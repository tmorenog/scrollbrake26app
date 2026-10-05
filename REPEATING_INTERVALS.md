# Repeating Intervals: X minutes, intervention, X more minutes

This is the highest-priority technical question. Evidence tags (**[DOC]**, **[INFER]**, **[DEVICE]**) mean the same as in `SCREEN_TIME_FEASIBILITY.md`.

## 1. What Apple documents

| Fact | Source |
|---|---|
| A threshold fires *"once the combination of specified applications, categories, and webDomains have been in use longer than the event's threshold **within the activity's scheduled interval**"*. So thresholds count total usage within an interval. | [DOC] `DeviceActivityEvent.init(applications:categories:webDomains:threshold:)` |
| *"When your app calls `startMonitoring(_:during:events:)` and the event's schedule is active, the system will **only consider the person's device activity when it starts monitoring the event**."* | [DOC] same page, Important box |
| `includesPastActivity` (iOS 17.4+) controls this explicitly. `false` means only usage after the call counts. | [DOC] `DeviceActivityEvent/includesPastActivity` |
| *"If the app already monitored the activity, this method **overwrites** the previous schedule and events."* | [DOC] `startMonitoring(_:during:events:)` |
| The extension *"may begin receiving callbacks as soon as the system calls this method if the activity's scheduled interval is ongoing"*. `intervalDidStart` fires right away if the current time is inside the interval. | [DOC] `startMonitoring`, `DeviceActivitySchedule.init` |
| `intervalDidEnd` fires *"when your app stops monitoring an activity with an ongoing interval"*. | [DOC] `intervalDidEnd(for:)` |
| Limits: at most **20 activities** per app and its extensions. Schedule intervals must be **at least 15 minutes and at most 1 week**. | [DOC] `MonitoringError.excessiveActivities`, `.intervalTooShort`, `.intervalTooLong` |
| Usage *"accumulates based on the time zone of the scheduled start date"*. | [DOC] `DeviceActivityEvent` |
| Callbacks only arrive while the device is in use. | [DOC] `DeviceActivityCenter` |

There's no documented limit on the number of *events* per activity. [DEVICE]

## 2. Options compared

**A. Restart (re-arm) monitoring after each unlock. Chosen.**
After a challenge is solved, call `startMonitoring(ruleActivity, during: activeHours, events: [nextEvent])`. `nextEvent` has `threshold = X` and `includesPastActivity: false`. Per the documentation above, usage counts again from zero.
- Pros: directly documented. Each cycle's settings (escalation stage, a changed rule) apply at re-arm. Time spent shielded, paused or in the challenge never counts, because the counter only restarts at unlock.
- Cons: re-arming fires `intervalDidStart` again (we handle that, see §3). Someone has to re-arm: the app after a correct answer, which is reliable because the app is in front then.

**B. Cumulative thresholds at 15, 30, 45 and so on in one registration.**
- Pros: no re-arm.
- Cons: time spent blocked or "I'm Done" breaks don't count, so thresholds drift away from "X minutes since unlock". Escalation and rule changes still need a re-registration. The number of events is capped and unknown. If the child keeps the app shielded but still switches into it, whether that counts is unknown (E2). **Rejected as the main mechanism.**

**C. The extension re-arms itself.**
`DeviceActivityCenter` works from extensions [DOC: "enables an application's extension to start monitoring"]. But re-arming must happen *at unlock*, which happens in the app. We use C only to *re-establish* monitoring in `intervalDidStart` if the config version changed.

**D. Separate daily cap.**
A second activity per rule (`daily.<ruleID>`) that's never re-armed during the day, with `threshold = dailyMax`. When it fires, it shields the selection with reason `.dailyLimitReached`. A math challenge can't lift it. Only a parent override can.

## 3. The design

```
activity name  : "rule.<ruleUUID>"              (one per rule, ≤ 19 rules with daily caps reserved)
event name     : "rule.<ruleUUID>.g<generation>" (generation increments at each arm)
schedule       : intervalStart = activeStart, intervalEnd = activeEnd, repeats: true
```

1. **Arm** (`generation += 1`): save `armedGeneration` in the App Group, **then** call `startMonitoring`.
2. **Threshold** callback: parse the generation from the event name. If it isn't the current `armedGeneration`, it's stale or a duplicate, so **ignore it**. If today isn't an active weekday (`WeeklySchedule`), ignore it. Otherwise apply the shield and move to `shielded`.
3. **Unlock** (correct answer):
   - **re-arm first**
   - then remove the shield
   - then move to `monitoring`.

   If re-arming throws, **keep the shield** and show a retry. Family Mode must never fail open.
