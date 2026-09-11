import Foundation
import CryptoKit
import FilterEngine

/// Serialized by the handler queue. It never sends or persists browsing URLs.
final class AdvancedRuleStore {
    static let generation = "fc68ee1ce9fa6a7eabd48a644785d45c87afb403931e9b6dcb1efadb292a873c"
    private let rulesURL: URL
    private let cacheURL: URL
    private var engine: WebExtension?

    init(rulesURL: URL, cacheURL: URL) {
        self.rulesURL = rulesURL
        self.cacheURL = cacheURL.appendingPathComponent(Self.generation, isDirectory: true)
    }

    enum Failure: String, Error {
        case invalidRequest = "invalid_request"
        case generationMismatch = "generation_mismatch"
        case engineUnavailable = "engine_unavailable"
    }

    func configuration(for message: [String: Any]) throws -> [String: Any] {
        guard message["type"] as? String == "lookup",
              let pageURL = Self.webURL(message["url"]) else { throw Failure.invalidRequest }
        let topURL: URL?
        if let top = message["topUrl"] {
            guard let parsed = Self.webURL(top) else { throw Failure.invalidRequest }
            topURL = parsed
        } else { topURL = nil }

        if engine == nil {
            let data = try Data(contentsOf: rulesURL)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hash == Self.generation else { throw Failure.generationMismatch }
            // Upstream opens its lock before creating this directory. Create it first
            // so a cold start also gets the cross-process lock.
            try FileManager.default.createDirectory(
                at: cacheURL.appendingPathComponent(Schema.BASE_DIR, isDirectory: true),
                withIntermediateDirectories: true
            )
            let instance = try WebExtension(containerURL: cacheURL, version: .safari26)
            if instance.lookup(pageUrl: pageURL, topUrl: topURL) == nil {
                guard let rules = String(data: data, encoding: .utf8) else { throw Failure.engineUnavailable }
                _ = try instance.buildFilterEngine(rules: rules)
                // A failed cache read may already have cached its metadata timestamp.
                // Reopen after rebuilding, including recovery from missing binary files.
                engine = try WebExtension(containerURL: cacheURL, version: .safari26)
            } else {
                engine = instance
            }
        }
        guard let config = engine?.lookup(pageUrl: pageURL, topUrl: topURL) else {
            engine = nil
            throw Failure.engineUnavailable
        }
        return [
            "css": config.css,
            "extendedCss": config.extendedCss,
            "js": config.js,
            "scriptlets": config.scriptlets.map { ["name": $0.name, "args": $0.args] as [String: Any] },
            "engineTimestamp": config.engineTimestamp,
        ]
    }

    private static func webURL(_ value: Any?) -> URL? {
        guard let text = value as? String, text.utf8.count <= 16384,
              let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
