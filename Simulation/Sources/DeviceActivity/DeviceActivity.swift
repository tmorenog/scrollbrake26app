// Fake DeviceActivity: a simulated device with a clock, per-second app usage,
// schedules and threshold events, following Apple's documentation:
//
// - Usage counts while an app is frontmost; a shielded app can't be used.
// - An event fires once its apps/categories have been used for `threshold`
//   within the current interval. With includesPastActivity = false, only
//   usage after startMonitoring counts ("the system will only consider the
//   person's device activity when it starts monitoring the event").
// - An event with no apps, categories or domains counts ALL activity.
// - startMonitoring overwrites an activity. If its interval is ongoing,
//   intervalDidStart is delivered right away. (We also deliver
//   intervalDidEnd for the replaced interval: the worst case.)
// - Interval callbacks arrive only while the device is in use.
// - Callbacks run after the caller returns, in a fresh monitor instance, like
//   a separate extension process.
// - At most 20 activities; schedules must be 15 minutes to 1 week long.
import Foundation
import ManagedSettings

public struct DeviceActivityName: Hashable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct DeviceActivitySchedule {
    public let intervalStart: DateComponents
    public let intervalEnd: DateComponents
    public let repeats: Bool

    public init(intervalStart: DateComponents, intervalEnd: DateComponents, repeats: Bool, warningTime: DateComponents? = nil) {
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.repeats = repeats
    }

    static func seconds(_ c: DateComponents) -> Int {
        (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }

    var startSeconds: Int { Self.seconds(intervalStart) }
    var endSeconds: Int { Self.seconds(intervalEnd) }

    var lengthSeconds: Int {
        endSeconds > startSeconds ? endSeconds - startSeconds : 86_400 - startSeconds + endSeconds
    }

    func secondOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        let p = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (p.hour ?? 0) * 3600 + (p.minute ?? 0) * 60 + (p.second ?? 0)
    }

    func contains(_ date: Date, _ calendar: Calendar) -> Bool {
        let t = secondOfDay(date, calendar)
        return startSeconds < endSeconds ? (t >= startSeconds && t < endSeconds) : (t >= startSeconds || t < endSeconds)
    }

    /// Start of the interval containing `date` (call only when `contains`).
    func intervalStart(containing date: Date, _ calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: date)
        var start = midnight.addingTimeInterval(TimeInterval(startSeconds))
        if start > date { start = calendar.date(byAdding: .day, value: -1, to: start)! }
        return start
    }
}

public struct DeviceActivityEvent {
    public struct Name: Hashable {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(rawValue: String) { self.rawValue = rawValue }
    }

    public let applications: Set<ApplicationToken>
    public let categories: Set<ActivityCategoryToken>
    public let webDomains: Set<WebDomainToken>
    public let threshold: DateComponents
    public let includesPastActivity: Bool

    public init(applications: Set<ApplicationToken> = [], categories: Set<ActivityCategoryToken> = [],
                webDomains: Set<WebDomainToken> = [], threshold: DateComponents, includesPastActivity: Bool) {
        self.applications = applications
        self.categories = categories
        self.webDomains = webDomains
        self.threshold = threshold
        self.includesPastActivity = includesPastActivity
    }

    public var includesAllActivity: Bool { applications.isEmpty && categories.isEmpty && webDomains.isEmpty }

    var thresholdSeconds: Int { DeviceActivitySchedule.seconds(threshold) + (threshold.day ?? 0) * 86_400 }

    func matches(_ app: FakeApp) -> Bool {
        includesAllActivity || applications.contains(app.token) || app.category.map(categories.contains) == true
    }
}

public struct FakeApp {
    public let token: ApplicationToken
    public let category: ActivityCategoryToken?
    public init(_ id: String, category: String? = nil) {
        token = ApplicationToken(id)
        self.category = category.map { ActivityCategoryToken($0) }
    }
}

public struct DeviceActivityCenter {
    public enum MonitoringError: Error {
        case excessiveActivities, intervalTooLong, intervalTooShort, invalidDateComponents, unauthorized
    }

