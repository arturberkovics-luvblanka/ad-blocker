import Foundation
import FilterEngine

@main
struct AdvancedRuleStoreTests {
    static func main() throws {
        let rules = URL(fileURLWithPath: CommandLine.arguments[1])
        let scratch = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let store = AdvancedRuleStore(rulesURL: rules, cacheURL: scratch)
        let youtube: [String: Any] = ["type": "lookup", "url": "https://www.youtube.com/watch?v=test"]

        let start = Date()
        let cold = try store.configuration(for: youtube)
        if CommandLine.arguments.count > 3 {
            try JSONSerialization.data(withJSONObject: cold, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        }
        let scriptlets = cold["scriptlets"] as! [[String: Any]]
        precondition(scriptlets.contains { ($0["name"] as? String) == "json-prune-fetch-response" })
        precondition(scriptlets.contains { ($0["name"] as? String) == "set-constant" && ($0["args"] as? [String]) == ["google_ad_status", "1"] })
        for property in ["ytInitialPlayerResponse.adPlacements", "ytInitialPlayerResponse.adSlots", "ytInitialPlayerResponse.playerAds", "playerResponse.adPlacements"] {
            precondition(scriptlets.contains {
                ($0["name"] as? String) == "set-constant" && ($0["args"] as? [String]) == [property, "undefined"]
            })
        }
        precondition(!(cold["extendedCss"] as! [String]).isEmpty)
        print("PASS: cold full-list YouTube lookup (\(scriptlets.count) scriptlets, \(Date().timeIntervalSince(start)) seconds)")

        let warm = try store.configuration(for: youtube)
        precondition(NSDictionary(dictionary: cold).isEqual(to: warm))
        let reopened = try AdvancedRuleStore(rulesURL: rules, cacheURL: scratch).configuration(for: youtube)
        precondition(NSDictionary(dictionary: cold).isEqual(to: reopened))
        print("PASS: warm and reopened cache preserve configuration")

        let excepted = try store.configuration(for: ["type": "lookup", "url": "https://www.youtube.com/my_video_ad"])
        precondition((excepted["scriptlets"] as! [[String: Any]]).isEmpty)
        print("PASS: reviewed early player rules match native lookup; YouTube document exception still disables scriptlets")

        let storage = scratch.appendingPathComponent(AdvancedRuleStore.generation).appendingPathComponent(Schema.BASE_DIR)
        precondition(FileManager.default.fileExists(atPath: storage.appendingPathComponent(Schema.LOCK_FILE_NAME).path))
        try FileManager.default.removeItem(at: storage.appendingPathComponent(Schema.FILTER_ENGINE_INDEX_FILE_NAME))
        let repaired = try AdvancedRuleStore(rulesURL: rules, cacheURL: scratch).configuration(for: youtube)
        precondition((repaired["scriptlets"] as! [[String: Any]]).count == scriptlets.count)
        print("PASS: missing engine binary is rebuilt; cold-start lock exists")

        for message: [String: Any] in [
            [:], ["type": "other", "url": "https://example.com"],
            ["type": "lookup", "url": "file:///private/test"],
            ["type": "lookup", "url": "https://name:secret@example.com"],
            ["type": "lookup", "url": "https://example.com", "topUrl": "about:blank"],
            ["type": "lookup", "url": "https://example.com/" + String(repeating: "x", count: 16384)]
        ] {
            do { _ = try store.configuration(for: message); preconditionFailure("Accepted invalid request") }
            catch AdvancedRuleStore.Failure.invalidRequest {}
        }
        print("PASS: malformed, credential-bearing and non-web requests rejected")

        let corrupt = scratch.appendingPathComponent("corrupt.txt")
        try Data("modified".utf8).write(to: corrupt)
        do {
            _ = try AdvancedRuleStore(rulesURL: corrupt, cacheURL: scratch).configuration(for: youtube)
            preconditionFailure("Accepted altered rule file")
        } catch AdvancedRuleStore.Failure.generationMismatch {}
        print("PASS: modified source rejected even with an existing engine cache")

        let frame = try store.configuration(for: ["type": "lookup", "url": "https://www.youtube.com/embed/test", "topUrl": "https://example.com/"])
        precondition(!(frame["scriptlets"] as! [[String: Any]]).isEmpty)
        print("PASS: embedded YouTube lookup returns scriptlets")

        let selfTest = try store.configuration(for: [
            "type": "lookup",
            "url": "http://127.0.0.1:49152/session/" + String(repeating: "a", count: 64) + "/",
        ])
        let selfTestExtendedCSS = selfTest["extendedCss"] as! [String]
        precondition(selfTestExtendedCSS.contains(".adblocker-self-test-advanced:has-text(advanced-marker)"))
        print("PASS: production localhost lookup returns the deterministic advanced self-test rule")
    }
}
