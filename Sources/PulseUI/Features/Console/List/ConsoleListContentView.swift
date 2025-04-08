// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

import CoreData
import Pulse
import Combine
import SwiftUI

@available(iOS 15, macOS 13, visionOS 1.0, *)
struct ConsoleListContentView: View {
    @EnvironmentObject var viewModel: ConsoleListViewModel

#if os(macOS)
    let proxy: ScrollViewProxy
    let bottomID: Namespace.ID
    @Binding var selection: ConsoleSelectedItem?
    @SceneStorage("com-rocketsim-connect-is-now-enabled") private var isNowEnabled = true
#endif

    var body: some View {
#if os(iOS) || os(visionOS)
        if !viewModel.pins.isEmpty, !viewModel.isShowingFocusedEntities {
            ConsoleListPinsSectionView(viewModel: viewModel)
            if !viewModel.entities.isEmpty {
                PlainListGroupSeparator()
            }
        }
#endif

#if os(iOS) || os(macOS) || os(visionOS)
        if let sections = viewModel.sections, !sections.isEmpty {
            ForEach(sections, id: \.name) {
                ConsoleListGroupedSectionView(section: $0, viewModel: viewModel, selection: $selection)
            }
        } else {
            plainView
        }
#else
        plainView
#endif
    }

    @ViewBuilder
    private var plainView: some View {
            ForEach(viewModel.visibleEntities, id: \.objectID) { entity in
                let objectID = entity.objectID
                ConsoleEntityCell(entity: entity, selection: $selection)
                    .id(objectID)
                Divider()
#if os(iOS) || os(visionOS)
                    .onAppear { viewModel.onAppearCell(with: objectID) }
                    .onDisappear { viewModel.onDisappearCell(with: objectID) }
#endif
            }
#if os(macOS)
        bottomAnchorView
#else
        footerView
#endif
    }

    @ViewBuilder
    private var footerView: some View {
        if let session = viewModel.previousSession, !viewModel.isShowingFocusedEntities {
            Button(action: { viewModel.buttonShowPreviousSessionTapped(for: session) }) {
                Text("Show Previous Session")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                Spacer()
                Text(session.formattedDate(isCompact: false))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
#if os(iOS) || os(visionOS)
            .listRowSeparator(.hidden, edges: .bottom)
#endif
        }
    }

#if os(macOS)
    // This view is used to keep scroll to the bottom and keep track of the
    // scroll position (near bottom or not).
    private var bottomAnchorView: some View {
        HStack {
            Text("Waiting for new requests...")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical)
        
        }
            .frame(minHeight: 1)
            .id(bottomID)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .onAppear {
                nowModeChange?.cancel()
                withAnimation {
                    isNowEnabled = true
                }
            }
            .onDisappear {
                // The scrolling with ScrollViewProxy is unreliable, and this cell
                // occasionally disappears.
                delayNowModeChange {
                    guard viewModel.isViewVisible else { return }
                    withAnimation {
                        isNowEnabled = false
                    }
                }
            }
    }
#endif
}

#if os(macOS)
private var nowModeChange: DispatchWorkItem?

private func delayNowModeChange(_ closure: @escaping () -> Void) {
    nowModeChange?.cancel()
    let item = DispatchWorkItem(block: closure)
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(64), execute: item)
    nowModeChange = item
}

#endif

#if os(iOS) || os(visionOS)
@available(iOS 15, macOS 13, visionOS 1.0, *)
struct ConsoleStaticList: View {
    let entities: [NSManagedObject]

    var body: some View {
        List {
            ForEach(entities, id: \.objectID, content: ConsoleEntityCell.init)
        }
        .listStyle(.plain)
#if os(iOS) || os(visionOS)
        .environment(\.defaultMinListRowHeight, 8)
#endif
    }
}
#endif
