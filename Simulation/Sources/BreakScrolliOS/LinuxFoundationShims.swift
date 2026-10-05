// Linux stand-ins for Apple-only Foundation APIs used by Shared/.
import Foundation

/// Where the simulated App Group container lives. Tests point it at a temp dir.
enum FakeAppGroup {
    static var containerURL: URL?
}

extension FileManager {
    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        FakeAppGroup.containerURL
    }
}

/// Serializes access like NSFileCoordinator and records nested coordination,
/// which can deadlock on iOS. Tests assert `nestedCoordinations == 0`.
final class NSFileCoordinator {
    struct ReadingOptions: OptionSet { let rawValue: Int }
    struct WritingOptions: OptionSet {
        let rawValue: Int
        static let forMerging = WritingOptions(rawValue: 1)
    }

    nonisolated(unsafe) static var depth = 0
    nonisolated(unsafe) static var nestedCoordinations = 0
    nonisolated(unsafe) static var writes = 0

    func coordinate(readingItemAt url: URL, options: ReadingOptions = [], error: UnsafeMutablePointer<NSError?>?, byAccessor reader: (URL) -> Void) {
        enter()
        defer { Self.depth -= 1 }
        reader(url)
    }

    func coordinate(writingItemAt url: URL, options: WritingOptions = [], error: UnsafeMutablePointer<NSError?>?, byAccessor writer: (URL) -> Void) {
        enter()
        defer { Self.depth -= 1 }
        Self.writes += 1
        writer(url)
    }

    private func enter() {
        if Self.depth > 0 { Self.nestedCoordinations += 1 }
        Self.depth += 1
    }
}
