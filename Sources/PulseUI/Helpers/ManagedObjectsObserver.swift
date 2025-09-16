// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreData
import Pulse
import Combine
import SwiftUI

final class ManagedObjectsObserver<T: NSManagedObject>: NSObject, NSFetchedResultsControllerDelegate {
    @Published private(set) var objects: [T] = []

    private let controller: NSFetchedResultsController<T>

    init(request: NSFetchRequest<T>,
         context: NSManagedObjectContext,
         cacheName: String? = nil) {
        self.controller = NSFetchedResultsController(fetchRequest: request, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: cacheName)
        super.init()

        try? controller.performFetch()
        objects = controller.fetchedObjects ?? []

        controller.delegate = self
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        objects = self.controller.fetchedObjects ?? []
    }
}

extension ManagedObjectsObserver where T == RSLoggerMessageEntity {
    static func pins(for context: NSManagedObjectContext) -> ManagedObjectsObserver {
        let request = NSFetchRequest<RSLoggerMessageEntity>(entityName: "\(RSLoggerMessageEntity.self)")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RSLoggerMessageEntity.createdAt, ascending: false)]
        request.predicate = NSPredicate(format: "isPinned == YES")

        return ManagedObjectsObserver(request: request, context: context, cacheName: "com.github.pulse.pins-cache")
    }
}

extension ManagedObjectsObserver where T == RSLoggerSessionEntity {
    static func sessions(for context: NSManagedObjectContext) -> ManagedObjectsObserver {
        let request = NSFetchRequest<RSLoggerSessionEntity>(entityName: "\(RSLoggerSessionEntity.self)")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RSLoggerSessionEntity.createdAt, ascending: false)]

        return ManagedObjectsObserver(request: request, context: context, cacheName: "com.github.pulse.sessions-cache")
    }
}
