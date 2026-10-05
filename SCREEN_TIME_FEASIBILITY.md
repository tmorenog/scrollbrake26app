# BreakScroll — Screen Time Feasibility

Status: Phase 0 research, written 2026-10-05.

Sources: Apple's developer documentation, read through its JSON endpoints (`developer.apple.com/tutorials/data/documentation/<path>.json`) on 2026-10-05. Each claim is tagged:

- **[DOC]**: stated in Apple's current documentation. The doc path is given.
- **[INFER]**: follows from documented behavior but isn't stated outright.
- **[DEVICE]**: not documented. It must be checked on physical iPhones before we rely on it. Each one has an experiment in section 6.

Nothing in this file comes from blog posts or sample projects.

---

## 1. Summary

| Question | Answer |
|---|---|
| Does enforcement run on the child's phone? | **Yes.** BreakScroll is installed on the child's phone, authorized with `.child`, and its extensions shield apps there. [DOC] |
| Can the parent's phone push rules to the child's phone through Screen Time? | **No.** No Screen Time API sends schedules, events or shields from one device to another. [INFER] |
| Do we need our own sync? | **Yes, for remote rule changes and approvals.** Recommendation: **CloudKit with two `CKShare`s**. No custom backend. |
| Can the repeating "X minutes, intervention, X more minutes" loop work? | **Yes.** Restart monitoring after each unlock. The docs say a restarted event only counts usage from the restart. [DOC] See `REPEATING_INTERVALS.md`. |
| Can the shield open BreakScroll? | **Yes on iOS 26.5+** (`ShieldActionResponse.openParentalControlsApp`). [DOC] On older iOS it can't, so we fall back to a notification and the user opening the app. |
| Can the child ask for more time from the shield? | **iOS 26.4+** adds up to three secondary-button submenu items. [DOC] Sending the request to the parent needs our CloudKit layer. |
| Can the parent see app names and icons? | **Yes, inside our UI**, through `Label(token)`. Tokens work across devices in the same Family Sharing group. [DOC] |
| Can the child delete the app or sign out of iCloud? | **No**, while `.child` authorization is active. [DOC] |

**Smallest viable architecture.** BreakScroll runs on both phones. The child's phone does all enforcement offline. A CloudKit share carries versioned rules and parent decisions to the child, and a second share carries daily summaries and requests back to the parent.

---

## 2. Answers to the 20 questions

### Parent/child architecture

**1. Can the parent's phone use `FamilyActivityPicker` to choose apps from the child's phone?**
Documented as yes. From `familycontrols/familyactivitypicker`: *"A `FamilyActivityPicker` shown on a parent device only displays applications and websites from authorized child devices within the Family Sharing Group. A `FamilyActivityPicker` shown on an individually authorized device includes applications and websites from that same device."* [DOC]

Open points:
- There's no parameter to limit the picker to one child or one device. With several children, the parent sees all authorized children's apps together. [DOC: the only initializers are `init(selection:)`, `init(headerText:footerText:selection:)` and the `familyActivityPicker(...)` modifier.]
- The docs don't say whether the parent's phone itself needs Family Controls authorization for the picker to work. They also don't say what happens if the parent authorized `.individual` for Self-Control Mode. The note implies the picker would then show the parent's own apps. [DEVICE: experiment E3]
- **Fallback if E3 fails:** the parent picks apps on the child's phone during setup. The picker there shows the child's apps. We then sync the tokens up so the parent can still see labels.

**2. Can the parent set schedules and events that are enforced on the child's phone?**
Not directly. `DeviceActivityCenter` and `ManagedSettingsStore` act on **the device they run on**. `ManagedSettingsStore` is *"a data store that applies settings to the current user or device"* (`managedsettings/managedsettingsstore`), and no API takes a target device or member. [DOC + INFER] The parent's choices have to reach BreakScroll on the child's phone, which then calls `DeviceActivityCenter.startMonitoring` and sets `ManagedSettingsStore` locally.

**3. Where does the DeviceActivityMonitor extension run?**
On the monitored device, meaning the child's phone. *"Device Activity executes your code on a schedule without a child running your app."* (`managedsettings/connectionwithframeworks`) It runs even when the app isn't running. [DOC]

