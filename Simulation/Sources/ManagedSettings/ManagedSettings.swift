// Fake ManagedSettings. Tokens are opaque values tests create; shields are
// stored per named store in FakeShields so the simulated device can tell
// whether an app is blocked.
import Foundation

public struct Token<T>: Hashable, Codable {
    public let id: String
    public init(_ id: String) { self.id = id }
}

public struct Application {
    public let token: ApplicationToken?
    public init(token: ApplicationToken) { self.token = token }
}
public typealias ApplicationToken = Token<Application>

public struct ActivityCategory {
    public let token: ActivityCategoryToken?
    public init(token: ActivityCategoryToken) { self.token = token }
}
public typealias ActivityCategoryToken = Token<ActivityCategory>

public struct WebDomain {
    public let token: WebDomainToken?
    public init(token: WebDomainToken) { self.token = token }
}
public typealias WebDomainToken = Token<WebDomain>

public struct ShieldSettings {
    public enum ActivityCategoryPolicy<Activity> {
        case none
        case all(except: Set<Token<Activity>> = [])
        case specific(Set<ActivityCategoryToken>, except: Set<Token<Activity>> = [])
    }

    public var applications: Set<ApplicationToken>?
    public var applicationCategories: ActivityCategoryPolicy<Application>?
    public var webDomains: Set<WebDomainToken>?
    public var webDomainCategories: ActivityCategoryPolicy<WebDomain>?

    public init() {}

    var isEmpty: Bool {
        applications == nil && applicationCategories == nil && webDomains == nil && webDomainCategories == nil
    }

    func blocks(app: ApplicationToken, category: ActivityCategoryToken?) -> Bool {
        if applications?.contains(app) == true { return true }
        switch applicationCategories {
        case .specific(let categories, let except)?:
            return category.map(categories.contains) == true && !except.contains(app)
        case .all(let except)?:
            return !except.contains(app)
        case .none?, nil:
            return false
        }
    }
}

/// The simulated device's shield state, keyed by store name.
public enum FakeShields {
    public static var stores: [String: ShieldSettings] = [:]

    public static func reset() { stores = [:] }

    public static func isBlocked(app: ApplicationToken, category: ActivityCategoryToken?) -> Bool {
        stores.values.contains { $0.blocks(app: app, category: category) }
    }

    public static var activeStoreNames: [String] {
        stores.filter { !$0.value.isEmpty }.map(\.key).sorted()
    }
}

open class ManagedSettingsStore {
    public struct Name: Hashable {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Name("default")
    }

    let name: String
    public init() { name = Name.default.rawValue }
    public convenience init(named name: Name) {
        self.init(storeName: name.rawValue)
    }
    init(storeName: String) { name = storeName }

    public var shield: ShieldSettings {
        get { FakeShields.stores[name] ?? ShieldSettings() }
        set { FakeShields.stores[name] = newValue }
    }

    public func clearAllSettings() { FakeShields.stores[name] = nil }
}

public enum ShieldAction {
    case primaryButtonPressed, secondaryButtonPressed
    case firstSecondarySubmenuItemPressed, secondSecondarySubmenuItemPressed, thirdSecondarySubmenuItemPressed
}

public enum ShieldActionResponse { case close, `defer`, none, openParentalControlsApp }

open class ShieldActionDelegate {
    public init() {}
    open func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {}
    open func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {}
    open func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {}
}
