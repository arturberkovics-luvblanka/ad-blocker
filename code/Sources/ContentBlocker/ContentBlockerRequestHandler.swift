import Foundation
import os

final class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    private let logger = Logger(subsystem: "org.local.adblocker", category: "ContentBlocker")

    func beginRequest(with context: NSExtensionContext) {
        logger.info("Native rule request received")
        guard let url = Bundle.main.url(forResource: "blockerList", withExtension: "json"),
              let provider = NSItemProvider(contentsOf: url) else {
            logger.error("Bundled rules could not be attached")
            context.cancelRequest(withError: NSError(domain: "AdBlocker", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "A csomagolt szűrőlista hiányzik."]))
            return
        }
        let item = NSExtensionItem()
        item.attachments = [provider]
        logger.info("Returning bundled native rules")
        context.completeRequest(returningItems: [item])
    }
}
