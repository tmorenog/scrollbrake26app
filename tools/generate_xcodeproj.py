#!/usr/bin/env python3
"""Generates scrollbrake26app/scrollbrake26app.xcodeproj/project.pbxproj.

The project uses folder-synchronized groups (Xcode 16+, objectVersion 77), so
adding or removing .swift files never requires editing the project; re-run this
script only when targets, folders or build settings change:

    python3 tools/generate_xcodeproj.py

Targets keep their original names and bundle identifiers. Each target builds
its own folder plus Shared/, and links the local BreakScrollCore package.
"""

import hashlib
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent / "scrollbrake26app"
PROJECT = ROOT / "scrollbrake26app.xcodeproj"
APP_GROUP = "group.com.scrollbrake26app.shared"
BUNDLE_PREFIX = "com.scrollbrake26app.scrollbrake26app"
DEPLOYMENT_TARGET = "17.4"


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


TARGETS = [
    dict(name="scrollbrake26app", folder="BreakScroll", kind="app",
         bundle=BUNDLE_PREFIX, display="BreakScroll",
         entitlements="BreakScroll/BreakScroll.entitlements", plist="BreakScroll/Info.plist"),
    dict(name="DeviceActivityMonitorExtension", folder="DeviceActivityMonitorExtension", kind="appex",
         bundle=BUNDLE_PREFIX + ".DeviceActivityMonitorExtension", display="BreakScroll Monitor",
         entitlements="DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.entitlements",
         plist="DeviceActivityMonitorExtension/Info.plist"),
    dict(name="ShieldConfigurationExtension", folder="ShieldConfigurationExtension", kind="appex",
         bundle=BUNDLE_PREFIX + ".ShieldConfigurationExtension", display="BreakScroll Shield",
         entitlements="ShieldConfigurationExtension/ShieldConfigurationExtension.entitlements",
         plist="ShieldConfigurationExtension/Info.plist"),
    dict(name="ShieldActionExtension", folder="ShieldActionExtension", kind="appex",
         bundle=BUNDLE_PREFIX + ".ShieldActionExtension", display="BreakScroll Shield Action",
         entitlements="ShieldActionExtension/ShieldActionExtension.entitlements",
         plist="ShieldActionExtension/Info.plist"),
]

for t in TARGETS:
    n = t["name"]
    t["id"] = oid("target", n)
    t["product"] = oid("product", n)
    t["product_file"] = n + (".app" if t["kind"] == "app" else ".appex")
    t["group"] = oid("group", t["folder"])
    t["exceptions"] = oid("exceptions", n)
    t["sources"] = oid("sources", n)
    t["frameworks"] = oid("frameworks", n)
    t["resources"] = oid("resources", n)
    t["config_list"] = oid("configlist", n)
    t["debug"] = oid("debug", n)
    t["release"] = oid("release", n)
    t["pkg_dep"] = oid("pkgdep", n)
    t["pkg_build"] = oid("pkgbuild", n)
    t["embed"] = oid("embed", n)
    t["proxy"] = oid("proxy", n)
    t["dependency"] = oid("dependency", n)

APP = TARGETS[0]
EXTENSIONS = TARGETS[1:]
PROJECT_ID = oid("project")
MAIN_GROUP = oid("maingroup")
PRODUCTS_GROUP = oid("products")
SHARED_GROUP = oid("group", "Shared")
PACKAGE = oid("package", "BreakScrollCore")
EMBED_PHASE = oid("embedphase")
PROJECT_CONFIGS = oid("configlist", "project")
PROJECT_DEBUG = oid("debug", "project")
PROJECT_RELEASE = oid("release", "project")


def plist_list(items, indent):
    pad = "\t" * indent
    return "(\n" + "".join(f"{pad}\t{i},\n" for i in items) + f"{pad})"


