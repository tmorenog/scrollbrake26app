import Foundation

open class UNNotificationContent {}
open class UNMutableNotificationContent: UNNotificationContent {
    public override init() {}
    open var title = ""
    open var body = ""
}
open class UNNotificationTrigger {}
open class UNNotificationRequest {
    public let identifier: String
    public let content: UNNotificationContent
    public init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = content
    }
}
public struct UNAuthorizationOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let alert = UNAuthorizationOptions(rawValue: 1), sound = UNAuthorizationOptions(rawValue: 2)
}
open class UNUserNotificationCenter {
    nonisolated(unsafe) static let instance = UNUserNotificationCenter()
    public static func current() -> UNUserNotificationCenter { instance }
    public var delivered: [UNNotificationRequest] = []
    open func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {
        delivered.append(request)
        completionHandler?(nil)
    }
    open func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
}
