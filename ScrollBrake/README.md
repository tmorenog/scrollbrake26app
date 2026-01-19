# ScrollBrake

An iOS app that enforces usage limits on distracting apps using Apple's Screen Time APIs.

## Overview

ScrollBrake helps you manage your screen time by:
- Monitoring usage of selected apps (TikTok, Instagram, YouTube, etc.)
- Blocking access after a configurable session limit (default: 5 minutes)
- Requiring you to solve a math problem to unlock apps
- Providing a short "reward window" before monitoring resumes

## Requirements

- **iOS 16.0+** (Screen Time APIs require iOS 16+)
- **Xcode 15.0+**
- **Apple Developer Account** (required for Family Controls entitlement)
- **Physical iOS Device** (Screen Time APIs don't work in Simulator)

## Project Setup (Step by Step)

### 1. Create New Xcode Project

1. Open Xcode
2. File → New → Project
3. Choose "App" under iOS
4. Configure:
   - Product Name: `ScrollBrake`
   - Team: Your Apple Developer Team
   - Organization Identifier: `com.yourname` (or your identifier)
   - Interface: SwiftUI
   - Language: Swift
5. Create project

### 2. Add Source Files

Copy all Swift files from this repository into your Xcode project:

**Main App (ScrollBrake/)**
- `ScrollBrakeApp.swift`
- `ContentView.swift`
- `Views/AppSelectionView.swift`
- `Views/MathGateView.swift`
- `Views/SettingsView.swift`
- `Managers/AuthorizationManager.swift`
- `Managers/MonitoringManager.swift`
- `Managers/ShieldManager.swift`
- `Models/SessionState.swift`
- `Persistence/PersistenceManager.swift`
- `Extensions/URLHandler.swift`

### 3. Create Extensions

You need to create 3 extensions. For each:

#### DeviceActivityMonitor Extension
1. File → New → Target
2. Search for "Device Activity Monitor Extension"
3. Name it `DeviceActivityMonitorExtension`
4. Copy `DeviceActivityMonitorExtension.swift` into it

#### Shield Configuration Extension
1. File → New → Target
2. Search for "Shield Configuration Extension"
3. Name it `ShieldConfigurationExtension`
4. Copy `ShieldConfigurationExtension.swift` into it

#### Shield Action Extension
1. File → New → Target
2. Search for "Shield Action Extension"
3. Name it `ShieldActionExtension`
4. Copy `ShieldActionExtension.swift` into it

### 4. Configure Capabilities & Entitlements

#### For Main App:
1. Select the main app target
2. Go to "Signing & Capabilities"
3. Add "Family Controls" capability
4. Add "App Groups" capability
   - Add group: `group.com.scrollbrake.shared`

#### For Each Extension:
Repeat the above for all 3 extensions, ensuring:
- Family Controls is enabled
- App Groups has the same group ID: `group.com.scrollbrake.shared`

### 5. Update Bundle Identifiers

Update `PersistenceManager.swift` if your bundle identifier is different:

```swift
static let appGroupIdentifier = "group.com.YOURBUNDLE.shared"
```

### 6. Configure Info.plist

The main app's Info.plist needs:

```xml
<!-- Screen Time Usage Description -->
<key>NSFamilyControlsUsageDescription</key>
<string>ScrollBrake needs Screen Time access to monitor and limit your app usage.</string>

<!-- URL Scheme for deep linking -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.scrollbrake.app</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>scrollbrake</string>
        </array>
    </dict>
</array>
```

### 7. Request Family Controls Entitlement

**Important:** The Family Controls entitlement requires Apple approval.

1. Go to [Apple Developer](https://developer.apple.com/account)
2. Navigate to Certificates, Identifiers & Profiles
3. For your App ID, request the "Family Controls" capability
4. Wait for approval (can take a few days)

For **development/testing**, you can use the "Individual" authorization mode which is available without additional approval.

### 8. Build and Run

1. Connect your physical iOS device
2. Select your device as the build target
3. Build and run (Cmd+R)
4. On first launch, grant Screen Time access when prompted

## File Structure

```
ScrollBrake/
├── ScrollBrake/
│   ├── ScrollBrakeApp.swift          # App entry point
│   ├── ContentView.swift             # Main navigation
│   ├── Views/
│   │   ├── AppSelectionView.swift    # FamilyActivityPicker UI
│   │   ├── MathGateView.swift        # Math challenge screen
│   │   └── SettingsView.swift        # Settings configuration
│   ├── Managers/
│   │   ├── AuthorizationManager.swift # Screen Time authorization
│   │   ├── MonitoringManager.swift   # DeviceActivity management
│   │   └── ShieldManager.swift       # ManagedSettings shields
│   ├── Models/
│   │   └── SessionState.swift        # Data models
│   ├── Persistence/
│   │   └── PersistenceManager.swift  # App Group UserDefaults
│   └── Extensions/
│       └── URLHandler.swift          # Deep link handling
├── DeviceActivityMonitorExtension/
│   └── DeviceActivityMonitorExtension.swift
├── ShieldConfigurationExtension/
│   └── ShieldConfigurationExtension.swift
└── ShieldActionExtension/
    └── ShieldActionExtension.swift
```

## How It Works

### Architecture

1. **Main App**: User interface for configuration and math challenges
2. **DeviceActivityMonitor Extension**: Runs in background, triggers when usage threshold is reached
3. **ShieldConfiguration Extension**: Customizes the appearance of blocked app overlays
4. **ShieldAction Extension**: Handles "Open ScrollBrake" button on shields

### Session Flow

1. User selects apps to monitor via FamilyActivityPicker
2. MonitoringManager creates a DeviceActivitySchedule with threshold events
3. User uses their selected apps
4. When cumulative usage hits the session limit, DeviceActivityMonitor extension triggers
5. Extension applies shield via ManagedSettingsStore
6. User tries to open blocked app → sees shield overlay
7. User taps "Open ScrollBrake" → app opens with math challenge
8. User solves challenge → shield removed for reward window
9. After reward window, monitoring resumes

### Limitations & Approximations

**Important:** Due to iOS API limitations, the "continuous session" logic is approximated:

- DeviceActivity tracks **cumulative** usage within a schedule interval
- There's no direct API to detect when user leaves/returns to an app
- The "20 second break = reset" is approximated by:
  - Using daily schedule intervals
  - Cumulative usage continues within the day
  - True break detection would require more complex interval management

**Practical Impact:**
- Session limit (5 min) works accurately
- Break window detection is approximate
- For stricter break detection, shorter monitoring intervals could be used

## Testing Checklist

- [ ] App launches and requests Screen Time authorization
- [ ] Authorization granted successfully
- [ ] Can open FamilyActivityPicker and select apps
- [ ] Selection persists after closing/reopening app
- [ ] "Start Monitoring" activates DeviceActivity monitoring
- [ ] Using selected apps for session limit triggers shield
- [ ] Shield overlay appears when opening blocked apps
- [ ] "Open ScrollBrake" button works (opens app)
- [ ] Math challenge displays correctly
- [ ] Correct answer removes shield
- [ ] Reward window provides temporary access
- [ ] Monitoring resumes after reward window
- [ ] Settings adjustments take effect
- [ ] "Reset Session" works for debugging

## Troubleshooting

### "Family Controls not available"
- Ensure you're running on a physical device
- Check that Family Controls entitlement is approved
- Verify App Groups are configured identically across all targets

### Shield not appearing
- Check DeviceActivityMonitor extension is being built
- Verify the extension's Info.plist has correct principal class
- Check Console.app for extension crash logs

### App Group data not sharing
- Verify exact same group ID in all entitlements
- Check PersistenceManager.appGroupIdentifier matches

### Math challenge not showing
- Check URL scheme is configured in Info.plist
- Verify URLHandler.swift is included in build

## Default Settings

- **Session Limit**: 5 minutes
- **Break Window**: 20 seconds
- **Reward Window**: 2 minutes

## License

MIT License - Use freely for personal projects.

## Disclaimer

This is an MVP implementation. Screen Time APIs have limitations that affect precision of "continuous session" tracking. The app provides reasonable approximation for personal use but may not be suitable for strict parental control scenarios.
