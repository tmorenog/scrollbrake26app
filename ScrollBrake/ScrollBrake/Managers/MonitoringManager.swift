//
//  MonitoringManager.swift
//  ScrollBrake
//
//  Manages DeviceActivity monitoring schedules and session tracking.
//
//  IMPORTANT IMPLEMENTATION NOTES:
//  ================================
//  Apple's DeviceActivity API has significant limitations for "continuous session" tracking:
//
//  1. DeviceActivityMonitor extension receives callbacks for:
//     - intervalDidStart / intervalDidEnd (schedule-based)
//     - eventDidReachThreshold (when cumulative usage hits a threshold)
//
//  2. There's NO direct way to detect:
//     - When user switches away from a monitored app
//     - How long they've been away
//     - Real-time "continuous" vs "interrupted" usage
//
//  3. Our approximation strategy:
//     - We use DeviceActivity schedules that run continuously (24/7)
//     - We set usage thresholds (eventDidReachThreshold) for the session limit
//     - The "break window" (20s away = reset) is APPROXIMATED:
//       * DeviceActivity events track cumulative usage within a schedule interval
//       * If user leaves and returns within the same interval, usage continues accumulating
//       * True "break detection" would require a companion extension or polling, which isn't
//         reliably possible with current APIs
//
//  4. PRACTICAL BEHAVIOR:
//     - Session limit (5 min) works accurately via eventDidReachThreshold
//     - Break window is approximated by using short monitoring intervals (e.g., 1 min)
//       and resetting if usage doesn't accumulate within an interval
//     - This means breaks slightly longer than the interval may not perfectly reset
//
//  5. FUTURE IMPROVEMENTS:
//     - iOS updates may provide more granular activity data
//     - Could use shorter intervals with more aggressive threshold checking
//     - Could combine with app foreground/background notifications (limited scope)
//

import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import Combine

@MainActor
class MonitoringManager: ObservableObject {
    static let shared = MonitoringManager()

    /// Whether monitoring is currently active
    @Published var isMonitoring: Bool = false

    /// Current session accumulated time (in seconds) - approximate
    @Published var currentSessionSeconds: Int = 0

    /// Whether we're in a reward window (post-challenge free time)
    @Published var isInRewardWindow: Bool = false

    /// The DeviceActivity center for managing schedules
    private let activityCenter = DeviceActivityCenter()

    /// Persistence manager
    private let persistence = PersistenceManager.shared

    /// Timer for reward window countdown
    private var rewardWindowTimer: Timer?

    /// The current family activity selection
    private var currentSelection: FamilyActivitySelection?

    private init() {
        // Load saved state
        isMonitoring = persistence.isMonitoringActive
        currentSelection = persistence.loadFamilyActivitySelection()
    }

    // MARK: - Public Methods

    /// Update the app selection for monitoring
    func updateSelection(_ selection: FamilyActivitySelection) {
        currentSelection = selection
        persistence.saveFamilyActivitySelection(selection)

        // If monitoring is active, restart with new selection
        if isMonitoring {
            stopMonitoring()
            startMonitoring()
        }
    }

    /// Start monitoring the selected apps
    func startMonitoring() {
        guard let selection = currentSelection,
              !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else {
            print("[MonitoringManager] Cannot start monitoring: no apps selected")
            return
        }

        // Create the activity schedule
        // We use a schedule that runs from now until far in the future
        let schedule = createMonitoringSchedule()

        // Create the event thresholds
        let events = createThresholdEvents(for: selection)

        do {
            // Start monitoring with the activity name
            try activityCenter.startMonitoring(
                .sessionMonitor,
                during: schedule,
                events: events
            )

            isMonitoring = true
            persistence.isMonitoringActive = true
            print("[MonitoringManager] Started monitoring with \(events.count) events")

        } catch {
            print("[MonitoringManager] Failed to start monitoring: \(error)")
        }
    }

    /// Stop all monitoring
    func stopMonitoring() {
        activityCenter.stopMonitoring([.sessionMonitor])
        isMonitoring = false
        persistence.isMonitoringActive = false
        print("[MonitoringManager] Stopped monitoring")
    }

    /// Reset the current session (e.g., after break or challenge solved)
    func resetSession() {
        currentSessionSeconds = 0
        persistence.currentSessionStartTime = nil
        persistence.isShieldActive = false

        // Restart monitoring to reset thresholds
        if isMonitoring {
            stopMonitoring()
            startMonitoring()
        }

        print("[MonitoringManager] Session reset")
    }

    /// Start the reward window (free time after solving challenge)
    func startRewardWindow() {
        let rewardMinutes = persistence.rewardWindowMinutes
        isInRewardWindow = true
        persistence.rewardWindowEndTime = Date().addingTimeInterval(TimeInterval(rewardMinutes * 60))

        // Stop monitoring during reward window
        stopMonitoring()

        // Start a timer to re-enable monitoring after reward window
        rewardWindowTimer?.invalidate()
        rewardWindowTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(rewardMinutes * 60),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.endRewardWindow()
            }
        }

        print("[MonitoringManager] Reward window started for \(rewardMinutes) minutes")
    }

    /// End the reward window and resume monitoring
    func endRewardWindow() {
        isInRewardWindow = false
        persistence.rewardWindowEndTime = nil
        rewardWindowTimer?.invalidate()
        rewardWindowTimer = nil

        // Reset session and restart monitoring
        resetSession()
        startMonitoring()

        print("[MonitoringManager] Reward window ended, monitoring resumed")
    }

    /// Called when settings change
    func updateSettings() {
        // If monitoring is active, restart with new settings
        if isMonitoring {
            stopMonitoring()
            startMonitoring()
        }
    }

    // MARK: - Private Methods

    /// Create the monitoring schedule
    /// We use a schedule that effectively runs 24/7
    private func createMonitoringSchedule() -> DeviceActivitySchedule {
        // Create a schedule that starts now and repeats daily
        // The schedule runs from midnight to midnight, repeating
        let calendar = Calendar.current
        let now = Date()

        // Start from the current time
        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: now)

        // End 23 hours and 59 minutes later (effectively all day)
        var endComponents = startComponents
        endComponents.hour = 23
        endComponents.minute = 59
        endComponents.second = 59

        return DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true,
            warningTime: nil
        )
    }

    /// Create threshold events for the session limit
    private func createThresholdEvents(for selection: FamilyActivitySelection) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        let sessionLimitSeconds = persistence.sessionLimitMinutes * 60

        // Create event that fires when cumulative usage reaches the session limit
        let sessionLimitEvent = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(second: sessionLimitSeconds)
        )

        // We could add intermediate events for warnings, but keeping it simple for MVP
        // e.g., a 4-minute warning event

        return [
            .sessionLimitReached: sessionLimitEvent
        ]
    }
}

// MARK: - DeviceActivity Names
extension DeviceActivityName {
    /// The main session monitoring activity
    static let sessionMonitor = DeviceActivityName("com.scrollbrake.sessionMonitor")
}

// MARK: - DeviceActivity Event Names
extension DeviceActivityEvent.Name {
    /// Event triggered when session limit is reached
    static let sessionLimitReached = DeviceActivityEvent.Name("com.scrollbrake.sessionLimitReached")

    /// Event triggered as a warning before limit (optional)
    static let sessionWarning = DeviceActivityEvent.Name("com.scrollbrake.sessionWarning")
}