def target_settings(t):
    s = {
        "CODE_SIGN_ENTITLEMENTS": t["entitlements"],
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE": t["plist"],
        "INFOPLIST_KEY_CFBundleDisplayName": f'"{t["display"]}"',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": t["bundle"],
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
    }
    if t["kind"] == "app":
        s.update({
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "ENABLE_PREVIEWS": "YES",
            "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
            "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
            "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
                '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown '
                'UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
            "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
        })
    else:
        s.update({
            "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
            "LD_RUNPATH_SEARCH_PATHS":
                '("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks")',
            "SKIP_INSTALL": "YES",
        })
    return s


PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "SDKROOT": "iphoneos",
}
PROJECT_DEBUG_SETTINGS = dict(PROJECT_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": '("DEBUG=1", "$(inherited)")',
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
})
PROJECT_RELEASE_SETTINGS = dict(PROJECT_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})


def config(object_id, name, settings):
    body = "".join(f"\t\t\t\t{k} = {v};\n" for k, v in sorted(settings.items()))
    return (f"\t\t{object_id} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
            f"\t\t\tbuildSettings = {{\n{body}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")


def generate():
    o = []
    o.append("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n\n")

    o.append("/* Begin PBXBuildFile section */\n")
    for t in TARGETS:
        o.append(f"\t\t{t['pkg_build']} /* BreakScrollCore in Frameworks */ = "
                 f"{{isa = PBXBuildFile; productRef = {t['pkg_dep']} /* BreakScrollCore */; }};\n")
    for t in EXTENSIONS:
        o.append(f"\t\t{t['embed']} /* {t['product_file']} in Embed Foundation Extensions */ = "
                 f"{{isa = PBXBuildFile; fileRef = {t['product']} /* {t['product_file']} */; "
                 f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
    o.append("/* End PBXBuildFile section */\n\n")

    o.append("/* Begin PBXContainerItemProxy section */\n")
    for t in EXTENSIONS:
        o.append(f"\t\t{t['proxy']} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
                 f"\t\t\tcontainerPortal = {PROJECT_ID} /* Project object */;\n\t\t\tproxyType = 1;\n"
                 f"\t\t\tremoteGlobalIDString = {t['id']};\n\t\t\tremoteInfo = {t['name']};\n\t\t}};\n")
    o.append("/* End PBXContainerItemProxy section */\n\n")

    o.append("/* Begin PBXCopyFilesBuildPhase section */\n")
    embeds = [f"{t['embed']} /* {t['product_file']} in Embed Foundation Extensions */" for t in EXTENSIONS]
    o.append(f"\t\t{EMBED_PHASE} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n"
             f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n"
             f"\t\t\tfiles = {plist_list(embeds, 3)};\n\t\t\tname = \"Embed Foundation Extensions\";\n"
             f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    o.append("/* End PBXCopyFilesBuildPhase section */\n\n")

    o.append("/* Begin PBXFileReference section */\n")
    for t in TARGETS:
        ftype = "wrapper.application" if t["kind"] == "app" else '"wrapper.app-extension"'
        o.append(f"\t\t{t['product']} /* {t['product_file']} */ = {{isa = PBXFileReference; "
                 f"explicitFileType = {ftype}; includeInIndex = 0; path = {t['product_file']}; "
                 f"sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    o.append("/* End PBXFileReference section */\n\n")

    o.append("/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */\n")
    for t in TARGETS:
        excluded = [pathlib.Path(t["plist"]).name, pathlib.Path(t["entitlements"]).name]
        o.append(f"\t\t{t['exceptions']} /* Exceptions for \"{t['folder']}\" folder in \"{t['name']}\" target */ = {{\n"
                 f"\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
                 f"\t\t\tmembershipExceptions = {plist_list(excluded, 3)};\n"
                 f"\t\t\ttarget = {t['id']} /* {t['name']} */;\n\t\t}};\n")
    o.append("/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */\n\n")

    o.append("/* Begin PBXFileSystemSynchronizedRootGroup section */\n")
    for t in TARGETS:
        o.append(f"\t\t{t['group']} /* {t['folder']} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
                 f"\t\t\texceptions = {plist_list([t['exceptions']], 3)};\n"
                 f"\t\t\tpath = {t['folder']};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    o.append(f"\t\t{SHARED_GROUP} /* Shared */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
             f"\t\t\tpath = Shared;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    o.append("/* End PBXFileSystemSynchronizedRootGroup section */\n\n")

    o.append("/* Begin PBXFrameworksBuildPhase section */\n")
    for t in TARGETS:
        o.append(f"\t\t{t['frameworks']} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n"
                 f"\t\t\tbuildActionMask = 2147483647;\n"
                 f"\t\t\tfiles = {plist_list([t['pkg_build'] + ' /* BreakScrollCore in Frameworks */'], 3)};\n"
                 f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    o.append("/* End PBXFrameworksBuildPhase section */\n\n")

    o.append("/* Begin PBXGroup section */\n")
    children = [f"{t['group']} /* {t['folder']} */" for t in TARGETS]
    children += [f"{SHARED_GROUP} /* Shared */", f"{PRODUCTS_GROUP} /* Products */"]
    o.append(f"\t\t{MAIN_GROUP} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = {plist_list(children, 3)};\n"
             f"\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    products = [f"{t['product']} /* {t['product_file']} */" for t in TARGETS]
    o.append(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n"
             f"\t\t\tchildren = {plist_list(products, 3)};\n\t\t\tname = Products;\n"
             f"\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    o.append("/* End PBXGroup section */\n\n")

    o.append("/* Begin PBXNativeTarget section */\n")
    for t in TARGETS:
        phases = [f"{t['sources']} /* Sources */", f"{t['frameworks']} /* Frameworks */",
                  f"{t['resources']} /* Resources */"]
        deps = []
        if t is APP:
            phases.append(f"{EMBED_PHASE} /* Embed Foundation Extensions */")
            deps = [f"{e['dependency']} /* PBXTargetDependency */" for e in EXTENSIONS]
        groups = [f"{t['group']} /* {t['folder']} */", f"{SHARED_GROUP} /* Shared */"]
        ptype = '"com.apple.product-type.application"' if t is APP else '"com.apple.product-type.app-extension"'
        o.append(f"\t\t{t['id']} /* {t['name']} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
                 f"\t\t\tbuildConfigurationList = {t['config_list']} /* Build configuration list for PBXNativeTarget \"{t['name']}\" */;\n"
                 f"\t\t\tbuildPhases = {plist_list(phases, 3)};\n\t\t\tbuildRules = (\n\t\t\t);\n"
                 f"\t\t\tdependencies = {plist_list(deps, 3)};\n"
                 f"\t\t\tfileSystemSynchronizedGroups = {plist_list(groups, 3)};\n"
                 f"\t\t\tname = {t['name']};\n"
                 f"\t\t\tpackageProductDependencies = {plist_list([t['pkg_dep'] + ' /* BreakScrollCore */'], 3)};\n"
                 f"\t\t\tproductName = {t['name']};\n"
                 f"\t\t\tproductReference = {t['product']} /* {t['product_file']} */;\n"
                 f"\t\t\tproductType = {ptype};\n\t\t}};\n")
    o.append("/* End PBXNativeTarget section */\n\n")

    o.append("/* Begin PBXProject section */\n")
    attrs = "".join(f"\t\t\t\t\t{t['id']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t}};\n" for t in TARGETS)
    target_list = [f"{t['id']} /* {t['name']} */" for t in TARGETS]
    package_refs = plist_list([PACKAGE + ' /* XCLocalSwiftPackageReference "../BreakScrollCore" */'], 3)
    o.append(f"\t\t{PROJECT_ID} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n"
             f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2600;\n"
             f"\t\t\t\tLastUpgradeCheck = 2600;\n\t\t\t\tTargetAttributes = {{\n{attrs}\t\t\t\t}};\n\t\t\t}};\n"
             f"\t\t\tbuildConfigurationList = {PROJECT_CONFIGS} /* Build configuration list for PBXProject \"scrollbrake26app\" */;\n"
             f"\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n"
             f"\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
             f"\t\t\tmainGroup = {MAIN_GROUP};\n\t\t\tminimizedProjectReferenceProxies = 1;\n"
             f"\t\t\tpackageReferences = {package_refs};\n"
             f"\t\t\tpreferredProjectObjectVersion = 77;\n"
             f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;\n\t\t\tprojectDirPath = \"\";\n"
             f"\t\t\tprojectRoot = \"\";\n\t\t\ttargets = {plist_list(target_list, 3)};\n\t\t}};\n")
    o.append("/* End PBXProject section */\n\n")

    for section, key in [("PBXResourcesBuildPhase", "resources"), ("PBXSourcesBuildPhase", "sources")]:
        name = "Resources" if key == "resources" else "Sources"
        o.append(f"/* Begin {section} section */\n")
        for t in TARGETS:
            o.append(f"\t\t{t[key]} /* {name} */ = {{\n\t\t\tisa = {section};\n\t\t\tbuildActionMask = 2147483647;\n"
                     f"\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
        o.append(f"/* End {section} section */\n\n")

    o.append("/* Begin PBXTargetDependency section */\n")
    for t in EXTENSIONS:
        o.append(f"\t\t{t['dependency']} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n"
                 f"\t\t\ttarget = {t['id']} /* {t['name']} */;\n"
                 f"\t\t\ttargetProxy = {t['proxy']} /* PBXContainerItemProxy */;\n\t\t}};\n")
    o.append("/* End PBXTargetDependency section */\n\n")

    o.append("/* Begin XCBuildConfiguration section */\n")
    o.append(config(PROJECT_DEBUG, "Debug", PROJECT_DEBUG_SETTINGS))
    o.append(config(PROJECT_RELEASE, "Release", PROJECT_RELEASE_SETTINGS))
    for t in TARGETS:
        o.append(config(t["debug"], "Debug", target_settings(t)))
        o.append(config(t["release"], "Release", target_settings(t)))
    o.append("/* End XCBuildConfiguration section */\n\n")

    o.append("/* Begin XCConfigurationList section */\n")
    lists = [(PROJECT_CONFIGS, 'PBXProject "scrollbrake26app"', PROJECT_DEBUG, PROJECT_RELEASE)]
    lists += [(t["config_list"], f'PBXNativeTarget "{t["name"]}"', t["debug"], t["release"]) for t in TARGETS]
    for list_id, label, debug, release in lists:
        o.append(f"\t\t{list_id} /* Build configuration list for {label} */ = {{\n\t\t\tisa = XCConfigurationList;\n"
                 f"\t\t\tbuildConfigurations = {plist_list([debug + ' /* Debug */', release + ' /* Release */'], 3)};\n"
                 f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")
    o.append("/* End XCConfigurationList section */\n\n")

    o.append("/* Begin XCLocalSwiftPackageReference section */\n")
    o.append(f"\t\t{PACKAGE} /* XCLocalSwiftPackageReference \"../BreakScrollCore\" */ = {{\n"
             f"\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = ../BreakScrollCore;\n\t\t}};\n")
    o.append("/* End XCLocalSwiftPackageReference section */\n\n")

    o.append("/* Begin XCSwiftPackageProductDependency section */\n")
    for t in TARGETS:
        o.append(f"\t\t{t['pkg_dep']} /* BreakScrollCore */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n"
                 f"\t\t\tproductName = BreakScrollCore;\n\t\t}};\n")
    o.append("/* End XCSwiftPackageProductDependency section */\n")

    o.append(f"\t}};\n\trootObject = {PROJECT_ID} /* Project object */;\n}}\n")
    return "".join(o)


def main():
    (PROJECT / "project.pbxproj").write_text(generate())
    scheme = PROJECT / "xcshareddata/xcschemes/scrollbrake26app.xcscheme"
    text = scheme.read_text()
    text = re.sub(r'BlueprintIdentifier = "[^"]*"', f'BlueprintIdentifier = "{APP["id"]}"', text)
    text = re.sub(r'LastUpgradeVersion = "[^"]*"', 'LastUpgradeVersion = "2600"', text)
    scheme.write_text(text)
    print("wrote", PROJECT / "project.pbxproj")


if __name__ == "__main__":
    main()