4. **`intervalDidStart`**: re-arming triggers this callback too, so it must be idempotent. We store `dayKey` (`yyyy-MM-dd` in the schedule's calendar). A new day resets `continuationsToday`. The same day changes nothing.
5. **`intervalDidEnd`** (leaving active hours): remove the BreakScroll shield and set state to `inactive`. The daily-cap shield stays until midnight.
6. **Midnight**: when a repeating interval rolls over, the event counter starts again [INFER from "within the activity's scheduled interval"]. Rolling over also resets `continuationsToday`. If the child is shielded at that moment, they stay shielded until they choose Continue. The pause and challenge still apply.
7. **Inactive weekdays**: we don't use one activity per weekday (which could reach 7 per rule). The threshold handler checks `WeeklySchedule.isActive(on:)`.
8. **Rule change** (new config version): re-arm at once with the new X. The current cycle's usage is dropped, so the child gets a fresh X. That's acceptable.

Everything above except the iOS API calls lives in `BreakScrollCore`, mainly `InterventionEngine` and `MonitoringNames` (`BreakScrollCore/Sources/BreakScrollCore/Engine/InterventionEngine.swift`), and is covered by unit tests (`swift test`).

## 4. Questions answered and open

| Question | Answer |
|---|---|
| Does restarting monitoring reset accumulated usage? | **Yes** for events with `includesPastActivity: false` while the schedule is active. [DOC] Confirm with E1. |
| What happens on stop and restart? | `intervalDidEnd`, then `intervalDidStart` straight away. [DOC] We handle both idempotently. |
| Are thresholds cumulative? | Within the activity's interval. [DOC] |
| Can events be replaced on the fly? | Yes. `startMonitoring` overwrites. [DOC] |
| Limit on events? | Not documented. We use 1 per rule plus the daily cap. |
| Can extensions schedule the next threshold? | The API is available to them [DOC]. We avoid depending on it (option C). |
| Does usage while shielded count? | **Unknown.** E2 checks this. Re-arming makes it irrelevant for the repeat loop, but it matters for the daily cap. |
| Across midnight? | A new interval starts and our day state resets. [INFER] Check with E1b. |
| Can the monitor extension change the configuration? | Yes. [DOC] We use it only for re-syncing (option C). |

## 5. On-device experiment protocol

**Setup for every experiment.** Xcode 26+. Build the `scrollbrake26app` scheme in **Debug** to a physical iPhone, with all four targets signed with the same team and App Group. Use Settings → Screen Time → turn on Screen Time. Add `-BreakScrollDebug 1` to the launch arguments. Watch logs in Console.app filtered to subsystem `com.breakscroll`.

**E1: re-arm resets usage (blocks Phase 7)**
1. In the debug panel, set the threshold to **1 min** and select one app, such as Safari or a test app.
2. Tap Start. Log: `armed rule=<id> gen=1 threshold=60s`.
3. Use the app for 70 seconds. Expect `threshold rule=<id> gen=1`, and the shield appears.
4. Solve the challenge. Expect `armed … gen=2`, then `shield removed`.
5. **Success:** the shield comes back after about 60 seconds more use, *not* straight away. Log: `threshold … gen=2`.
6. Repeat 3 times. If any re-shield happens within 10 seconds of unlock, past usage leaked into the count. Record the iOS version.

**E1b: midnight.** Set the device clock to automatic and the threshold to 2 minutes. Use the app from 23:59 to 00:02. Record whether the `gen` event fires and when `intervalDidStart` logs.

**E2: does shielded time count?** Turn on the daily-cap debug event at 2 minutes and the repeat threshold at 1 minute. Get shielded at 1 minute, then keep the shield in front for 3 minutes without unlocking. Success means the daily-cap event has **not** fired.

**E8: reboot.** Get shielded, then reboot and don't open BreakScroll. Success: the app is still shielded after the reboot. Then unlock and use it for X minutes. The threshold fires without opening BreakScroll first, which shows monitoring survived the reboot.

Record results in the table below.

| Exp | iOS | Device | Result | Date |
|---|---|---|---|---|
| E1 | | | | |
| E1b | | | | |
| E2 | | | | |
| E8 | | | | |
