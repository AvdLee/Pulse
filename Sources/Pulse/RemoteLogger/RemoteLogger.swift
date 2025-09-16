// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Network
import Combine
import SwiftUI
import OSLog

public protocol RemoteLoggerDelegate: AnyObject {
    func didReceiveMessage(packet: RemoteLogger.Connection.Packet) throws
}

/// Connects to the remote server and sends logs remotely. In the current version,
/// a server is a Pulse Pro app for macOS).
///
/// - warning: Has to be used from the main thread.
public final class RemoteLogger: ObservableObject, RemoteLoggerConnectionDelegate {
    /// The store that the logger was initialized with.
    public private(set) var store: LoggerStore?

    public private(set) var isEnabled = false
    
    @Published
    public private(set) var connectionState: ConnectionState = .disconnected {
        didSet { os_log("Set public connection state %{public}@", log: log, "\(oldValue) → \(connectionState)") }
    }
    
    private weak var delegate: RemoteLoggerDelegate?
    private let rocketSimLoggerQueue = DispatchQueue(label: "com.swiftlee.rocketsim.logger", qos: .userInitiated, attributes: .concurrent)
    
    // Connections
    private var connectionCompletion: ((Result<Void, ConnectionError>) -> Void)?
    private var connection: Connection?
    private var connectionTimeoutItem: DispatchWorkItem?
    private var connectionError: ConnectionError?
    private var connectionRetryItem: DispatchWorkItem?
    private var timeoutDisconnectItem: DispatchWorkItem?
    private var pingItem: DispatchWorkItem?
    private var port: NWEndpoint.Port?
    private var parameters: NWParameters?
    private var retryCount = 0
    
    /// The number of times RocketSim Connect tries to reconnect to RocketSim.
    private var retryLimit = 3
    
    // Logging
    private var isLoggingPaused = true
    private var buffer: [LoggerStore.Event]? = []
    private var cancellable: AnyCancellable?
    private var getMockedResponseCompletions: [UUID: (URLSessionMockedResponse?) -> Void] = [:]

    // Private
    private var isInitialized = false
    private let log: OSLog
    private var lastReceivedCode: PacketCode?
    
    public enum ConnectionState {
        case disconnected, connecting, connected
    }
    
    public enum ConnectionError: Error, LocalizedError {
        case network(NWError)
        case waiting(NWError)
        case unknown(isProtected: Bool)

        public var errorDescription: String? {
            switch self {
            case .network(let error), .waiting(let error):
                return error.localizedDescription
            case .unknown(let isProtected):
                return "Connection failed. Please\(isProtected ? " verify the password and" : "") try again."
            }
        }
    }

    public static var shared: RemoteLogger { _shared.value }
    private static let _shared = Atomic(value: RemoteLogger())

    /// - parameter store: The store to be synced with the server. By default,
    /// ``LoggerStore/shared``. Only one store can be synced at at time.
    public func initialize(store: LoggerStore = .shared) {
        os_log("Initialize with store at %{private}@", log: log, "\(store.storeURL)")

        guard self.store !== store else {
            return
        }
        self.store = store
        if isInitialized {
            cancel()
        }
        isInitialized = true

        cancellable = store.events.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.didReceive(event: $0)
        }

