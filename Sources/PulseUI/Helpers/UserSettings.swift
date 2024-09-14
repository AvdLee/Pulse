// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import Pulse
import Combine

/// Allows you to control Pulse appearance and other settings programmatically.
public final class UserSettings: ObservableObject {
    public static let shared = UserSettings()

    /// The console default mode.
    @AppStorage("com.github.kean.pulse.console.mode")
    public var mode: ConsoleMode = .network

    /// The line limit for messages in the console. By default, `3`.
    @AppStorage("com.github.kean.pulse.consoleCellLineLimit")
    public var lineLimit: Int = 3

    /// Enables link detection in the response viewier. By default, `false`.
    @AppStorage("com.github.kean.pulse.linkDetection")
    public var isLinkDetectionEnabled = false

    /// The default sharing output type. By default, ``ShareStoreOutput/store``.
    @AppStorage("com.github.kean.pulse.sharingOutput")
    public var sharingOutput: ShareStoreOutput = .store

    /// HTTP headers to display in a Console. By default, empty.
    public var displayHeaders: [String] {
        get { decode(rawDisplayHeaders) ?? [] }
        set { rawDisplayHeaders = encode(newValue) ?? "[]" }
    }

    @AppStorage("com.github.kean.pulse.display.headers")
    var rawDisplayHeaders: String = "[]"

    /// If `true`, the network inspector will show the current request by default.
    /// If `false`, show the original request.
    @AppStorage("com.github.kean.pulse.showCurrentRequest")
    public var isShowingCurrentRequest = true

    /// The allowed sharing options.
    public var allowedShareStoreOutputs: [ShareStoreOutput] {
        get { decode(rawAllowedShareStoreOutputs) ?? [] }
        set { rawAllowedShareStoreOutputs = encode(newValue) ?? "[]" }
    }

    @AppStorage("com.github.kean.pulse.allowedShareStoreOutputs")
    var rawAllowedShareStoreOutputs: String = "[]"

    /// If enabled, the console stops showing the remote logging option.
    @AppStorage("com.github.kean.pulse.isRemoteLoggingAllowed")
    public var isRemoteLoggingHidden = false

    /// Task cell display options.
    public var displayOptions: ConsoleDisplayOptions {
        get {
            if let options = cachedDisplayOptions {
                return options
            }
            let options = decode(rawDisplayOptions) ?? ConsoleDisplayOptions()
            cachedDisplayOptions = options
            return options
        }
        set {
            cachedDisplayOptions = newValue
            rawDisplayOptions = encode(newValue) ?? "{}"
        }
    }

    var cachedDisplayOptions: ConsoleDisplayOptions?

    @AppStorage("com.github.kean.pulse.DisplayOptions")
    var rawDisplayOptions: String = "{}"
}

private func decode<T: Decodable>(_ string: String) -> T? {
    let data = string.data(using: .utf8) ?? Data()
    return (try? JSONDecoder().decode(T.self, from: data))
}

private func encode<T: Encodable>(_ value: T) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}