    public init() {}

    public func startMonitoring(_ activity: DeviceActivityName, during schedule: DeviceActivitySchedule,
                                events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]) throws {
        try FakeDevice.shared.startMonitoring(activity.rawValue, schedule, events)
    }

    public func stopMonitoring(_ activities: [DeviceActivityName] = []) {
        FakeDevice.shared.stopMonitoring(activities.map(\.rawValue))
    }

    public var activities: [DeviceActivityName] {
        FakeDevice.shared.activityNames.map { DeviceActivityName($0) }
    }
}

open class DeviceActivityMonitor {
    public init() {}
    open func intervalDidStart(for activity: DeviceActivityName) {}
    open func intervalDidEnd(for activity: DeviceActivityName) {}
    open func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {}
}

public final class FakeDevice {
    public static let shared = FakeDevice()

    public var now = Date()
    public var calendar = Calendar(identifier: .gregorian)
    /// Creates the monitor extension's principal object for each callback.
    public var makeMonitor: (() -> DeviceActivityMonitor)?
    /// Makes the next N startMonitoring calls throw.
    public var failNextStartMonitoring = 0
    /// Whether the system authorizes monitoring (false after revocation).
    public var isAuthorized = true

    public private(set) var callbackLog: [String] = []
    public private(set) var startMonitoringLog: [(activity: String, events: [String], thresholds: [Int], at: Date)] = []

    final class Activity {
        let schedule: DeviceActivitySchedule
        /// `used` is the event's qualifying usage in the current interval.
        var events: [(name: String, event: DeviceActivityEvent, fired: Bool, used: Int)]
        let armedAt: Date
        var intervalStart: Date?
        init(schedule: DeviceActivitySchedule, events: [(String, DeviceActivityEvent, Bool)], armedAt: Date) {
            self.schedule = schedule
            self.events = events.map { (name: $0.0, event: $0.1, fired: $0.2, used: 0) }
            self.armedAt = armedAt
        }
    }

    private var activities: [String: Activity] = [:]
    private var usage: [(at: Date, app: FakeApp)] = []
    private var pending: [() -> Void] = []

    public var activityNames: [String] { activities.keys.sorted() }

    public func reset(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
        activities = [:]
        usage = []
        pending = []
        callbackLog = []
        startMonitoringLog = []
        failNextStartMonitoring = 0
        isAuthorized = true
    }

