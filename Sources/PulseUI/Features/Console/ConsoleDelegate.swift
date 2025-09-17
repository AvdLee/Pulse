// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Pulse

/// Allows you to customize the console behavior.
public protocol ConsoleViewDelegate {
    /// Returns a title for the given task.
    func getTitle(for task: RSNetworkTaskEntity) -> String?
}

extension ConsoleViewDelegate {
    func getTitle(for task: RSNetworkTaskEntity) -> String? {
        if let taskDescription = task.taskDescription, !taskDescription.isEmpty {
            return taskDescription
        }
        return task.url
    }

    func getShortTitle(for task: RSNetworkTaskEntity) -> String {
        guard let title = getTitle(for: task) else {
            return ""
        }
        return URL(string: title)?.lastPathComponent ?? title
    }
}

struct DefaultConsoleViewDelegate: ConsoleViewDelegate {}
