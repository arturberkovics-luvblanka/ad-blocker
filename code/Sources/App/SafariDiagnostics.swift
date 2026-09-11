import Foundation
import SafariServices

// Runs from the actual signed host bundle; a standalone binary cannot prove this path.
@MainActor
func runSafariDiagnostics(reload: Bool) async -> Bool {
    guard let host = Bundle.main.bundleIdentifier else { return false }
    let started = Date()
    let native: (Bool?, String?)? = await safariRequest(timeout: .seconds(15)) { done in
        SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: host + ".ContentBlocker") { state, error in
            done((state?.isEnabled, error?.localizedDescription))
        }
    }
    var output: [String: Any] = [
        "host": host,
        "nativeEnabled": native?.0 as Any? ?? NSNull(),
        "stateError": native?.1 as Any? ?? NSNull(),
        "stateTimedOut": native == nil,
        "reloadRequested": reload,
        "bundledNativeGeneration": NativeRuleBundle.generation as Any? ?? NSNull(),
    ]
    var success = native != nil && native?.1 == nil
    #if os(macOS)
    let web = await SafariSetupState.web(host + ".WebExtension")
    output["web"] = web.dictionary
    output["lastBackgroundSetup"] = UserDefaults.standard.dictionary(forKey: "lastBackgroundSetup") as Any? ?? NSNull()
    output["appPath"] = Bundle.main.bundlePath
    output["appVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
    #endif
    if reload {
        let result: String? = await safariRequest(timeout: .seconds(60)) { done in
            SFContentBlockerManager.reloadContentBlocker(withIdentifier: host + ".ContentBlocker") { error in
                done(error?.localizedDescription ?? "")
            }
        }
        output["reloadCompleted"] = result != nil
        output["reloadError"] = result as Any? ?? NSNull()
        success = success && result == ""
        if result == "", let generation = NativeRuleBundle.generation {
            NativeRuleBundle.acknowledge(generation)
        }
    }
    output["acknowledgedNativeGeneration"] = NativeRuleBundle.acknowledgedGeneration as Any? ?? NSNull()
    output["elapsedSeconds"] = Date().timeIntervalSince(started)
    if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    } else {
        return false
    }
    return success
}