        // The buffer is used to cover the time between the app launch and the
        // initial (automatic) connection to the server.
        let box = SendableBox(value: self)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
            box.value?.clearBuffer()
        }
    }

    private func clearBuffer() {
        buffer = nil
        os_log("Did clear buffer", log: log)
    }

    private init() {
        /// RocketSim Custom Logging:
        let isLogEnabled = ProcessInfo.processInfo.arguments.contains("-com.swiftlee.rocketsim.debug")
        self.log = isLogEnabled ? OSLog(subsystem: "com.swiftlee.rocketsim", category: "RocketSim.RemoteLogger") : .disabled
    }

    /// Enables remote logging. The logger will start searching for available
    /// servers.
    public func enable(port: NWEndpoint.Port, parameters: NWParameters, delegate: RemoteLoggerDelegate) {
        guard !isEnabled else { return }
        isEnabled = true
        self.delegate = delegate

        os_log("Will enable", log: log)
        defer { os_log("Did enable", log: log) }

        self.port = port
        self.parameters = parameters
        openRocketSimConnection()
    }

    /// Disables remote logging and disconnects from the server.
    public func disable() {
        guard isEnabled else { return }
        isEnabled = false

        os_log("Will disable", log: log)
        defer { os_log("Did disable", log: log) }

        cancel()
    }

    private func getDebugState() -> String {
        "(isEnabled: \(isEnabled))"
    }

    private func cancel() {
        os_log("Will cancel", log: log)
        defer { os_log("Did cancel", log: log) }

        disconnect()
    }

    // MARK: Connection
    private func openRocketSimConnection() {
        guard let port, let parameters else {
            os_log("Cancel RocketSim connection since port and parameters are missing", log: log)
            return
        }
        let newConnection = NWConnection(
            host: .name("localhost", nil),
            port: port,
            using: parameters
        )
        let connection = Connection(newConnection, delegate: self)
        self.connectionState = .connecting
        self.connection = connection

        connection.start(on: rocketSimLoggerQueue)
    }
    
    private func connectionDidTimeout(isProtected: Bool) {
        os_log("Connection did timeout", log: log)
        connectionCompletion?(.failure(self.connectionError ?? .unknown(isProtected: isProtected)))
        connectionCompletion = nil
        disconnect()
    }
    
    // MARK: RemoteLoggerConnectionDelegate

    public func connection(_ connection: Connection, didChangeState newState: NWConnection.State) {
        os_log("Connection did change state to %{public}@", log: log, "\(newState)")

        switch newState {
        case .ready:
            NSLog("RocketSim application detected, connecting...")
            handshakeWithServer()
        case .waiting(let error):
            os_log("Connection failed while waiting with error: %{public}@", log: log, type: .error, error.debugDescription)
            connectionError = .waiting(error)
            connectionState = .disconnected
            scheduleConnectionRetry()
        case .failed(let error):
            os_log("Connection failed with error: %{public}@", log: log, type: .error, error.debugDescription)
            
            logTroubleshootingMessage(for: error)
            connectionError = .network(error)
            connectionState = .disconnected
            scheduleConnectionRetry()
        default:
            break
        }
    }

    private func logTroubleshootingMessage(for error: Error) {
        if let nwError = error as? NWError, case .posix(let posixError) = nwError, posixError == .ECONNRESET {
            /// RocketSim probably closed, this is expected.
            NSLog("RocketSim application closed the connection.")
        } else {
            NSLog("""
            RocketSim Connect failed (2) with error: \(error.localizedDescription).
            
            To troubleshoot if this is unexpected:
            - Make sure to enable Local Network for RocketSim: System → Privacy → Local Network → Turn RocketSim on.
            - Enable debug logs by adding -com.swiftlee.rocketsim.debug 1 to your launch arguments.
            - If the issue remains, please contact support@rocketsim.app and share your console logs.
            """)
        }
    }
    
    public func connection(_ connection: Connection, didReceiveEvent event: Connection.Event) {
        switch event {
        case .packet(let packet):
            do {
                try didReceiveMessage(packet: packet)
            } catch {
                os_log("Failed to decode packet: %{public}@", log: log, type: .error, "\(error)")
            }
        case .error(let error):
            os_log("Connection received error while receiving data: %{public}@", log: log, type: .error, "\(error)")
            scheduleConnectionRetry()
        case .completed:
            break
        }
    }

    // MARK: Communication

    private func handshakeWithServer() {
        assert(connection != nil)

        os_log("Will send hello to the server", log: log)

        // Say "hello" to the server and share information about the client
        let body = PacketClientHello(
            version: Version.currentProtocolVersion.description,
            deviceId: getDeviceId() ?? getFallbackDeviceId(),
            deviceInfo: .make(),
            appInfo: .make(),
            session: store?.session
        )
        connection?.send(code: .clientHello, entity: body)

        // Set timeout and retry in case there was no response from the server
        let box = SendableBox(value: self)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(10)) {
            box.value?.handshakeDidTimeout()
        }
    }

    private func handshakeDidTimeout() {
        guard connectionState == .connecting else { return }
        os_log("The handshake with the server timed out", log: log)
        scheduleConnectionRetry()
    }

    private func didReceiveMessage(packet: Connection.Packet) throws {
        try delegate?.didReceiveMessage(packet: packet)
        
        let code = RemoteLogger.PacketCode(rawValue: packet.code)

        if let code {
            if code != lastReceivedCode {
                lastReceivedCode = code
                os_log("Did receive packet with code: %{public}@", log: log, type: .info, String(describing: code))
            }
        } else {
            os_log("Did receive packet with unsupported code: %{public}@", log: log, type: .info, String(describing: packet.code))
        }

        switch code {
        case .serverHello:
            let response = try? JSONDecoder().decode(ServerHelloResponse.self, from: packet.body)
            didConnectToServer(response: response)
        case .pause:
            isLoggingPaused = true
        case .resume:
            isLoggingPaused = false
            buffer?.forEach(send)
        case .ping:
            scheduleAutomaticDisconnect()
        case .message:
            guard let message = try? Message.decode(packet.body) else {
                return // New unsupported message
            }
            switch message.path {
            case .updateMocks:
                let mocks = try JSONDecoder().decode([URLSessionMock].self, from: message.data)
                URLSessionMockManager.shared.update(mocks)
            case .getMockedResponse, .openMessageDetails, .openTaskDetails:
                break // Server specific (should never happen)
            }
        default:
            break // Do nothing
        }
    }

    private func didConnectToServer(response: ServerHelloResponse?) {
        os_log("Did receive hello from server (version: %{public}@)", log: log, response?.version ?? "–")

        guard connectionState != .connected else { return }
        connectionState = .connected
        retryCount = 0

        NSLog("Connected to RocketSim 🚀")
        connectionCompletion?(.success(()))
        connectionCompletion = nil

        os_log("Did cancel connection timeout", log: log)
        connectionTimeoutItem?.cancel()
        connectionTimeoutItem = nil

        schedulePing()
    }

    private func scheduleConnectionRetry() {
        guard connectionRetryItem == nil else { return }
        guard retryCount < retryLimit else {
            NSLog("Failed to connect with RocketSim after \(retryLimit) attempts. Giving up... Make sure RocketSim is running and relaunch your app.")
            disconnect()
            return
        }
        retryCount += 1
        os_log("Schedule connection retry", log: log)

        cancelPingPong()

        let item = DispatchWorkItem { [weak self] in
            self?.retryConnection()
        }
        /// Slowly increase the retry delay to give the opportunity to launch RocketSim.
        let delayInSeconds = retryCount * 10
        NSLog("RocketSim Connect failed to establish connection. Retrying in \(delayInSeconds) seconds... (\(retryCount)/3)")
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delayInSeconds), execute: item)
        connectionRetryItem = item
    }

    private func retryConnection() {
        os_log("Retry connection", log: log)

        connectionRetryItem?.cancel()
        connectionRetryItem = nil

        connectionState = .disconnected
        
        openRocketSimConnection()
    }

    private func scheduleAutomaticDisconnect() {
        if timeoutDisconnectItem == nil {
            os_log("Schedule automatic disconnect", log: log)
        }

        timeoutDisconnectItem?.cancel()
        timeoutDisconnectItem = nil

        guard connectionState == .connected else { return }

        let item = DispatchWorkItem { [weak self] in
            self?.didTriggerAutomaticDisconnect()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5), execute: item)
        timeoutDisconnectItem = item
    }

    private func didTriggerAutomaticDisconnect() {
        guard connectionState == .connected else { return }
        os_log("Haven't received pings from a server in a while, disconnecting", log: log)
        connectionState = .disconnected
        scheduleConnectionRetry()
    }

    private func schedulePing() {
        connection?.send(code: .ping)

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.connectionState == .connected else { return }
            self.schedulePing()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: item)
        pingItem = item
    }

    public func disconnect() {
        guard connectionState != .disconnected else { return }
        connectionState = .disconnected // The order is important

        os_log("Disconnect from the current server", log: log)

        connection?.cancel()

        connectionRetryItem?.cancel()
        connectionRetryItem = nil

        connectionTimeoutItem?.cancel()
        connectionTimeoutItem = nil

        cancelPingPong()
    }

    private func cancelPingPong() {
        timeoutDisconnectItem?.cancel()
        timeoutDisconnectItem = nil

        pingItem?.cancel()
        pingItem = nil
    }

    // MARK: Logging

    private func didReceive(event: LoggerStore.Event) {
        if isLoggingPaused {
            buffer?.append(event)
        } else {
            send(event: event)
        }
    }

    private func send(event: LoggerStore.Event) {
        switch event {
        case .messageStored(let message):
            connection?.send(code: .storeEventMessageStored, entity: message)
        case .networkTaskCreated(let event):
            connection?.send(code: .storeEventNetworkTaskCreated, entity: event)
        case .networkTaskProgressUpdated(let event):
            connection?.send(code: .storeEventNetworkTaskProgressUpdated, entity: event)
        case .networkTaskCompleted(let message):
            do {
                let data = try RemoteLogger.PacketNetworkMessage.encode(message)
                connection?.send(code: .storeEventNetworkTaskCompleted, data: data)
            } catch {
                os_log("Failed to encode network message %{public}@", log: log, type: .error, "\(error)")
            }
        case .customMessage(let code, let data):
            connection?.send(code: code.rawValue, data: data)
            os_log("Did send custom message with code: %{public}@", log: log, type: .info, String(describing: code))
        }
    }

    // MARK: Mocks

    func getMockedResponse(for mock: URLSessionMock, _ completion: @escaping (URLSessionMockedResponse?) -> Void) {
        guard let connection = connection else {
            return completion(nil)
        }
        connection.sendMessage(path: .getMockedResponse(mockID: mock.mockID)) { data, _ in
            if let data = data, let response = try? JSONDecoder().decode(URLSessionMockedResponse.self, from: data) {
                completion(response)
            } else {
                completion(nil)
            }
        }
    }
    
    // MARK: Details
    
    public func showDetails(for message: RSLoggerMessageEntity) {
        connection?.sendMessage(path: .openMessageDetails, entity: LoggerStore.Event.MessageCreated(message))
    }
    
    public func showDetails(for task: NetworkTaskEntity) {
        connection?.sendMessage(path: .openTaskDetails, entity: LoggerStore.Event.NetworkTaskCompleted(task))
    }
    
    // MARK: Custom Messages
    public func send(code: PacketCode, data: Data = Data()) {
        didReceive(event: .customMessage(code: code, data: data))
    }
    
    public func send<T: Codable>(code: PacketCode, entity: T) {
        do {
            let data = try JSONEncoder().encode(entity)
            didReceive(event: .customMessage(code: code, data: data))
        } catch {
            os_log("Failed to encode custom message %{public}@", log: log, type: .error, "\(error)")
        }
    }
}

