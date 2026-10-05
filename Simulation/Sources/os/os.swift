// Stand-in for Apple's os.Logger. Messages are kept so tests can assert on logs.
public enum LogPrivacy { case `public`, `private` }

public struct LogMessage: ExpressibleByStringInterpolation {
    public let text: String
    public init(stringLiteral value: String) { text = value }
    public init(stringInterpolation: Interpolation) { text = stringInterpolation.text }

    public struct Interpolation: StringInterpolationProtocol {
        var text = ""
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) { text += literal }
        public mutating func appendInterpolation(_ value: String, privacy: LogPrivacy = .private) { text += value }
        public mutating func appendInterpolation(_ value: Int, privacy: LogPrivacy = .private) { text += String(value) }
    }
}

public enum FakeLog {
    public static var lines: [String] = []
}

public struct Logger {
    let category: String
    public init(subsystem: String, category: String) { self.category = category }
    public func info(_ message: LogMessage) { FakeLog.lines.append("[\(category)] \(message.text)") }
    public func notice(_ message: LogMessage) { info(message) }
    public func error(_ message: LogMessage) { FakeLog.lines.append("[\(category)] ERROR \(message.text)") }
    public func fault(_ message: LogMessage) { FakeLog.lines.append("[\(category)] FAULT \(message.text)") }
}
