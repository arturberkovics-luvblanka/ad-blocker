import Foundation
import SafariServices

// This records a successful reload request, not a measurement of every Safari tab.
@MainActor
enum NativeRuleBundle {
    private static let acknowledgedKey = "lastAcknowledgedNativeRuleSHA256"

    static let generation: String? = {
        guard let url = Bundle.main.url(forResource: "conversion-report", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outputs = report["outputs"] as? [String: Any],
              let hash = outputs["blockerListSHA256"] as? String,
              hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            return nil
        }
        return hash
    }()

    static var acknowledgedGeneration: String? {
        UserDefaults.standard.string(forKey: acknowledgedKey)
    }

    static func acknowledge(_ generation: String) {
        UserDefaults.standard.set(generation, forKey: acknowledgedKey)
    }

    private static let activation = NativeRuleActivation(
        readAcknowledged: { acknowledgedGeneration },
        writeAcknowledged: { acknowledge($0) }
    )

    static func activate(enabled: Bool, force: Bool = false) async -> NativeRuleActivation.Outcome {
        guard let generation, let host = Bundle.main.bundleIdentifier else {
            return .failed("A csomagolt szűrőlista adatai nem olvashatók. Telepítsd újra az alkalmazást.")
        }
        return await activation.activate(generation: generation, enabled: enabled, force: force) {
            await safariRequest(timeout: .seconds(60)) { done in
                SFContentBlockerManager.reloadContentBlocker(withIdentifier: host + ".ContentBlocker") { error in
                    done(error?.localizedDescription ?? "")
                }
            }
        }
    }
}
