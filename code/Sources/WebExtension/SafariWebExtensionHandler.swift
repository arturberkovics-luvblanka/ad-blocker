import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let queue = DispatchQueue(label: "org.local.adblocker.advanced-rules")
    private static var store: AdvancedRuleStore?

    func beginRequest(with context: NSExtensionContext) {
        guard let request = context.inputItems.first as? NSExtensionItem,
              let message = request.userInfo?[SFExtensionMessageKey] as? [String: Any] else {
            Self.respond(["error": "invalid_request"], to: context)
            return
        }
        Self.queue.async {
            do {
                if Self.store == nil {
                    guard let rules = Bundle.main.url(forResource: "adguard-base-advanced", withExtension: "txt"),
                          let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                        throw AdvancedRuleStore.Failure.engineUnavailable
                    }
                    Self.store = AdvancedRuleStore(rulesURL: rules, cacheURL: cache.appendingPathComponent("AdBlocker"))
                }
                guard let payload = try Self.store?.configuration(for: message) else {
                    throw AdvancedRuleStore.Failure.engineUnavailable
                }
                Self.respond(["payload": payload], to: context)
            } catch {
                Self.respond(["error": (error as? AdvancedRuleStore.Failure)?.rawValue ?? "engine_unavailable"], to: context)
            }
        }
    }

    private static func respond(_ data: [String: Any], to context: NSExtensionContext) {
        var reply = data
        reply["generation"] = AdvancedRuleStore.generation
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response])
    }
}
