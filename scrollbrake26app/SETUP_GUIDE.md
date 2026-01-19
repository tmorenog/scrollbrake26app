# ScrollBrake - Detailed Setup Guide

This guide walks you through creating the Xcode project from scratch.

## Step 1: Create the Xcode Project

1. Open Xcode
2. Click "Create a new Xcode project"
3. Select **iOS** → **App** → Next
4. Fill in:
   - **Product Name**: `ScrollBrake`
   - **Team**: Select your Apple Developer team
   - **Organization Identifier**: `com.scrollbrake` (or your own)
   - **Bundle Identifier**: Will auto-fill to `com.scrollbrake.ScrollBrake`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None
   - Uncheck "Include Tests"
5. Click Next and choose where to save

## Step 2: Add Source Files to Main App

### Create folder structure in Xcode:
Right-click on "ScrollBrake" folder → New Group:
- `Views`
- `Managers`
- `Models`
- `Persistence`
- `Extensions`

### Add files:
For each Swift file from this repository, right-click the appropriate group → "New File" → "Swift File":

| File | Location |
|------|----------|
| ScrollBrakeApp.swift | ScrollBrake/ (replace existing) |
| ContentView.swift | ScrollBrake/ (replace existing) |
| AppSelectionView.swift | ScrollBrake/Views/ |
| MathGateView.swift | ScrollBrake/Views/ |
| SettingsView.swift | ScrollBrake/Views/ |
| AuthorizationManager.swift | ScrollBrake/Managers/ |
| MonitoringManager.swift | ScrollBrake/Managers/ |
| ShieldManager.swift | ScrollBrake/Managers/ |
| SessionState.swift | ScrollBrake/Models/ |
| PersistenceManager.swift | ScrollBrake/Persistence/ |
| URLHandler.swift | ScrollBrake/Extensions/ |

Copy the code from the repository files into each new file.

## Step 3: Create DeviceActivityMonitor Extension

1. File → New → Target...
2. Search for "Device Activity Monitor"
3. Select "Device Activity Monitor Extension"
4. Configure:
   - **Product Name**: `DeviceActivityMonitorExtension`
   - **Team**: Same as main app
   - **Bundle Identifier**: `com.scrollbrake.ScrollBrake.DeviceActivityMonitorExtension`
5. Click Finish
6. Replace the generated Swift file content with `DeviceActivityMonitorExtension.swift` from repository

## Step 4: Create Shield Configuration Extension

1. File → New → Target...
2. Search for "Shield Configuration"
3. Select "Shield Configuration Extension"
4. Configure:
   - **Product Name**: `ShieldConfigurationExtension`
   - **Team**: Same as main app
   - **Bundle Identifier**: `com.scrollbrake.ScrollBrake.ShieldConfigurationExtension`
5. Click Finish
6. Replace the generated Swift file content with `ShieldConfigurationExtension.swift` from repository

## Step 5: Create Shield Action Extension

1. File → New → Target...
2. Search for "Shield Action"
3. Select "Shield Action Extension"
4. Configure:
   - **Product Name**: `ShieldActionExtension`
   - **Team**: Same as main app
   - **Bundle Identifier**: `com.scrollbrake.ScrollBrake.ShieldActionExtension`
5. Click Finish
6. Replace the generated Swift file content with `ShieldActionExtension.swift` from repository

## Step 6: Configure Capabilities

### Main App Target:

1. Select project in navigator
2. Select "ScrollBrake" target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add **Family Controls**
6. Click "+ Capability" again
7. Add **App Groups**
8. Under App Groups, click "+"
9. Enter: `group.com.scrollbrake.shared`

### DeviceActivityMonitorExtension Target:

1. Select "DeviceActivityMonitorExtension" target
2. Go to "Signing & Capabilities"
3. Add **Family Controls**
4. Add **App Groups** with `group.com.scrollbrake.shared`

### ShieldConfigurationExtension Target:

1. Select "ShieldConfigurationExtension" target
2. Go to "Signing & Capabilities"
3. Add **Family Controls**
4. Add **App Groups** with `group.com.scrollbrake.shared`

### ShieldActionExtension Target:

1. Select "ShieldActionExtension" target
2. Go to "Signing & Capabilities"
3. Add **Family Controls**
4. Add **App Groups** with `group.com.scrollbrake.shared`

## Step 7: Configure Info.plist

### Main App Info.plist:

1. Select Info.plist in main app folder
2. Add the following keys:

**NSFamilyControlsUsageDescription** (String):
```
ScrollBrake needs Screen Time access to monitor and limit your app usage. Your data stays on your device.
```

**CFBundleURLTypes** (Array):
```xml
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

Or via Xcode UI:
1. Open Info.plist
2. Click "+" to add a row
3. Select "URL types"
4. Expand and add:
   - URL Schemes → Item 0 = `scrollbrake`

## Step 8: Link PersistenceManager in Extensions

The extensions need access to `PersistenceManager.swift`. You have two options:

### Option A: Shared Framework (Recommended for production)
Create a shared framework target containing PersistenceManager and link to all targets.

### Option B: File Reference (Simpler for MVP)
1. In each extension target's Build Phases
2. Under "Compile Sources"
3. Click "+" and add `PersistenceManager.swift` from the main app

**Note:** For Option B, ensure the file is marked for all targets:
1. Select `PersistenceManager.swift` in navigator
2. Open File Inspector (right panel)
3. Under "Target Membership", check all 4 targets

## Step 9: Set Deployment Target

1. Select the project in navigator
2. Under "Info" tab
3. Set iOS Deployment Target to **16.0** or higher for all targets

## Step 10: Build and Test

1. Connect your iPhone via USB
2. Select your device in the scheme selector
3. Press Cmd+R to build and run
4. On device, grant Screen Time access when prompted

## Troubleshooting Build Errors

### "Missing required module 'FamilyControls'"
- Ensure Family Controls capability is added
- Check iOS deployment target is 16.0+

### "Cannot find 'PersistenceManager' in scope" (in extensions)
- Add PersistenceManager.swift to extension's target membership
- Or create a shared framework

### "Signing for target requires a development team"
- Select your team for each target in Signing & Capabilities

### "App Groups capability not available"
- Ensure you have an active Apple Developer membership
- App Groups requires paid developer account

## Testing on Device

### First Launch:
1. App requests Screen Time authorization
2. Tap "Enable Screen Time Access"
3. System shows authorization prompt
4. Allow access

### Test Flow:
1. Go to "Apps" tab
2. Tap "Select Apps & Categories"
3. Choose some apps (e.g., Social category)
4. Tap "Apply & Start Monitoring"
5. Go to Home and use one of the selected apps
6. Wait for session limit (5 minutes by default)
7. App should become blocked
8. Try opening the blocked app
9. Should see shield overlay
10. Tap "Open ScrollBrake"
11. Solve math problem
12. Apps should unblock for reward window

### Debug Testing:
- Use "Reset Session (Debug)" button to clear state
- Reduce session limit to 1 minute in Settings for faster testing
- Check Console.app for extension logs

## Common Issues

### Shield doesn't appear
- Check Console.app for extension crashes
- Verify extension Info.plist principal class is correct
- Ensure DeviceActivity monitoring is actually started

### App Group data not syncing
- Double-check all 4 targets have identical App Group ID
- Restart device after changing App Group configuration

### FamilyActivityPicker empty
- This is normal - picker shows apps the user has installed
- Make sure some apps are installed on the test device

## Ready to Ship?

Before App Store submission:
1. Request Family Controls entitlement for distribution
2. Update privacy policy to mention Screen Time data usage
3. Test on multiple device types
4. Consider adding onboarding for first-time users
