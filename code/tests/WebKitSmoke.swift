import AppKit
import WebKit

// This tests the installed WebKit engine, NOT Safari extension activation.
final class SmokeTest: NSObject, WKNavigationDelegate {
    var webView: WKWebView!
    var compiled: WKContentRuleList!
    var blocking = false
    var hufilterFixture = false
    let store = WKContentRuleListStore(url: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))!

    func start() {
        do {
            let json = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            guard var rules = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else {
                fail("Rule JSON is not an array")
                return
            }
            let selector = ".pr-row:has(article.m-articleWidget__wrap .m-articleWidget__tag)"
            let generatedRuleExists = rules.contains { rule in
                let action = rule["action"] as? [String: Any]
                let trigger = rule["trigger"] as? [String: Any]
                let domains = trigger?["if-domain"] as? [String]
                return (action?["selector"] as? String)?.contains(selector) == true
                    && domains?.contains("*24.hu") == true
            }
            guard generatedRuleExists else {
                fail("Missing generated 24.hu advertorial rule")
                return
            }
            // The product rule is scoped to 24.hu. Add an otherwise identical
            // local-only rule so WebKit can exercise the selector on the fixture.
            rules.append([
                "trigger": ["url-filter": ".*", "if-domain": ["127.0.0.1"]],
                "action": ["type": "css-display-none", "selector": selector],
            ])
            let fixtureJSON = try String(decoding: JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
            store.compileContentRuleList(forIdentifier: "AdBlockerSmoke", encodedContentRuleList: fixtureJSON) { list, error in
                guard let list else { self.fail("Rule compilation: \(error?.localizedDescription ?? "unknown error")"); return }
                self.compiled = list
                print("PASS: installed WebKit compiled the complete native rule list")
                self.load()
            }
        } catch { fail(error.localizedDescription) }
    }

    func load() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        if blocking { config.userContentController.add(compiled) }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 800), configuration: config)
        webView.navigationDelegate = self
        let path = hufilterFixture ? "/hufilter-24hu.html" : "/"
        webView.load(URLRequest(url: URL(string: "http://127.0.0.1:8765\(path)")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if hufilterFixture {
            webView.evaluateJavaScript("JSON.stringify({advertorial: getComputedStyle(document.getElementById('advertorial-row')).display === 'none', editorial: getComputedStyle(document.getElementById('editorial-row')).display !== 'none'})") { value, error in
                guard error == nil, let text = value as? String,
                      let data = text.data(using: .utf8),
                      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Bool],
                      result["advertorial"] == true, result["editorial"] == true else {
                    self.fail("24.hu selector fixture: \(String(describing: error))")
                    return
                }
                print("PASS: generated 24.hu advertorial selector compiles and hides only the tagged fixture row")
                exit(0)
            }
            return
        }
        webView.evaluateJavaScript("document.getElementById('counter').click(); JSON.stringify(window.testResults())") { value, error in
            guard error == nil, let text = value as? String,
                  let data = text.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.fail("Fixture evaluation: \(String(describing: error))"); return
            }
            guard result["controlLoaded"] as? Bool == true,
                  result["networkBlocked"] as? Bool == self.blocking,
                  result["cosmeticHidden"] as? Bool == self.blocking,
                  result["counter"] as? Int == 1,
                  result["webExtension"] as? Bool == false else {
                self.fail("Unexpected fixture state (blocking=\(self.blocking)): \(text)"); return
            }
            print("PASS: blocking=\(self.blocking) \(text)")
            if self.blocking {
                self.hufilterFixture = true
                self.load()
                return
            }
            self.blocking = true
            self.load()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("Navigation: \(error.localizedDescription)")
    }

    func fail(_ reason: String) {
        fputs("FAIL: \(reason)\n", stderr)
        exit(1)
    }
}

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: WebKitSmoke rules.json temporary-rule-store\n", stderr)
    exit(2)
}
_ = NSApplication.shared
let test = SmokeTest()
test.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 90) { test.fail("Timed out after 90 seconds") }
RunLoop.main.run()
