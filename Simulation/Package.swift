// swift-tools-version:5.9
//
// A simulated iPhone for BreakScroll. The BreakScrolliOS target compiles the
// app's REAL iOS-layer sources (Shared/, the three extensions, AppModel) against
// fake versions of Apple's Screen Time frameworks that behave as Apple
// documents them. Tests then drive whole days of usage on a simulated clock.
//
// Linux only: the fake modules reuse Apple's module names (ManagedSettings,
// Combine, …), which would clash with the real SDK on macOS.
//
//     cd Simulation && swift test
//
import PackageDescription

let package = Package(
    name: "Simulation",
    dependencies: [.package(path: "../BreakScrollCore")],
    targets: [
        .target(name: "os"),
        .target(name: "Combine"),
        .target(name: "ManagedSettings"),
        .target(name: "FamilyControls", dependencies: ["ManagedSettings", "Combine"]),
        .target(name: "DeviceActivity", dependencies: ["ManagedSettings"]),
        .target(name: "UIKit"),
        .target(name: "ManagedSettingsUI", dependencies: ["UIKit", "ManagedSettings"]),
        .target(name: "UserNotifications"),
        .target(name: "BreakScrolliOS", dependencies: [
            "os", "Combine", "ManagedSettings", "FamilyControls", "DeviceActivity", "UIKit",
            "ManagedSettingsUI", "UserNotifications",
            .product(name: "BreakScrollCore", package: "BreakScrollCore"),
        ]),
        .testTarget(name: "SimulationTests", dependencies: [
            "BreakScrolliOS", "ManagedSettings", "FamilyControls", "DeviceActivity", "ManagedSettingsUI",
            "UserNotifications", "Combine",
            .product(name: "BreakScrollCore", package: "BreakScrollCore"),
        ]),
    ]
)
