import Foundation

/// Matches `Calendar.component(.weekday, from:)`: 1 = Sunday … 7 = Saturday.
public enum Weekday: Int, Codable, CaseIterable, Comparable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let weekend: Set<Weekday> = [.saturday, .sunday]
    public static let all = Set(Weekday.allCases)
}

/// A wall-clock time. `24:00` is allowed as an end-of-day marker.
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    public static let startOfDay = TimeOfDay(hour: 0)
    public static let endOfDay = TimeOfDay(hour: 24)

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public var isValid: Bool {
        (0...23).contains(hour) && (0...59).contains(minute) || (hour == 24 && minute == 0)
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// When interventions apply. Outside these hours selected apps are not interrupted.
///
/// If `end <= start` the window crosses midnight (e.g. 20:00–02:00) and belongs
/// to the weekday on which it starts.
public struct WeeklySchedule: Codable, Equatable, Sendable {
    public var activeDays: Set<Weekday>
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(activeDays: Set<Weekday>, start: TimeOfDay, end: TimeOfDay) {
        self.activeDays = activeDays
        self.start = start
        self.end = end
    }

    public static let always = WeeklySchedule(activeDays: Weekday.all, start: .startOfDay, end: .endOfDay)

    /// The default from the product spec: every day, 7:00 AM – 10:30 PM.
    public static let daytime = WeeklySchedule(
        activeDays: Weekday.all,
        start: TimeOfDay(hour: 7),
        end: TimeOfDay(hour: 22, minute: 30)
    )

    /// Apple rejects DeviceActivity schedules shorter than 15 minutes
    /// (`DeviceActivityCenter.MonitoringError.intervalTooShort`).
    public static let minimumIntervalMinutes = 15

    public var crossesMidnight: Bool { end <= start }

    public var durationMinutes: Int {
        crossesMidnight
            ? (24 * 60 - start.minutesSinceMidnight) + end.minutesSinceMidnight
            : end.minutesSinceMidnight - start.minutesSinceMidnight
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case noActiveDays
        case invalidTime
        case intervalTooShort
    }

    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        if activeDays.isEmpty { errors.append(.noActiveDays) }
        if !start.isValid || !end.isValid || start == .endOfDay { errors.append(.invalidTime) }
        if durationMinutes < Self.minimumIntervalMinutes { errors.append(.intervalTooShort) }
        return errors
    }

    /// Whether interventions apply at `date`.
    public func isActive(at date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekdayRaw = parts.weekday,
              let weekday = Weekday(rawValue: weekdayRaw),
              let hour = parts.hour, let minute = parts.minute else { return false }
        let now = hour * 60 + minute

        if !crossesMidnight {
            return activeDays.contains(weekday)
                && now >= start.minutesSinceMidnight
                && now < end.minutesSinceMidnight
        }
        // Late part of a window that started today.
        if activeDays.contains(weekday) && now >= start.minutesSinceMidnight {
            return true
        }
        // Early part of a window that started yesterday.
        let yesterday = Weekday(rawValue: (weekdayRaw + 5) % 7 + 1)!
        return activeDays.contains(yesterday) && now < end.minutesSinceMidnight
    }

    /// The calendar day an intervention belongs to, e.g. "2026-10-05".
    /// Use the same calendar (and time zone) that the DeviceActivity schedule uses.
    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
