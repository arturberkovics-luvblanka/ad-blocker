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
            let scopedSelectors = [
                (".pr-row:has(article.m-articleWidget__wrap .m-articleWidget__tag)", "*24.hu"),
                ("article.m-articleWidget__wrap:has(a.m-articleWidget__link[href^=\"https://ng.24.hu/egyeb/2026/09/11/megerkeztek-a-felix-doubly-delicious-szaraz-macskaeledelek-ketszeres-finomsag-minden-falatban-x/\"])", "*24.hu"),
                ("li.m-nonstopWidget__item:has(> a.m-nonstopWidget__link[href^=\"https://24.hu/tech/2026/09/11/itt-az-uj-okauchan-igazi-2-in-1/\"])", "*24.hu"),
                (".rltd_item_container:has(> a.rltd_item > span.rltd_tag:not(.rltd_article_tag))", "*hvg.hu"),
                (".sidebar-brandlab", "*hvg.hu"),
                (".mntl-site-wide-notification:has(a[href^=\"https://myrecipesapp.onelink.me/Wc8m\"])", "*allrecipes.com"),
            ]
            for (selector, domain) in scopedSelectors {
                let generatedRuleExists = rules.contains { rule in
                    let action = rule["action"] as? [String: Any]
                    let trigger = rule["trigger"] as? [String: Any]
                    let domains = trigger?["if-domain"] as? [String]
                    return (action?["selector"] as? String)?.contains(selector) == true
                        && domains?.contains(domain) == true
                }
                guard generatedRuleExists else {
                    fail("Missing generated 24.hu rule: \(selector)")
                    return
                }
            }
            // The product rule is scoped to 24.hu. Add an otherwise identical
            // local-only copy so WebKit can exercise each selector on the fixture.
            for (selector, _) in scopedSelectors {
                rules.append([
                    "trigger": ["url-filter": ".*", "if-domain": ["127.0.0.1"]],
                    "action": ["type": "css-display-none", "selector": selector],
                ])
            }
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
            let script = """
                JSON.stringify({
                    advertorial: getComputedStyle(document.getElementById('advertorial-row')).display === 'none',
                    editorial: getComputedStyle(document.getElementById('editorial-row')).display !== 'none',
                    felix: getComputedStyle(document.getElementById('felix-sponsored-card')).display === 'none',
                    ngEditorial: getComputedStyle(document.getElementById('ng-editorial-card')).display !== 'none',
                    ngNearMatch: getComputedStyle(document.getElementById('ng-near-match-card')).display !== 'none',
                    subscriber: getComputedStyle(document.getElementById('subscriber-article')).display !== 'none',
                    okauchan: getComputedStyle(document.getElementById('okauchan-sponsored-item')).display === 'none',
                    ordinaryCurrent: getComputedStyle(document.getElementById('ordinary-current-item')).display !== 'none',
                    hvgSponsored: getComputedStyle(document.getElementById('hvg-sponsored-card')).display === 'none',
                    hvgEditorial: getComputedStyle(document.getElementById('hvg-editorial-card')).display !== 'none',
                    hvgPartnerLabel: getComputedStyle(document.getElementById('hvg-partner-label-card')).display !== 'none',
                    hvgBrandLab: getComputedStyle(document.getElementById('hvg-brandlab')).display === 'none',
                    hvgEditorialSidebar: getComputedStyle(document.getElementById('hvg-editorial-sidebar')).display !== 'none',
                    allrecipesBanner: getComputedStyle(document.getElementById('allrecipes-app-banner')).display === 'none',
                    allrecipesOtherNotice: getComputedStyle(document.getElementById('allrecipes-other-notification')).display !== 'none',
                    allrecipesNavigation: getComputedStyle(document.getElementById('allrecipes-navigation')).display !== 'none',
                    allrecipesSave: getComputedStyle(document.getElementById('allrecipes-save-recipe')).display !== 'none'
                })
                """
            webView.evaluateJavaScript(script) { value, error in
                guard error == nil, let text = value as? String,
                      let data = text.data(using: .utf8),
                      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Bool],
                      result["advertorial"] == true,
                      result["editorial"] == true,
                      result["felix"] == true,
                      result["ngEditorial"] == true,
                      result["ngNearMatch"] == true,
                      result["subscriber"] == true,
                      result["okauchan"] == true,
                      result["ordinaryCurrent"] == true,
                      result["hvgSponsored"] == true,
                      result["hvgEditorial"] == true,
                      result["hvgPartnerLabel"] == true,
                      result["hvgBrandLab"] == true,
                      result["hvgEditorialSidebar"] == true,
                      result["allrecipesBanner"] == true,
                      result["allrecipesOtherNotice"] == true,
                      result["allrecipesNavigation"] == true,
                      result["allrecipesSave"] == true else {
                    self.fail("24.hu selector fixture: \(String(describing: error))")
                    return
                }
                print("PASS: generated site selectors hide the observed adverts and preserve the negative fixtures")
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
