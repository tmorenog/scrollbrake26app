// swift-tools-version:5.9
//
// BreakScrollCore holds BreakScroll's platform-independent logic: rules,
// schedules, escalation, math challenges, the intervention state machine and
// sync merging. It deliberately imports only Foundation so it builds and tests
// on any Swift platform. Screen Time types (FamilyActivitySelection, tokens)
// stay in the iOS targets and are carried here as opaque `Data`.
//
import PackageDescription

let package = Package(
    name: "BreakScrollCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BreakScrollCore", targets: ["BreakScrollCore"]),
    ],
    targets: [
        .target(name: "BreakScrollCore"),
        .testTarget(name: "BreakScrollCoreTests", dependencies: ["BreakScrollCore"]),
    ]
)