    public func thresholds(for activity: String) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: (activities[activity]?.events ?? []).map { ($0.name, $0.event.thresholdSeconds) })
    }

    public func eventIncludesPastActivity(_ activity: String) -> [Bool] {
        activities[activity]?.events.map(\.event.includesPastActivity) ?? []
    }

    // MARK: - DeviceActivityCenter

    func startMonitoring(_ name: String, _ schedule: DeviceActivitySchedule, _ events: [DeviceActivityEvent.Name: DeviceActivityEvent]) throws {
        guard isAuthorized else { throw DeviceActivityCenter.MonitoringError.unauthorized }
        if failNextStartMonitoring > 0 {
            failNextStartMonitoring -= 1
            throw DeviceActivityCenter.MonitoringError.excessiveActivities
        }
        if activities[name] == nil && activities.count >= 20 {
            throw DeviceActivityCenter.MonitoringError.excessiveActivities
        }
        if schedule.lengthSeconds < 15 * 60 { throw DeviceActivityCenter.MonitoringError.intervalTooShort }
        if schedule.lengthSeconds > 7 * 86_400 { throw DeviceActivityCenter.MonitoringError.intervalTooLong }

        if activities[name]?.intervalStart != nil {
            enqueue("intervalDidEnd", name) { $0.intervalDidEnd(for: DeviceActivityName(name)) }
        }
        let activity = Activity(schedule: schedule, events: events.map { ($0.key.rawValue, $0.value, false) }, armedAt: now)
        activities[name] = activity
        startMonitoringLog.append((name, events.keys.map(\.rawValue), events.values.map(\.thresholdSeconds), now))
        if schedule.contains(now, calendar) {
            let start = schedule.intervalStart(containing: now, calendar)
            activity.intervalStart = start
            // includesPastActivity: count what was already used this interval.
            for index in activity.events.indices where activity.events[index].event.includesPastActivity {
                let event = activity.events[index].event
                activity.events[index].used = usage.filter { $0.at > start && event.matches($0.app) }.count
            }
            enqueue("intervalDidStart", name) { $0.intervalDidStart(for: DeviceActivityName(name)) }
        }
    }

    func stopMonitoring(_ names: [String]) {
        let targets = names.isEmpty ? Array(activities.keys) : names
        for name in targets {
            guard let activity = activities.removeValue(forKey: name) else { continue }
            if activity.intervalStart != nil {
                enqueue("intervalDidEnd", name) { $0.intervalDidEnd(for: DeviceActivityName(name)) }
            }
        }
    }

    // MARK: - Simulation

    /// The person uses `app` for up to `seconds`, one second at a time. Stops
    /// early when the app is shielded. Returns the seconds actually used.
    @discardableResult
    public func use(_ app: FakeApp, for seconds: Int) -> Int {
        drain()
        var used = 0
        for _ in 0..<seconds {
            if FakeShields.isBlocked(app: app.token, category: app.category) { break }
            now = now.addingTimeInterval(1)
            usage.append((now, app))
            used += 1
            updateIntervals()
            count(app)
            checkThresholds()
            drain()
        }
        return used
    }

    /// Time passes with the device asleep: no callbacks are delivered.
    public func sleep(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    /// The device is picked up (in use) without using a monitored app.
    public func wake() {
        updateIntervals()
        drain()
    }

    /// Runs queued extension callbacks, including any they cause.
    public func drain() {
        while !pending.isEmpty {
            pending.removeFirst()()
        }
    }

    private func enqueue(_ kind: String, _ activity: String, extra: String = "", _ call: @escaping (DeviceActivityMonitor) -> Void) {
        pending.append { [weak self] in
            guard let self, let monitor = self.makeMonitor?() else { return }
            self.callbackLog.append("\(kind) \(activity)\(extra)")
            call(monitor)
        }
    }

    private func updateIntervals() {
        for (name, activity) in activities.sorted(by: { $0.key < $1.key }) {
            let inside = activity.schedule.contains(now, calendar)
            let currentStart = inside ? activity.schedule.intervalStart(containing: now, calendar) : nil
            if let start = activity.intervalStart, start != currentStart {
                activity.intervalStart = nil
                enqueue("intervalDidEnd", name) { $0.intervalDidEnd(for: DeviceActivityName(name)) }
                if !activity.schedule.repeats { continue }
            }
            if activity.intervalStart == nil, let currentStart {
                activity.intervalStart = currentStart
                for index in activity.events.indices {
                    activity.events[index].fired = false
                    activity.events[index].used = 0
                }
                enqueue("intervalDidStart", name) { $0.intervalDidStart(for: DeviceActivityName(name)) }
            }
        }
    }

    /// One second of `app` counts toward every matching event whose interval
    /// is running. Usage before an event was armed never reaches it, unless it
    /// includes past activity (counted when armed, above).
    private func count(_ app: FakeApp) {
        for activity in activities.values where activity.intervalStart != nil {
            for index in activity.events.indices where activity.events[index].event.matches(app) {
                activity.events[index].used += 1
            }
        }
    }

    private func checkThresholds() {
        for (name, activity) in activities.sorted(by: { $0.key < $1.key }) {
            guard activity.intervalStart != nil else { continue }
            for index in activity.events.indices where !activity.events[index].fired {
                let event = activity.events[index].event
                if activity.events[index].used >= event.thresholdSeconds {
                    activity.events[index].fired = true
                    let eventName = activity.events[index].name
                    enqueue("eventDidReachThreshold", name, extra: " \(eventName)") {
                        $0.eventDidReachThreshold(DeviceActivityEvent.Name(eventName), activity: DeviceActivityName(name))
                    }
                }
            }
        }
    }
}
