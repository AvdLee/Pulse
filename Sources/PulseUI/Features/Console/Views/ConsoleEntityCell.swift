// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import SwiftUI
import Pulse
import CoreData

@available(iOS 15, macOS 13, visionOS 1.0, *)
struct ConsoleEntityCell: View {
    let entity: NSManagedObject
    @Binding var selection: ConsoleSelectedItem?
    
    var body: some View {
        switch LoggerEntity(entity) {
        case .message(let message):
            _ConsoleMessageCell(message: message, selection: $selection)
#if os(macOS)
                .listRowSeparator(.visible)
#endif
        case .task(let task):
            _ConsoleTaskCell(task: task, selection: $selection)
#if os(macOS)
                .listRowSeparator(.visible)
#endif
        }
    }
}

@available(iOS 15, macOS 13, visionOS 1.0, *)
private struct _ConsoleMessageCell: View {
    let message: RSLoggerMessageEntity

    @State private var shareItems: ShareItems?
    @Binding var selection: ConsoleSelectedItem?
    
    var body: some View {
#if os(iOS) || os(visionOS)
        let cell = ConsoleMessageCell(message: message, isDisclosureNeeded: true)
            .background(NavigationLink("", destination: ConsoleMessageDetailsView(message: message)).opacity(0))
#elseif os(macOS)
        let cell = ConsoleMessageCell(message: message)
            .consoleListItemSelectable(ConsoleSelectedItem.entity(message.objectID), selection: $selection)
#else
        // `id` is a workaround for macOS (needs to be fixed)
        let cell = NavigationLink(destination: ConsoleMessageDetailsView(message: message)) {
            ConsoleMessageCell(message: message)
        }
#endif

#if os(iOS) || os(macOS) || os(visionOS)
        cell.swipeActions(edge: .leading, allowsFullSwipe: true) {
            PinButton(viewModel: .init(message)).tint(.pink)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: { shareItems = ShareService.share(message, as: .html) }) {
                Label("Share", systemImage: "square.and.arrow.up.fill")
            }.tint(.blue)
        }
        .contextMenu {
            ContextMenu.MessageContextMenu(message: message, shareItems: $shareItems)
        }
#if os(iOS) || os(visionOS)
        .sheet(item: $shareItems, content: ShareView.init)
#else
        .popover(item: $shareItems, attachmentAnchor: .point(.leading), arrowEdge: .leading) { ShareView($0) }
#endif
#else
        cell
#endif
    }
}

@available(iOS 15, macOS 13, visionOS 1.0, *)
private struct _ConsoleTaskCell: View {
    let task: RSNetworkTaskEntity
    @State private var shareItems: ShareItems?
    @State private var sharedTask: RSNetworkTaskEntity?
    @Environment(\.store) private var store
    @EnvironmentObject private var environment: ConsoleEnvironment
    @Binding var selection: ConsoleSelectedItem?
    
    var body: some View {
#if os(iOS) || os(visionOS)
        let cell = ConsoleTaskCell(task: task, isDisclosureNeeded: true)
            .background(NavigationLink("", destination: inspector).opacity(0))
#elseif os(macOS)
        let cell = ConsoleTaskCell(task: task)
            .consoleListItemSelectable(ConsoleSelectedItem.entity(task.objectID), selection: $selection)
#else
        let cell = NavigationLink(destination: inspector) {
            ConsoleTaskCell(task: task)
        }
#endif

#if os(iOS) || os(macOS) || os(visionOS)
        cell.swipeActions(edge: .leading, allowsFullSwipe: true) {
            PinButton(viewModel: .init(task)).tint(.pink)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: {
#if os(iOS) || os(visionOS)
                shareItems = ShareService.share(task, as: .html, store: store)
#else
                sharedTask = task
#endif
            }) {
                Label("Share", systemImage: "square.and.arrow.up.fill")
            }.tint(.blue)
        }
        .contextMenu {
#if os(iOS) || os(visionOS)
            ContextMenu.NetworkTaskContextMenuItems(task: task, sharedItems: $shareItems)
#else
            ContextMenu.NetworkTaskContextMenuItems(task: task, sharedTask: $sharedTask)
#endif
        }
#if os(iOS) || os(visionOS)
        .sheet(item: $shareItems, content: ShareView.init)
#else
        .popover(item: $sharedTask, attachmentAnchor: .point(.leading), arrowEdge: .leading) { ShareNetworkTaskView(task: $0) }
#endif
#else
        cell
#endif
    }

    private var inspector: some View {
        // We don't own NavigationView, so we have to inject the dependencies
        NetworkInspectorView(task: task)
            .injecting(environment)
    }
}

struct ConsoleListItemSelectableViewModifier: ViewModifier {
    @Binding var selection: ConsoleSelectedItem?
    let selectedItem: ConsoleSelectedItem
    @State private var isAppActive: Bool = NSApp.isActive
    
    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
            .contentShape(Rectangle())
            .background {
                if selection == selectedItem {
                    Color(nsColor: NSApp.isActive ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor)
                }
            }
            .cornerRadius(4)
            .onTapGesture {
                selection = selectedItem
            }
            .tag(selectedItem)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                isAppActive = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                isAppActive = false
            }
            .padding(.horizontal, 10)
    }
}

extension View {
    func consoleListItemSelectable(_ selectedItem: ConsoleSelectedItem, selection: Binding<ConsoleSelectedItem?>) -> some View {
        self.modifier(ConsoleListItemSelectableViewModifier(selection: selection, selectedItem: selectedItem))
    }
}
