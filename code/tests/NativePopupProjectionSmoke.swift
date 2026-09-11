import AppKit
import WebKit

final class NativePopupProjectionSmoke: NSObject, WKNavigationDelegate, WKUIDelegate {
    enum Phase {
        case genericControl
        case genericDocumentProtected
        case genericPopupProtected
        case projectedControl
        case projectedDocumentThirdParty
        case projectedPopupThirdParty
        case projectedPopupFirstParty
        case projectedLinkControl
        case projectedLinkProtected
        case productThirdParty
        case productFirstParty
        case productException
    }

    let store: WKContentRuleListStore
    let projectedJSON: String
    let productJSON: String
    var genericDocumentRules: WKContentRuleList!
    var genericPopupRules: WKContentRuleList!
    var projectedDocumentRules: WKContentRuleList!
    var projectedPopupRules: WKContentRuleList!
    var productRules: WKContentRuleList!
    var productExceptionRules: WKContentRuleList!
    var phase: Phase = .genericControl
    var popupRequests: [String] = []
    var iframeRequests: [String] = []
    var webView: WKWebView!

    let genericTarget = "https://popup-block.invalid/ad"
    let projectedTargets = [
        "https://35.1.2.3/",
        "http://104.255.0.9/",
        "https://146.59.211.42/path",
    ]
    let usefulTarget = "https://example.com/useful"

    init(projectedJSON: String, productJSON: String, storeURL: URL) {
        self.projectedJSON = projectedJSON
        self.productJSON = productJSON
        store = WKContentRuleListStore(url: storeURL)!
    }

    func start() {
        let genericDocumentJSON = """
        [{"trigger":{"url-filter":"^https://popup-block\\\\.invalid/","load-type":["third-party"],"resource-type":["document"]},"action":{"type":"block"}}]
        """
        let genericPopupJSON = replacingResourceType(in: genericDocumentJSON, with: "popup")
        let projectedPopupJSON = replacingResourceType(in: projectedJSON, with: "popup")
        compile("NativePopupGenericDocument", genericDocumentJSON) { self.genericDocumentRules = $0
            self.compile("NativePopupGenericPopup", genericPopupJSON) { self.genericPopupRules = $0
                self.compile("NativePopupProjectionDocument", self.projectedJSON) { self.projectedDocumentRules = $0
                    self.compile("NativePopupProjectionPopup", projectedPopupJSON) { self.projectedPopupRules = $0
                        self.compile("NativePopupProduct", self.productJSON) { self.productRules = $0
                            var exceptions = try! JSONSerialization.jsonObject(with: Data(self.productJSON.utf8)) as! [[String: Any]]
                            var allowed = exceptions[0]
                            allowed["action"] = ["type": "ignore-previous-rules"]
                            exceptions.append(allowed)
                            let json = String(decoding: try! JSONSerialization.data(withJSONObject: exceptions), as: UTF8.self)
                            self.compile("NativePopupProductException", json) { self.productExceptionRules = $0
                                self.loadPhase()
                            }
                        }
                    }
                }
            }
        }
    }

