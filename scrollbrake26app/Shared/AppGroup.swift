//
//  AppGroup.swift
//  Shared by the app and all three extensions.
//

import Foundation
import os

enum AppGroup {
    /// Must match `com.apple.security.application-groups` in every target's entitlements.
    static let identifier = "group.com.scrollbrake26app.shared"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// Filter Console.app on subsystem `com.breakscroll` (see REPEATING_INTERVALS.md §5).
enum Log {
    static let subsystem = "com.breakscroll"
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let monitor = Logger(subsystem: subsystem, category: "monitor")
    static let shield = Logger(subsystem: subsystem, category: "shield")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let app = Logger(subsystem: subsystem, category: "app")
}