// MARK: - Helpers

private func getFallbackDeviceId() -> UUID {
    let key = "com-swiftlee-rocketsim-connect-device-id"
    if let value = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: value) {
        return uuid
    }
    let id = UUID()
    UserDefaults.standard.set(id.uuidString, forKey: key)
    return id
}

private struct SendableBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
}

private extension NWBrowser.Result {
    var name: String? {
        switch endpoint {
        case .service(let name, _, _, _):
            return name
        default:
            return nil
        }
    }

    var isProtected: Bool {
        switch metadata {
        case .bonjour(let record):
            return record["protected"].map { Bool($0) } == true
        case .none:
            return false
        @unknown default:
            return false
        }
    }
}

extension RemoteLogger.ConnectionState {
    var description: String {
        switch self {
        case .disconnected: return "idle"
        case .connecting: return "connecting"
        case .connected: return "connected"
        }
    }
}

extension [String: NWBrowser.Result] {
    func preferredRocketSimServer() -> (String, NWBrowser.Result)? {
        let baseName = "rocketsim"
        var highestNumber: Int?
        var matchResult: (String, NWBrowser.Result)?
        
        for (name, result) in self {
            let serverName = name.lowercased()
            if serverName == baseName {
                if matchResult == nil {
                    matchResult = (name, result) // default to base name
                }
            } else if let match = serverName.range(of: #"^\#(baseName) \((\d+)\)$"#, options: .regularExpression) {
                let numberString = String(serverName[match]).dropFirst(baseName.count + 2).dropLast()
                if let number = Int(numberString), number > (highestNumber ?? -1) {
                    highestNumber = number
                    matchResult = (name, result)
                }
            }
        }
        
        return matchResult
    }
}