**4. What does Apple's infrastructure propagate automatically?**
- **Authorization.** It's granted on the child's phone, with the parent authenticating on that phone. Apple tells the parent's account about it. [DOC] Apple doesn't document a callback on the parent's phone. [INFER]
- **Tokens.** `ApplicationToken`: *"`FamilyActivitySelection` provides tokens that devices within the same Family Sharing group can use to identify applications."* [DOC] So a token picked on the parent's phone means the same app on the child's phone.
- **Picker contents.** The parent's picker can list apps from the child's devices (Q1). [DOC]
- **Usage reports.** `DeviceActivityReport` on the parent's phone can show children's usage (`users: .children` in Apple's example), rendered inside the sandboxed report extension. [DOC]

**5. What doesn't propagate?**
The `FamilyActivitySelection` the parent picked, BreakScroll's rules, schedules and thresholds, shield state, intervention state, approval requests and decisions, and any numbers we generate. [INFER: no API exists for any of these.]

**6. What do we need for parent/child sync?**
| Option | Verdict |
|---|---|
| **CloudKit** | **Recommended.** Native, needs no server, and has accounts and permissions built in. Parent and child have different Apple Accounts, so their private databases are separate. A `CKShare` lets one account give another `readOnly` or `readWrite` access, and CloudKit's server enforces it. [DOC: `cloudkit/ckshare/participantpermission` has `none`, `readOnly` and `readWrite`.] |
| iCloud key-value storage | **No.** It only syncs between devices of the *same* Apple Account. |
| Custom backend | Not needed for the MVP. We'd need it later for Android parents or the web. |
| Screen Time itself | Has no transport for app data (Q2, Q5). |

**7. Can a child request extra time from our shield?**
Partly. On iOS 26.4+, `ShieldConfiguration.secondaryButtonSubmenuItems` adds up to three custom items, such as "15 more minutes". Taps arrive in `ShieldActionDelegate` as `firstSecondarySubmenuItemPressed` and so on. [DOC] Getting the request to the parent is up to us (Q9).

**8. Can `ShieldActionDelegate` open BreakScroll?**
- **iOS 26.5+: yes.** `ShieldActionResponse.openParentalControlsApp`: *"An instruction for the system to open your parental controls app that is responsible for shielding the application or web browser."* [DOC, not marked beta]
- **Before 26.5: no.** The other responses are `.close` (closes the shielded app), `.none`, and `.defer` (*"the shield redraws its UI"*). [DOC] The existing scrollbrake26app code wrongly assumes `.defer` opens the app.

**9. Can the shield send an "Ask Parent" request directly?**
Apple's own description of `.defer` uses that case: *"for example, if your extension on a client device sends a remote request to a parent or guardian's device"*. [DOC] Apple sandboxes the **Shield Configuration** and **Device Activity Report** extensions against network access [DOC], but **not** the Shield Action extension. So the Shield Action extension can probably write a CloudKit record. [INFER, DEVICE: experiment E7]

**10. The App Store–compliant flow (Phase 2)**
1. Shield secondary button opens a submenu with "Ask a parent".
2. `ShieldActionDelegate` writes an `ApprovalRequest` record to the child-owned shared CloudKit zone, then returns `.defer`. The shield redraws to show "Request sent".
3. If the extension can't reach the network (E7 fails), it saves the request in the App Group. The next time BreakScroll opens or does a background refresh, it sends it.
4. The parent's phone gets a CloudKit subscription push and shows a notification.

**11. Can the parent approve an unlock remotely?**
Yes, using our CloudKit layer. Screen Time itself has no remote-approval channel. [INFER]

**12. How does the child's phone learn about an approval?**
The parent writes an `ApprovalDecision` to the **parent-owned** zone, which the child can only read, so the child can't fake an approval. The child's phone learns about it through, in order of reliability:
- a CloudKit database subscription silent push, which wakes the app in the background (Apple doesn't guarantee delivery)
- a `BGAppRefreshTask` fetch
- a fetch when the app comes to the front.

Pushes only trigger a refresh. The CloudKit record is what's authoritative.

**13. Can the parent see which app triggered an intervention?**
Only through how we design events. `eventDidReachThreshold(_:activity:)` gives an event *name*, not a token. [DOC] If a rule uses one event per app token, we know which token fired and can send the encoded token to the parent, who renders `Label(token)`. For the MVP, one rule has one combined event, so we only know which **rule** fired.

**14. What Screen Time data can be shown to the parent?**
- Data **BreakScroll creates itself**: interventions, stops, continuations and approvals.
- **Token labels** through `Label(token)`.
- Apple's usage charts rendered **inside** our `DeviceActivityReport` extension. The extension is sandboxed, so we can't take numbers out of it. [DOC]

`FamilyActivityData` and `.approvedWithDataAccess` (iOS 26.4) expose bundle IDs and domain names, but only to customers in the EU, and only one app per device can hold that status. [DOC] **We won't use it.** It goes against the privacy principle, and it isn't available outside the EU anyway.

**15. What stays as opaque tokens?**
Apps, categories and web domains, everywhere outside the Shield Configuration and Report extensions. The Shield Configuration extension gets display names and bundle IDs, but runs sandboxed: *"prevents your extension from making network requests or moving sensitive content outside the extension's address space."* [DOC] `ShieldActionDelegate` only gets tokens. [DOC]

**16. Can BreakScroll show app names and icons in the parent's UI?**
Yes, with `Label(applicationToken)`, `FamilyActivityTitleView` or `FamilyActivityIconView` (`familycontrols/displayingactivitylabels`). [DOC] Whether a token from the child's phone renders on the parent's phone is implied by the ApplicationToken doc. [DEVICE: experiment E4]

**17. What protections come with `.child` authorization?**
From `familycontrols`: *"authorizing an app prevents the child user from deleting the app that provides parental controls. In addition, while a device has at least one app authorized for parental controls by a parent or guardian, the user can't sign out of iCloud."* Also: *"After a parent or guardian authorizes your app, only a parent or guardian can delete your app."* [DOC]

Extra `ManagedSettingsStore` settings we can turn on in Family Mode [DOC]:
- `dateAndTime.requireAutomaticDateAndTime`: stops clock tampering.
- `application.denyAppRemoval`: stops deleting the *monitored* apps to reset them.
- `passcode.lockPasscode` and `account.lockAccounts`: optional. These are invasive, so they're off by default and the parent opts in.

**18. What happens when the child tries to get around it?**
| Child action | Expected result | Basis |
|---|---|---|
| Deletes BreakScroll | Blocked. Only a parent or guardian can delete it. | [DOC] |
| Signs out of iCloud | Blocked while `.child` authorization is active. | [DOC] |
| Turns off permissions | The child can't revoke. A parent can in Settings, which makes `authorizationStatus` change and **voids all tokens**. We watch for this and show "Family Controls was turned off". | [DOC] `AuthorizationCenter` and `FamilyActivitySelection` |
| Changes time zone | Usage *"accumulates based on the time zone of the scheduled start date"*. The schedule stays tied to its original time zone. Day boundaries in our own state must use the same calendar. | [DOC] `DeviceActivityEvent` |
| Changes date/time | Blocked if `requireAutomaticDateAndTime` is on. | [DOC] |
| Restarts the phone | Shields are stored by the system and monitoring is registered with the system. Both should survive. Our state is saved in the App Group. | [INFER, DEVICE: E8] |
| Turns off Wi-Fi or cellular | Local enforcement is unaffected. Only approvals and sync stop. | [INFER: everything runs on-device] |
| Low Power Mode | Nothing documented. Background refresh may be delayed, and sync becomes slower. | [DEVICE] |
| Force-quits BreakScroll | Extensions run separately from the app. *"Device Activity executes your code … without a child running your app."* | [DOC] |
| Turns on Screen Time with another app | `authorizationConflict`: *"Another authorized app already provides parental controls."* | [DOC] |

**19. What does Apple enforce, and what's on us?**
- **Apple enforces:** the app can't be deleted; iCloud can't be signed out; the shield overlay can't be bypassed from inside the shielded app; usage is counted by the system; date/time lock, if we turn it on.
- **We must handle:** re-arming monitoring after each unlock, idempotent callbacks, saving state across process death, ignoring stale or duplicate threshold callbacks, checking that parent actions are really from the parent (CloudKit permissions), detecting when authorization is revoked, and never shielding essential apps (section 4).

**20. Entitlements**
From `familycontrols/requesting-the-family-controls-entitlement`: *"If your app includes a Screen Time API app extension such as Device Activity Monitor, Device Activity Report, Shield Action, or Shield Configuration, submit the same request for the extension."* [DOC]

| Target | `com.apple.developer.family-controls` | App Group | iCloud/CloudKit | Push |
|---|---|---|---|---|
| BreakScroll (app) | ✅ | ✅ | ✅ (Phase 10) | ✅ (Phase 10) |
| Device Activity Monitor | ✅ | ✅ | – | – |
| Shield Configuration | ✅ | ✅ (read-only use) | – (sandboxed) | – |
| Shield Action | ✅ | ✅ | ✅ (Phase 11, if E7 passes) | – |
| Device Activity Report (later) | ✅ | ✅ | – (sandboxed) | – |

Developer builds can use the capability straight away. App Store distribution needs Apple to approve each bundle ID. [DOC]

---

## 3. Product decisions forced by the APIs

1. **Minimum iOS version: 17.4.** That's where `DeviceActivityEvent(..., includesPastActivity:)` arrives, which lets us control past usage explicitly. Features that need 26.4 or 26.5 are switched on at runtime:
   - iOS 26.5+: Continue on the shield opens BreakScroll directly.
   - iOS 17.4–26.4: the Continue button closes the app with `.close`. The shield text says "Open BreakScroll to continue", and the Shield Action extension posts a local notification that deep-links to the challenge. [DEVICE: E6, which checks that a local notification can be posted from the extension] **The user should confirm this choice.** Requiring iOS 26.5 removes the fallback but excludes older devices.
2. **The parent picks apps on their own phone, if E3 passes.** Otherwise they pick during setup on the child's phone.
3. **No custom child picker.** Apple gives no API to list family members (no such API exists in FamilyControls). The child joins by accepting a CloudKit share on their phone. The parent types a nickname such as "Pau". We never read the child's name from the system.
4. **"I'm Done"** leaves the shield up. The next time the child opens the app, the shield shows "Continue" again. There's no cooldown in the MVP.
5. **Combined time per rule.** One `DeviceActivityEvent` per rule covers all its tokens. For per-app intervals, the parent makes one rule per app.
6. **Active hours** become the `DeviceActivitySchedule` interval. Inactive weekdays are filtered in our own code (see `REPEATING_INTERVALS.md`), which keeps us at **one activity per rule**. Apple's limit is 20 activities per app. [DOC]
7. **Essential apps.** We only shield what the parent explicitly picked. When whole categories are picked, a warning lists what they include. We can't filter out Phone or Messages by token, because tokens are opaque.

---

## 4. Smallest viable architecture

```
 Parent iPhone (BreakScroll)                    Child iPhone (BreakScroll, .child auth)
 ─────────────────────────────                  ──────────────────────────────────────────
 FamilyActivityPicker ──tokens──┐               App:   challenge UI, rule cache, rearm
 Rules editor (Face ID gate)    │               DAM ext: threshold → shield, record
                                ▼               ShieldConfig ext: copy (reads App Group)
      CloudKit zone "family-<id>" (parent-owned) ShieldAction ext: Continue / Done / Ask
        rules, decisions, overrides  ──CKShare readOnly──▶ child's shared DB
      CloudKit zone "child-<id>" (child-owned)
        daily summaries, approval requests ◀──CKShare readOnly── parent's shared DB
```

- **Trust model.** The parent owns the config zone and the child only has `readOnly` access, enforced by CloudKit's server. The child owns the report zone and the parent only has `readOnly` access. Changing rules, approving, overriding and revoking can only be done by the zone owner (the parent). Sensitive parent actions are also gated with `LocalAuthentication` on the parent's phone. No `isParent` flag in UserDefaults is trusted.
- **Local enforcement** on the child's phone never needs the network. The child's phone caches the newest valid config, keeping the highest version it has seen.
- **Shared code** goes in the `BreakScrollCore` Swift package. It has no Apple-only imports, so the rules, state machine, challenge generator, escalation and sync merging can be unit-tested on any platform. The iOS layer turns opaque `FamilyActivitySelection` data into tokens.

---

## 5. What Apple's APIs rule out

| Desired UX | Status |
|---|---|
| Shield, Continue, open BreakScroll on iOS < 26.5 | Not possible. Fallback: notification, or the child opens the app themselves. |
| Custom controls on the shield (timer, text field) | Not possible. Only an icon, title, subtitle, two buttons and (26.4+) three submenu items. [DOC] |
| "Next break in about 7 minutes" on the child's home screen | Not possible. No API reports current progress toward an event's threshold. `eventWillReachThresholdWarning` exists, but its timing is set when monitoring is registered. **We won't fake a countdown.** |
| Parent sees exact times the child opened apps | Not exposed outside the sandboxed report extension, and against our privacy principle. |
| Picking which child the picker shows | No API. |
| Blocking Phone, Messages or Settings by mistake | We can't *detect* these in a token selection. We can only warn about broad categories. |

---

## 6. Experiments to run on devices (they block the phases shown)

| ID | Question | Phase |
|---|---|---|
| E1 | Re-arming with `startMonitoring` (same name, new event, `includesPastActivity: false`) fires again after X more minutes | 7 |
| E2 | Does time spent on a shielded app count toward a threshold? | 7 |
| E3 | The parent's picker shows the child's apps; does the parent's own authorization state change that? | 3 |
| E4 | A token picked on the parent's phone shields the right app on the child's phone, and `Label(token)` renders on both | 3 |
| E5 | `.openParentalControlsApp` opens BreakScroll, and the app can read App Group state to show the challenge | 6 |
| E6 | Can the Shield Action extension post a local notification (iOS < 26.5 fallback)? | 6 |
| E7 | Can the Shield Action extension write to CloudKit? | 11 |
| E8 | Do shields and monitoring survive a reboot with BreakScroll never opened afterwards? | 7 |

Steps for each are in `REPEATING_INTERVALS.md` §5.
