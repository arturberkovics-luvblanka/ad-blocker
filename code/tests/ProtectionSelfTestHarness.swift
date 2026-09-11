#if os(macOS)
import Foundation

@main
struct ProtectionSelfTestHarness {
    static func main() async {
        guard CommandLine.arguments.count == 2 else { fail("Usage: harness resource-directory") }
        resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            await testEarlyCancellation()
            try await testRequestCap()
            try await testDelayedBlockedRequest()
            try await testStaleRuntime()
            try await testSuccessAndMalformedReport()
            print("PASS: cancellation, request cap, fixed routes, strict reports, delayed block, stale runtime, and success")
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static var resources: URL!
    private static let expectedHash = String(repeating: "a", count: 64)

    static func makeTest() async -> ProtectionSelfTest {
        await ProtectionSelfTest(resourceDirectory: resources, timeout: 5,
                                 expectedAdvancedGeneration: expectedHash,
                                 expectedRuntimeRevision: expectedHash)
    }

    static func testEarlyCancellation() async {
        let test = await makeTest()
        let start = Task { await test.start() }
        while await test.state == .idle { await Task.yield() }
        await test.cancel()
        _ = await start.value
        guard await test.state == .idle else { fail("Cancellation did not return to idle") }
    }

    static func prime(_ test: ProtectionSelfTest) async throws -> (page: URL, nonce: String) {
        guard let pageURL = await test.start() else { fail("Server did not start: \(await test.userMessage)") }
        let page = try await request(pageURL)
        guard page.status == 200, String(decoding: page.data, as: UTF8.self).contains("HELYI MŰKÖDÉSPRÓBA") else {
            fail("Bundled page was not served")
        }
        let root = URL(string: "/", relativeTo: pageURL)!.absoluteURL
        guard try await request(URL(string: "self-test.css", relativeTo: root)!.absoluteURL).status == 200,
              try await request(URL(string: "self-test.js", relativeTo: root)!.absoluteURL).status == 200,
              try await request(URL(string: "missing", relativeTo: root)!.absoluteURL).status == 404 else {
            fail("Fixed resource routing failed")
        }
        let nonce = pageURL.pathComponents.last!
        guard try await request(URL(string: "allowed.svg?session=\(nonce)&phase=before", relativeTo: root)!.absoluteURL).status == 200,
              try await request(URL(string: "allowed.svg?session=\(nonce)&phase=after", relativeTo: root)!.absoluteURL).status == 200 else {
            fail("Positive controls failed")
        }
        return (pageURL, nonce)
    }

    static func sendPage(_ page: URL, nonce: String, malformed: Bool = false) async throws -> Int {
            var forged = URLRequest(url: page.appendingPathComponent("page-report"))
            forged.httpMethod = "POST"
            forged.setValue(page.origin, forHTTPHeaderField: "Origin")
            forged.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if malformed { forged.httpBody = Data("{\"schema\":1}".utf8); return try await request(forged).status }
            let pageReport: [String: Any] = [
                "schema": 1, "nonce": nonce, "allowedLoaded": true, "blockedRejected": true,
                "nativeCosmeticHidden": true, "advancedEffectHidden": true, "usefulControlWorked": true,
            ]
            forged.httpBody = try JSONSerialization.data(withJSONObject: pageReport)
            return try await request(forged).status
    }

    static func sendExtension(_ page: URL, nonce: String, runtime: String = expectedHash) async throws -> Int {
            let extensionReport: [String: Any] = [
                "schema": 1, "nonce": nonce, "extensionVersion": "0.0.2",
                "generation": expectedHash, "runtimeRevision": runtime,
                "contentGeneration": expectedHash, "contentRuntimeRevision": runtime,
                "advancedPhase": "background_attempted_unverified", "advancedError": "",
            ]
            var extensionRequest = URLRequest(url: page.appendingPathComponent("extension-report"))
            extensionRequest.httpMethod = "POST"
            extensionRequest.setValue("safari-web-extension://test", forHTTPHeaderField: "Origin")
            extensionRequest.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            extensionRequest.httpBody = try JSONSerialization.data(withJSONObject: extensionReport)
            return try await request(extensionRequest).status
    }

    static func testDelayedBlockedRequest() async throws {
        let test = await makeTest(); let session = try await prime(test)
        guard try await sendPage(session.page, nonce: session.nonce) == 204,
              try await sendExtension(session.page, nonce: session.nonce) == 204 else { fail("Valid reports rejected") }
        try await Task.sleep(for: .milliseconds(100))
        let root = URL(string: "/", relativeTo: session.page)!.absoluteURL
        _ = try await request(URL(string: "adblocker-self-test-blocked.svg?session=\(session.nonce)", relativeTo: root)!.absoluteURL)
        try await Task.sleep(for: .milliseconds(800))
        guard await !test.succeeded else { fail("Delayed blocked request forged success") }
        await test.cancel()
    }

    static func testRequestCap() async throws {
        let test = await makeTest()
        guard let page = await test.start() else { fail("Request-cap server did not start") }
        let root = URL(string: "/", relativeTo: page)!.absoluteURL
        for index in 0..<32 {
            let response = try await request(URL(string: "missing?request=\(index)", relativeTo: root)!.absoluteURL)
            guard response.status == 404 else { fail("Request cap fired too early at \(index)") }
        }
        do {
            let capped = try await request(URL(string: "missing?request=32", relativeTo: root)!.absoluteURL)
            guard capped.status == 429 else { fail("Request cap did not return 429") }
        } catch {
            // The terminal transition may close the capped connection before
            // URLSession observes its best-effort 429 response.
        }
        try await Task.sleep(for: .milliseconds(50))
        let state = await test.state
        guard case .failed = state else { fail("Request cap did not terminate the test") }
    }

    static func testStaleRuntime() async throws {
        let test = await makeTest(); let session = try await prime(test)
        guard try await sendPage(session.page, nonce: session.nonce) == 204,
              try await sendExtension(session.page, nonce: session.nonce, runtime: String(repeating: "b", count: 64)) == 422 else {
            fail("Stale runtime was accepted")
        }
        guard await !test.succeeded else { fail("Stale runtime reached success") }
        await test.cancel()
    }

    static func testSuccessAndMalformedReport() async throws {
        let test = await makeTest(); let session = try await prime(test)
        guard try await sendPage(session.page, nonce: session.nonce, malformed: true) == 422,
              try await sendPage(session.page, nonce: session.nonce) == 204,
              try await sendExtension(session.page, nonce: session.nonce) == 204 else { fail("Strict report flow failed") }
        try await Task.sleep(for: .milliseconds(850))
        guard await test.succeeded, await test.result?.advancedGeneration == expectedHash,
              await test.result?.runtimeRevision == expectedHash else { fail("Valid flow did not succeed") }
    }

    static func request(_ url: URL) async throws -> (data: Data, status: Int) {
        try await request(URLRequest(url: url))
    }

    static func request(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http.statusCode)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

private extension URL {
    var origin: String { "\(scheme!)://\(host!):\(port!)" }
}
#endif