    func compile(_ identifier: String, _ json: String, completion: @escaping (WKContentRuleList) -> Void) {
        store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
            guard let list else {
                self.fail("\(identifier) compilation failed: \(error?.localizedDescription ?? "unknown error")")
            }
            completion(list)
        }
    }

    func replacingResourceType(in json: String, with type: String) -> String {
        let data = Data(json.utf8)
        guard var rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            fail("Rule projection JSON was invalid")
        }
        for index in rules.indices {
            guard var trigger = rules[index]["trigger"] as? [String: Any] else {
                fail("Projected rule had no trigger")
            }
            trigger["resource-type"] = [type]
            rules[index]["trigger"] = trigger
        }
        let output = try! JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
        return String(decoding: output, as: UTF8.self)
    }

    func loadPhase() {
        popupRequests = []
        iframeRequests = []

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        switch phase {
        case .genericDocumentProtected:
            configuration.userContentController.add(genericDocumentRules)
        case .genericPopupProtected:
            configuration.userContentController.add(genericPopupRules)
        case .projectedDocumentThirdParty:
            configuration.userContentController.add(projectedDocumentRules)
        case .projectedPopupThirdParty, .projectedPopupFirstParty, .projectedLinkProtected:
            configuration.userContentController.add(projectedPopupRules)
        case .productThirdParty, .productFirstParty:
            configuration.userContentController.add(productRules)
        case .productException:
            configuration.userContentController.add(productExceptionRules)
        case .genericControl, .projectedControl, .projectedLinkControl:
            break
        }

        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self

        let baseURL: URL
        if phase == .projectedPopupFirstParty || phase == .productFirstParty {
            baseURL = URL(string: "https://35.1.2.3/publisher")!
        } else {
            baseURL = URL(string: "https://publisher.invalid/page")!
        }
        webView.loadHTMLString(
            "<!doctype html><html><body><main id='content'>Useful page content</main></body></html>",
            baseURL: baseURL
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let targets: [String]
        switch phase {
        case .genericControl, .genericDocumentProtected, .genericPopupProtected:
            targets = [genericTarget, usefulTarget]
        case .projectedControl, .projectedDocumentThirdParty, .projectedPopupThirdParty,
             .projectedLinkControl, .projectedLinkProtected, .productThirdParty, .productException:
            targets = projectedTargets + [usefulTarget]
        case .projectedPopupFirstParty, .productFirstParty:
            targets = [projectedTargets[0], usefulTarget]
        }
        if phase == .projectedLinkControl || phase == .projectedLinkProtected {
            triggerLinksSequentially(targets, index: 0)
            return
        }
        let script = """
        (() => {
          const targets = \(json(targets));
          for (const target of targets) window.open(target, '_blank');
          const frame = document.createElement('iframe');
          frame.src = targets[0];
          document.body.append(frame);
          return document.getElementById('content').textContent;
        })()
        """
        webView.evaluateJavaScript(script) { value, error in
            guard error == nil, value as? String == "Useful page content" else {
                self.fail("Fixture action failed: \(String(describing: error))")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkPhase()
            }
        }
    }

    // Several same-turn link activations can replace a pending navigation.
    // Use separate native calls so the OFF control actually attempts every link.
    func triggerLinksSequentially(_ targets: [String], index: Int) {
        let script: String
        if index < targets.count {
            script = """
            (() => {
              const link = document.createElement('a');
              link.href = \(json([targets[index]])).at(0); link.target = '_blank';
              document.body.append(link); link.click();
            })()
            """
        } else {
            script = """
            (() => {
              const frame = document.createElement('iframe');
              frame.src = \(json([targets[0]])).at(0); document.body.append(frame);
              return document.getElementById('content').textContent;
            })()
            """
        }
        webView.evaluateJavaScript(script) { value, error in
            guard error == nil else { self.fail("Link control evaluation failed: \(error!)") }
            if index < targets.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.triggerLinksSequentially(targets, index: index + 1)
                }
            } else {
                guard value as? String == "Useful page content" else { self.fail("Useful content changed") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.checkPhase() }
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame == false,
              let url = navigationAction.request.url?.absoluteString,
              isTestTarget(url) else {
            decisionHandler(.allow)
            return
        }
        iframeRequests.append(url)
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url?.absoluteString {
            popupRequests.append(url)
        }
        return nil
    }

    func checkPhase() {
        switch phase {
        case .genericControl:
            guard popupRequests == [genericTarget, usefulTarget],
                  iframeRequests == [genericTarget] else {
                fail("Generic OFF control was unexpected: popups=\(popupRequests), iframes=\(iframeRequests)")
            }
            print("PASS: native popup OFF control reached WKUIDelegate; iframe control reached navigation policy")
            phase = .genericDocumentProtected
            loadPhase()

        case .genericDocumentProtected:
            guard popupRequests == [usefulTarget] || popupRequests == [genericTarget, usefulTarget],
                  iframeRequests.isEmpty || iframeRequests == [genericTarget] else {
                fail("Generic document rule produced unexpected requests: popups=\(popupRequests), iframes=\(iframeRequests)")
            }
            print("OBSERVED: generic resource-type=document popups=\(popupRequests), iframes=\(iframeRequests)")
            phase = .genericPopupProtected
            loadPhase()

        case .genericPopupProtected:
            guard popupRequests == [usefulTarget], iframeRequests == [genericTarget] else {
                fail("Native resource-type=popup did not suppress the target request: popups=\(popupRequests), iframes=\(iframeRequests)")
            }
            print("PASS: generic resource-type=popup suppressed only the target popup request; matching iframe still reached the pre-network cancel policy")
            phase = .projectedControl
            loadPhase()

        case .projectedControl:
            guard popupRequests == projectedTargets + [usefulTarget],
                  iframeRequests == [projectedTargets[0]] else {
                fail("Projected OFF control was unexpected: popups=\(popupRequests), iframes=\(iframeRequests)")
            }
            print("PASS: projected OFF control attempted all three IP popups and the useful popup")
            phase = .projectedDocumentThirdParty
            loadPhase()

        case .projectedDocumentThirdParty:
            guard popupRequests == [usefulTarget] || popupRequests == projectedTargets + [usefulTarget],
                  iframeRequests.isEmpty || iframeRequests == [projectedTargets[0]] else {
                fail("Projected document rules produced unexpected requests: popups=\(popupRequests), iframes=\(iframeRequests)")
            }
            print("OBSERVED: projected resource-type=document popups=\(popupRequests), iframes=\(iframeRequests)")
            phase = .projectedPopupThirdParty
            loadPhase()

        case .projectedPopupThirdParty:
            guard popupRequests == [usefulTarget], iframeRequests == [projectedTargets[0]] else {
                fail("Projected popup rules were not popup-only: popups=\(popupRequests), iframes=\(iframeRequests)")
            }
            print("PASS: projected resource-type=popup rules suppressed all three third-party IP popups and preserved the useful popup; matching iframe reached the pre-network cancel policy")
            phase = .projectedPopupFirstParty
            loadPhase()

        case .projectedPopupFirstParty:
            guard popupRequests == [projectedTargets[0], usefulTarget],
                  iframeRequests == [projectedTargets[0]] else {
                fail("Projected first-party control was unexpected: popups=\(popupRequests), iframes=\(iframeRequests)")
            }
            print("PASS: third-party condition preserved the same-IP first-party popup; its iframe request reached the pre-network cancel policy")
            phase = .projectedLinkControl
            loadPhase()

        case .projectedLinkControl:
            guard popupRequests == projectedTargets + [usefulTarget],
                  iframeRequests == [projectedTargets[0]] else {
                fail("Target-blank link OFF control was unexpected: popups=\(popupRequests), iframes=\(iframeRequests)")
            }
            print("PASS: target=_blank link OFF control attempted all targets and the useful window")
            phase = .projectedLinkProtected
            loadPhase()

        case .projectedLinkProtected:
            guard popupRequests == projectedTargets + [usefulTarget], iframeRequests == [projectedTargets[0]] else {
                fail("Target-blank link behavior changed; reassess its popup classification: \(popupRequests)")
            }
            print("CONFIRMED LIMITATION: popup-only rules did not suppress target=_blank link window requests; document fallback must not be removed")
            phase = .productThirdParty
            loadPhase()

        case .productThirdParty:
            guard popupRequests == [usefulTarget] else {
                fail("Generated product rules leaked a third-party popup: \(popupRequests)")
            }
            print("PASS: actual generated document+popup projections block all three third-party window.open requests and preserve useful popup")
            phase = .productFirstParty
            loadPhase()

        case .productFirstParty:
            guard popupRequests == [projectedTargets[0], usefulTarget] else {
                fail("Generated product rules blocked first-party control: \(popupRequests)")
            }
            print("PASS: actual generated document+popup projections preserve first-party window.open")
            phase = .productException
            loadPhase()

        case .productException:
            guard popupRequests == [projectedTargets[0], usefulTarget] else {
                fail("Generated product-derived exception failed: \(popupRequests)")
            }
            print("PASS: ignore-previous-rules exception restores only its selected popup; other blocked targets stay blocked")
            exit(0)
        }
    }

    func isTestTarget(_ url: String) -> Bool {
        url == genericTarget || projectedTargets.contains(url)
    }

    func json(_ strings: [String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: strings)
        return String(decoding: data, as: UTF8.self)
    }

    func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

guard CommandLine.arguments.count == 4 else {
    fputs("usage: NativePopupProjectionSmoke <legacy-projection.json> <rule-store> <product-projection.json>\n", stderr)
    exit(2)
}

let projectedJSON = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
guard let projectedRules = try JSONSerialization.jsonObject(with: Data(projectedJSON.utf8)) as? [[String: Any]],
      projectedRules.count == 3,
      projectedRules.allSatisfy({ rule in
          let trigger = rule["trigger"] as? [String: Any]
          let action = rule["action"] as? [String: Any]
          return trigger?["url-filter"] is String
              && (trigger?["load-type"] as? [String]) == ["third-party"]
              && (trigger?["resource-type"] as? [String]) == ["document"]
              && action?["type"] as? String == "block"
      }) else {
    fputs("FAIL: expected exactly three third-party document-block projection rules\n", stderr)
    exit(2)
}

let productJSON = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
let product = try JSONSerialization.jsonObject(with: Data(productJSON.utf8)) as! [[String: Any]]
guard product.count == 3, zip(projectedRules, product).allSatisfy({ old, new in
    var expected = old
    var trigger = old["trigger"] as! [String: Any]
    trigger["resource-type"] = ["document", "popup"]
    expected["trigger"] = trigger
    return NSDictionary(dictionary: expected).isEqual(to: new)
}) else {
    fputs("FAIL: generated product rules differ beyond adding the popup resource type\n", stderr)
    exit(2)
}

_ = NSApplication.shared
let smoke = NativePopupProjectionSmoke(
    projectedJSON: projectedJSON,
    productJSON: productJSON,
    storeURL: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
)
smoke.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 45) { smoke.fail("Timed out") }
RunLoop.main.run()
