#!/usr/bin/env python3
"""Generate the six small Xcode targets without a third-party project tool."""
import hashlib
import json
import plistlib
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "AdBlocker.xcodeproj"
objects = {}
VERSION = json.loads((ROOT / "extension/manifest.json").read_text())["version"]


def add(key, isa, **values):
    identifier = hashlib.sha256(key.encode()).hexdigest()[:24].upper()
    objects[identifier] = {"isa": isa, **values}
    return identifier


def plist(path, value):
    destination = ROOT / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(plistlib.dumps(value, sort_keys=False))


def reference(path, file_type):
    return add(path, "PBXFileReference", path=path, sourceTree="SOURCE_ROOT", lastKnownFileType=file_type)


def phase(key, isa, references):
    files = [add(key + ref, "PBXBuildFile", fileRef=ref) for ref in references]
    return add(key, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)


def configs(key, settings):
    refs = []
    for name in ("Debug", "Release"):
        values = dict(settings, SWIFT_OPTIMIZATION_LEVEL="-Onone" if name == "Debug" else "-O")
        values["ONLY_ACTIVE_ARCH"] = "YES" if name == "Debug" else "NO"
        refs.append(add(key + name, "XCBuildConfiguration", name=name, buildSettings=values))
    return add(key + "Configs", "XCConfigurationList", buildConfigurations=refs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")


sources = {
    "App": reference("Sources/App/AdBlockerApp.swift", "sourcecode.swift"),
    "ContentBlocker": reference("Sources/ContentBlocker/ContentBlockerRequestHandler.swift", "sourcecode.swift"),
    "WebExtension": reference("Sources/WebExtension/SafariWebExtensionHandler.swift", "sourcecode.swift"),
}
rules = reference("filters/blockerList.json", "text.json")
request_source = reference("Sources/App/SafariRequest.swift", "sourcecode.swift")
diagnostics_source = reference("Sources/App/SafariDiagnostics.swift", "sourcecode.swift")
activation_source = reference("Sources/App/NativeRuleActivation.swift", "sourcecode.swift")
bundle_source = reference("Sources/App/NativeRuleBundle.swift", "sourcecode.swift")
background_source = reference("Sources/App/MacBackgroundApp.swift", "sourcecode.swift")
advanced_source = reference("Sources/WebExtension/AdvancedRuleStore.swift", "sourcecode.swift")
advanced_rules = reference("filters/generated/adguard-base-advanced.txt", "text")
engine_package = add("EnginePackage", "XCLocalSwiftPackageReference", relativePath="vendor/SafariConverterLib")
webfiles = [reference(str(p.relative_to(ROOT)), "text.json" if p.suffix == ".json" else "text")
            for p in sorted((ROOT / "extension").iterdir()) if p.is_file()]
app_resources = [reference("../LICENSE", "text"), reference("vendor/licenses", "folder"),
                 reference("filters/LICENSE-Hufilter-CC-BY-4.0.txt", "text"),
                 reference("Resources/THIRD_PARTY_NOTICES.md", "text"),
                 reference("filters/generated/conversion-report.json", "text.json")]
products, targets, schemes = [], [], []
project_id = hashlib.sha256(b"Project").hexdigest()[:24].upper()

for platform, sdk, minimum in (("macOS", "macosx", "14.0"), ("iOS", "iphoneos", "17.0")):
    platform_targets = {}
    for kind in ("ContentBlocker", "WebExtension", "App"):
        name = "AdBlocker" + ("" if kind == "App" else kind) + "-" + platform
        product_name = "Ad Blocker" if kind == "App" else "AdBlocker" + kind
        suffix = ".app" if kind == "App" else ".appex"
        bundle = "org.local.adblocker" + (".ios" if platform == "iOS" else "")
        if kind != "App":
            bundle += "." + kind
        info_path = f"Configuration/{platform}-{kind}-Info.plist"
        info = {
            "CFBundleDevelopmentRegion": "hu", "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)", "CFBundleDisplayName": {
                "App": "Ad Blocker", "ContentBlocker": "Ad Blocker – Szűrőlista",
                "WebExtension": "Ad Blocker – Oldalellenőrzés"}[kind],
            "CFBundlePackageType": "APPL" if kind == "App" else "XPC!",
            "CFBundleShortVersionString": VERSION, "CFBundleVersion": "2",
        }
        if kind != "App":
            info["NSExtension"] = {
                "NSExtensionPointIdentifier": "com.apple.Safari." + ("content-blocker" if kind == "ContentBlocker" else "web-extension"),
                "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME)." + ("ContentBlockerRequestHandler" if kind == "ContentBlocker" else "SafariWebExtensionHandler"),
            }
            info["NSHumanReadableDescription"] = "Helyi Safari reklámblokkoló tesztverzió."
        elif platform == "macOS":
            info["NSPrincipalClass"] = "NSApplication"
            info["LSUIElement"] = True
            info["LSMinimumSystemVersion"] = "$(MACOSX_DEPLOYMENT_TARGET)"
        else:
            info["UILaunchScreen"] = {}
            info["UIApplicationSceneManifest"] = {"UIApplicationSupportsMultipleScenes": False}
            info["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
            info["UISupportedInterfaceOrientations~ipad"] = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
        plist(info_path, info)
        entitlements_path = f"Configuration/{platform}-{kind}.entitlements"
        plist(entitlements_path, {"com.apple.security.app-sandbox": True} if platform == "macOS" else {})
        settings = {
            "PRODUCT_NAME": product_name, "PRODUCT_BUNDLE_IDENTIFIER": bundle,
            "SWIFT_VERSION": "5.0", "SDKROOT": sdk,
            "INFOPLIST_FILE": info_path, "GENERATE_INFOPLIST_FILE": "NO",
            "CODE_SIGN_ENTITLEMENTS": entitlements_path, "CODE_SIGN_STYLE": "Automatic",
            "CODE_SIGN_IDENTITY": "-" if platform == "macOS" else "Apple Development",
            "ENABLE_HARDENED_RUNTIME": "YES", "CLANG_ENABLE_MODULES": "YES",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"] if platform == "macOS" else ["$(inherited)", "@executable_path/Frameworks"],
            "MACOSX_DEPLOYMENT_TARGET" if platform == "macOS" else "IPHONEOS_DEPLOYMENT_TARGET": minimum,
            "SKIP_INSTALL": "NO" if kind == "App" else "YES",
        }
        if platform == "iOS":
            settings["TARGETED_DEVICE_FAMILY"] = "1,2"
            settings["SUPPORTS_MACCATALYST"] = "NO"
        if kind != "App":
            settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
        if kind == "ContentBlocker":
            # PlugInKit's extension subsystem is supplied by the UI framework.
            settings["OTHER_LDFLAGS"] = ["$(inherited)", "-framework", "Cocoa" if platform == "macOS" else "UIKit"]
        product = add(name + "Product", "PBXFileReference", explicitFileType="wrapper.application" if kind == "App" else "wrapper.app-extension", path=product_name + suffix, sourceTree="BUILT_PRODUCTS_DIR", includeInIndex=0)
        products.append(product)
        resources = [rules] if kind == "ContentBlocker" else webfiles + [advanced_rules] if kind == "WebExtension" else app_resources
        target_sources = [sources[kind], request_source, diagnostics_source, activation_source, bundle_source, background_source] if kind == "App" else [sources[kind], advanced_source] if kind == "WebExtension" else [sources[kind]]
        phases = [phase(name + "Sources", "PBXSourcesBuildPhase", target_sources),
                  phase(name + "Resources", "PBXResourcesBuildPhase", resources),
                  phase(name + "Frameworks", "PBXFrameworksBuildPhase", [])]
        package_products = []
        if kind == "WebExtension":
            dependency = add(name + "EngineProduct", "XCSwiftPackageProductDependency", package=engine_package, productName="ContentBlockerConverter")
            package_products.append(dependency)
            objects[phases[2]]["files"].append(add(name + "LinkEngine", "PBXBuildFile", productRef=dependency))
        dependencies = []
        if kind == "App":
            embedded = []
            for child, child_product in platform_targets.values():
                proxy = add(name + child + "Proxy", "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=child, remoteInfo=objects[child]["name"])
                dependencies.append(add(name + child + "Dependency", "PBXTargetDependency", target=child, targetProxy=proxy))
                embedded.append(add(name + child + "Embed", "PBXBuildFile", fileRef=child_product, settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]}))
            phases.append(add(name + "EmbedExtensions", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=embedded, name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0))
        target = add(name, "PBXNativeTarget", name=name, productName=product_name,
                     productReference=product, productType="com.apple.product-type.application" if kind == "App" else "com.apple.product-type.app-extension",
                     buildConfigurationList=configs(name, settings), buildPhases=phases, buildRules=[], dependencies=dependencies, packageProductDependencies=package_products)
        targets.append(target)
        platform_targets[kind] = (target, product)
        if kind == "App":
            schemes.append((name, target, product_name + suffix))

product_group = add("Products", "PBXGroup", children=products, name="Products", sourceTree="<group>")
main_group = add("MainGroup", "PBXGroup", children=list(sources.values()) + [request_source, diagnostics_source, activation_source, bundle_source, background_source, advanced_source, advanced_rules, rules] + webfiles + app_resources + [product_group], sourceTree="<group>")
add("Project", "PBXProject", attributes={"LastUpgradeCheck": "2700", "BuildIndependentTargetsInParallel": "YES"},
    buildConfigurationList=configs("Project", {"CLANG_ENABLE_MODULES": "YES"}), compatibilityVersion="Xcode 14.0",
    developmentRegion="hu", hasScannedForEncodings=0, knownRegions=["hu", "en", "Base"],
    mainGroup=main_group, productRefGroup=product_group, projectDirPath="", projectRoot="", targets=targets, packageReferences=[engine_package])

PROJECT.mkdir(exist_ok=True)
(PROJECT / "project.pbxproj").write_bytes(plistlib.dumps({"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project_id}, sort_keys=False))
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
for name, identifier, product_name in schemes:
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{escape(product_name)}" BlueprintName="{name}" ReferencedContainer="container:AdBlocker.xcodeproj"/>'
    (scheme_dir / f"{name}.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(PROJECT)
