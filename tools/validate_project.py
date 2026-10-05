#!/usr/bin/env python3
"""Static checks for the BreakScroll Xcode project that no compiler catches.

    python3 tools/validate_project.py

Fails (exit 1) if an extension declares the wrong extension point or principal
class, if any target's entitlements disagree with Shared/AppGroup.swift, or if
the project references files that don't exist. Wrong extension points are
silent on device: iOS simply never loads the extension.
"""

import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "scrollbrake26app"

# Confirmed by an Apple engineer (developer.apple.com/forums/thread/681963) and
# Xcode's target templates.
EXTENSIONS = {
    "DeviceActivityMonitorExtension": ("com.apple.deviceactivity.monitor-extension", "DeviceActivityMonitor"),
    "ShieldActionExtension": ("com.apple.ManagedSettings.shield-action-service", "ShieldActionDelegate"),
    "ShieldConfigurationExtension": ("com.apple.ManagedSettingsUI.shield-configuration-service", "ShieldConfigurationDataSource"),
}
TARGET_FOLDERS = {"BreakScroll": "BreakScroll.entitlements", **{name: f"{name}.entitlements" for name in EXTENSIONS}}

errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


app_group = re.search(r'identifier = "([^"]+)"', (ROOT / "Shared/AppGroup.swift").read_text()).group(1)

for folder, entitlements_file in TARGET_FOLDERS.items():
    entitlements = plistlib.loads((ROOT / folder / entitlements_file).read_bytes())
    check(entitlements.get("com.apple.developer.family-controls") is True, f"{folder}: Family Controls entitlement missing")
    check(entitlements.get("com.apple.security.application-groups") == [app_group],
          f"{folder}: App Group {entitlements.get('com.apple.security.application-groups')} != {app_group}")

for name, (point, base_class) in EXTENSIONS.items():
    info = plistlib.loads((ROOT / name / "Info.plist").read_bytes()).get("NSExtension", {})
    check(info.get("NSExtensionPointIdentifier") == point,
          f"{name}: extension point {info.get('NSExtensionPointIdentifier')!r}, expected {point!r}")
    check(info.get("NSExtensionPrincipalClass") == f"$(PRODUCT_MODULE_NAME).{name}",
          f"{name}: principal class {info.get('NSExtensionPrincipalClass')!r}")
    source = (ROOT / name / f"{name}.swift").read_text()
    check(re.search(rf"^class {name}: {base_class}\b", source, re.M) is not None,
          f"{name}: expected `class {name}: {base_class}`")

app_info = plistlib.loads((ROOT / "BreakScroll/Info.plist").read_bytes())
check(app_info.get("NSExtension") is None, "the app's Info.plist must not declare an extension")

project = (ROOT / "scrollbrake26app.xcodeproj/project.pbxproj").read_text()
for path in re.findall(r"(?<![A-Z_])(?:CODE_SIGN_ENTITLEMENTS|INFOPLIST_FILE) = ([^;]+);", project):
    check((ROOT / path.strip('"')).exists(), f"project references missing file {path}")
for path in re.findall(r"isa = PBXFileSystemSynchronizedRootGroup;.*?path = ([^;]+);", project, re.S):
    check((ROOT / path).is_dir(), f"project references missing folder {path}")
check((ROOT / "../BreakScrollCore/Package.swift").exists(), "BreakScrollCore package missing")
check("IPHONEOS_DEPLOYMENT_TARGET = 17.4;" in project, "deployment target is not 17.4")

if errors:
    print("FAILED")
    for error in errors:
        print(" -", error)
    sys.exit(1)
print(f"OK: {len(EXTENSIONS)} extensions, {len(TARGET_FOLDERS)} targets, App Group {app_group}")
