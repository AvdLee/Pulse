// The MIT License (MIT)
//
// Copyright (c) 2020–2023 Alexander Grebenyuk (github.com/kean).

import CoreData
import Pulse
import Combine
import SwiftUI

final class ConsoleViewModel: ObservableObject {
    let title: String
    let isNetwork: Bool
    let store: LoggerStore
    let source: ConsoleSource

    let listViewModel: ConsoleListViewModel

#if os(iOS) || os(macOS)
    let insightsViewModel: InsightsViewModel
    @available(iOS 15, *)
    var searchViewModel: ConsoleSearchViewModel {
        _searchViewModel as! ConsoleSearchViewModel
    }
    private var _searchViewModel: AnyObject?

    let searchBarViewModel: ConsoleSearchBarViewModel
#endif

#if os(macOS)
    let tableViewModel: ConsoleTableViewModel
    let textViewModel: ConsoleTextViewModel
#endif

    let searchCriteriaViewModel: ConsoleSearchCriteriaViewModel
    let index: LoggerStoreIndex

    let logCountObserver: ManagedObjectsCountObserver
    let taskCountObserver: ManagedObjectsCountObserver

    let router = ConsoleRouter()

    var isViewVisible: Bool = false {
        didSet { refreshListsVisibility() }
    }

#warning("reimplement this")
    var isSearching = false {
        didSet { refreshListsVisibility() }
    }

    var mode: ConsoleMode {
        didSet { prepare(for: mode) }
    }

    var bindingForNetworkMode: Binding<Bool> {
        Binding(get: {
            self.mode == .tasks
        }, set: {
            self.mode = $0 ? .tasks : .all
        })
    }

    var onDismiss: (() -> Void)?

    private var cancellables: [AnyCancellable] = []

    init(store: LoggerStore, source: ConsoleSource = .store, mode: ConsoleMode = .all, isOnlyNetwork: Bool = false) {
        switch source {
        case .store:
            self.title = isOnlyNetwork ? "Network" : "Console"
        case .entities(let title, _):
            self.title = title
        }

        self.store = store
        self.source = source
        self.mode = mode
        self.isNetwork = isOnlyNetwork

        func makeDefaultSearchCriteria() -> ConsoleSearchCriteria {
            var criteria = ConsoleSearchCriteria()
            if store.isArchive {
                criteria.shared.dates.startDate = nil
            }
            if case .entities = source {
                criteria.shared.dates.startDate = nil
            }
            return criteria
        }

        self.index = LoggerStoreIndex(store: store)
        self.searchCriteriaViewModel = ConsoleSearchCriteriaViewModel(criteria: makeDefaultSearchCriteria(), index: index)
        self.listViewModel = ConsoleListViewModel(store: store, source: source, criteria: searchCriteriaViewModel)
#if os(iOS) || os(macOS)
        self.insightsViewModel = InsightsViewModel(store: store)
        self.searchBarViewModel = ConsoleSearchBarViewModel()
        if #available(iOS 15, *) {
            self._searchViewModel = ConsoleSearchViewModel(list: listViewModel, index: index, searchBar: searchBarViewModel)
        }
#endif

#if os(macOS)
        self.tableViewModel = ConsoleTableViewModel(store: store, source: source, criteria: searchCriteriaViewModel)
        self.textViewModel = ConsoleTextViewModel(store: store, source: source, criteria: searchCriteriaViewModel, router: router)
#endif

        self.logCountObserver = ManagedObjectsCountObserver(
            entity: LoggerMessageEntity.self,
            context: store.viewContext,
            sortDescriptior: NSSortDescriptor(keyPath: \LoggerMessageEntity.createdAt, ascending: false)
        )

        self.taskCountObserver = ManagedObjectsCountObserver(
            entity: NetworkTaskEntity.self,
            context: store.viewContext,
            sortDescriptior: NSSortDescriptor(keyPath: \NetworkTaskEntity.createdAt, ascending: false)
        )

        bind()

        if mode != .all {
            prepare(for: mode)
        }
    }

    private func bind() {
        searchCriteriaViewModel.bind(listViewModel.$entities)

        searchCriteriaViewModel.$criteria
            .combineLatest(searchCriteriaViewModel.$isOnlyErrors)
            .sink { [weak self] in
                self?.refreshCountObservers(criteria: $0, isOnlyError: $1)
            }
            .store(in: &cancellables)
    }

    private func refreshCountObservers(criteria: ConsoleSearchCriteria, isOnlyError: Bool) {
        func makePredicate(for mode: ConsoleMode) -> NSPredicate? {
            ConsoleDataSource.makePredicate(mode: mode, source: source, criteria: criteria, isOnlyErrors: isOnlyError)
        }
        logCountObserver.setPredicate(makePredicate(for: .logs))
        taskCountObserver.setPredicate(makePredicate(for: .tasks))
    }

    private func prepare(for mode: ConsoleMode) {
        searchCriteriaViewModel.mode = mode
        listViewModel.mode = mode
#if os(macOS)
        tableViewModel.mode = mode
        textViewModel.mode = mode
#endif
    }

    private func refreshListsVisibility() {
        listViewModel.isViewVisible = !isSearching && isViewVisible
#if os(iOS)
        if #available(iOS 15, *) {
            searchViewModel.isViewVisible = isSearching && isViewVisible
        }
#endif
    }

    func prepareForSharing(as output: ShareOutput, _ completion: @escaping (ShareItems?) -> Void) {
        ShareService.share(listViewModel.entities, store: store, as: output, completion)
    }
}

enum ConsoleSource {
    case store
    case entities(title: String, entities: [NSManagedObject])
}

enum ConsoleMode: String {
    case all
    case logs
    case tasks
}
