import AppKit
import WebKit

// This is a local-only proof for the Safari projection of the dropped media.net
// rule. It maps only the selected rule host to 127.0.0.1; the page base URL is
// localhost so the selected request remains third-party.
final class MediaNetSmoke: NSObject, WKNavigationDelegate {
    enum Phase: CaseIterable {
        case offThirdParty
        case onThirdParty
        case onFirstParty
    }

    private let candidateURL = URL(fileURLWithPath: CommandLine.arguments[1])
    private let store = WKContentRuleListStore(url: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))!
    private var compiled: WKContentRuleList!
    private var phase = Phase.offThirdParty
    private var webView: WKWebView!

    private let targetOrigin = "http://127.0.0.1:8765"
    private let thirdPartyBase = URL(string: "http://localhost:8765/media-net-publisher.html")!
    private let firstPartyBase = URL(string: "http://127.0.0.1:8765/media-net-publisher.html")!

    func start() {
        do {
            let data = try Data(contentsOf: candidateURL)
            guard var rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                fail("Candidate JSON is not an array")
                return
            }

            let originalFilter = #"^[^:]+://+([^:/]+\.)?media\.net[/:]"#
            let mappedFilter = #"^[^:]+://+([^:/]+\.)?127\.0\.0\.1:8765[/:]"#
            let matching = rules.enumerated().filter { _, rule in
                let trigger = rule["trigger"] as? [String: Any]
                let action = rule["action"] as? [String: Any]
                return action?["type"] as? String == "block"
                    && trigger?["url-filter"] as? String == originalFilter
                    && trigger?["load-type"] as? [String] == ["third-party"]
                    && trigger?["resource-type"] as? [String] == ["script", "fetch"]
            }
            guard matching.count == 1, var mapped = matching[0].element["trigger"] as? [String: Any] else {
                fail("Missing exact media.net script/fetch third-party projection")
                return
            }
            guard let exceptionIndex = rules.firstIndex(where: { rule in
                let trigger = rule["trigger"] as? [String: Any]
                return (rule["action"] as? [String: Any])?["type"] as? String == "ignore-previous-rules"
                    && trigger?["if-domain"] as? [String] == ["*sznlink.xyz"]
                    && trigger?["url-filter"] as? String == #"^[^:]+://+([^:/]+\.)?contextual\.media\.net\/dmedianet\.js"#
            }), exceptionIndex > matching[0].offset,
            var exceptionTrigger = rules[exceptionIndex]["trigger"] as? [String: Any] else {
                fail("Missing media.net exception after the new block")
                return
            }

            // Keep every selected trigger field unchanged except the host used by
            // this local fixture. The original media.net rule remains in the input.
            mapped["url-filter"] = mappedFilter
            rules.append(["trigger": mapped, "action": ["type": "block"]])
            exceptionTrigger["url-filter"] = #"^http://127\.0\.0\.1:8765/media-net-exception\.js"#
            exceptionTrigger["if-domain"] = ["localhost"]
            rules.append([
                "trigger": exceptionTrigger,
                "action": ["type": "ignore-previous-rules"],
            ])

            let encoded = try String(decoding: JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
            store.compileContentRuleList(forIdentifier: "AdBlockerMediaNetSmoke", encodedContentRuleList: encoded) { list, error in
                guard let list else {
                    self.fail("Rule compilation: \(error?.localizedDescription ?? "unknown error")")
                    return
                }
                self.compiled = list
                self.load()
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func load() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if phase != .offThirdParty {
            configuration.userContentController.add(compiled)
        }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        let base = phase == .onFirstParty ? firstPartyBase : thirdPartyBase
        webView.loadHTMLString("""
            <!doctype html><button id="useful">0</button>
            <script>window.usefulCount = 0; useful.onclick = () => useful.textContent = String(++window.usefulCount);</script>
            """, baseURL: base)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let run = """
        (() => {
          const result = { script: null, fetch: null, image: null, exception: null, useful: null };
          const script = src => new Promise(done => {
            const element = document.createElement('script'); element.src = src;
            element.onload = () => done(true); element.onerror = () => done(false); document.head.append(element);
          });
          const image = src => new Promise(done => {
            const element = new Image(); element.onload = () => done(true); element.onerror = () => done(false); element.src = src;
          });
          document.getElementById('useful').click(); result.useful = window.usefulCount === 1;
          Promise.all([
            script('\(targetOrigin)/media-net-script.js'),
            fetch('\(targetOrigin)/media-net-fetch.json', { mode: 'no-cors' }).then(() => true, () => false),
            image('\(targetOrigin)/media-net-image.svg'),
            script('\(targetOrigin)/media-net-exception.js'),
          ]).then(values => {
            [result.script, result.fetch, result.image, result.exception] = values;
            result.script = result.script && window.mediaNetScriptLoaded === 1;
            result.exception = result.exception && window.mediaNetExceptionLoaded === 1;
            window.mediaNetResult = result;
          });
        })();
        """
        webView.evaluateJavaScript(run) { _, error in
            guard error == nil else { self.fail("Fixture startup: \(error!.localizedDescription)"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.readResult() }
        }
    }

    private func readResult() {
        webView.evaluateJavaScript("JSON.stringify(window.mediaNetResult || null)") { value, error in
            guard error == nil, let text = value as? String,
                  let data = text.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] else {
                self.fail("Fixture result: \(String(describing: error))")
                return
            }
            let expected: [String: Bool]
            switch self.phase {
            case .offThirdParty, .onFirstParty:
                expected = ["script": true, "fetch": true, "image": true, "exception": true, "useful": true]
            case .onThirdParty:
                expected = ["script": false, "fetch": false, "image": true, "exception": true, "useful": true]
            }
            guard result == expected else {
                self.fail("Unexpected \(self.phase) result: \(text)")
                return
            }
            print("PASS: \(self.phase) \(text)")
            if let next = Phase.allCases.drop(while: { $0 != self.phase }).dropFirst().first {
                self.phase = next
                self.load()
            } else {
                exit(0)
            }
        }
    }

    func fail(_ reason: String) {
        fputs("FAIL: \(reason)\n", stderr)
        exit(1)
    }
}

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: MediaNetWebKitSmoke candidate.json temporary-rule-store\n", stderr)
    exit(2)
}
_ = NSApplication.shared
let test = MediaNetSmoke()
test.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 90) { test.fail("Timed out after 90 seconds") }
RunLoop.main.run()
