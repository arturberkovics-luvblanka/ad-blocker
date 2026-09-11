#if os(macOS)
import Combine
import Foundation
import Network
import Security

@MainActor
final class ProtectionSelfTest: ObservableObject {
    struct Result: Equatable, Sendable {
        let nativeNetworkBlocked: Bool
        let nativeCosmeticHidden: Bool
        let webExtensionPresent: Bool
        let advancedEffectApplied: Bool
        let usefulContentWorked: Bool
        let advancedGeneration: String
        let runtimeRevision: String
    }

    enum State: Equatable, Sendable {
        case idle
        case starting
        case running(URL)
        case succeeded(Result)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var isRunning: Bool {
        if case .starting = state { return true }
        if case .running = state { return true }
        return false
    }

    var succeeded: Bool {
        if case .succeeded = state { return true }
        return false
    }

    var result: Result? {
        if case .succeeded(let result) = state { return result }
        return nil
    }

    private(set) var expectedAdvancedGeneration: String?
    private(set) var expectedRuntimeRevision: String?

    var userMessage: String {
        switch state {
        case .idle:
            return "A működéspróba még nem indult el."
        case .starting:
            return "A helyi működéspróba előkészítése…"
        case .running:
            return "A Safari ellenőrzi a két védelmi réteget…"
        case .succeeded:
            return "A hálózati szűrés, az elrejtés és a webes védelem működik."
        case .failed(let reason):
            return reason
        }
    }

    private let resourceDirectory: URL?
    private let timeout: TimeInterval
    private var server: SelfTestLoopbackServer?

    init(
        resourceDirectory: URL? = nil,
        timeout: TimeInterval = 20,
        expectedAdvancedGeneration: String? = nil,
        expectedRuntimeRevision: String? = nil
    ) {
        self.resourceDirectory = resourceDirectory
        self.timeout = timeout
        let bundled = Self.bundledExpectations()
        self.expectedAdvancedGeneration = expectedAdvancedGeneration ?? bundled.generation
        self.expectedRuntimeRevision = expectedRuntimeRevision ?? bundled.runtimeRevision
    }

    func start() async -> URL? {
        cancel()
        state = .starting

        guard let nonce = Self.secureNonce() else {
            state = .failed("A működéspróba biztonságos azonosítója nem hozható létre.")
            return nil
        }
        guard let expectedAdvancedGeneration, let expectedRuntimeRevision else {
            state = .failed("Az alkalmazás csomagolt verzióadatai hiányoznak. Telepítsd újra az alkalmazást.")
            return nil
        }
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.2"
        let candidate = SelfTestLoopbackServer(
            nonce: nonce,
            expectedAppVersion: appVersion,
            expectedAdvancedGeneration: expectedAdvancedGeneration,
            expectedRuntimeRevision: expectedRuntimeRevision,
            resourceDirectory: resourceDirectory,
            timeout: timeout
        )
        server = candidate

        let started: Swift.Result<URL, Error> = await withCheckedContinuation { continuation in
            candidate.start(onTerminal: { [weak self, weak candidate] terminal in
                Task { @MainActor in
                    guard let self, let candidate, self.server === candidate else { return }
                    self.server = nil
                    switch terminal {
                    case .success(let result):
                        self.state = .succeeded(result)
                    case .failure(let error):
                        self.state = .failed(error.userMessage)
                    }
                }
            }, onReady: { result in
                continuation.resume(returning: result)
            })
        }

        guard server === candidate else { return nil }
        switch started {
        case .success(let url):
            state = .running(url)
            return url
        case .failure(let error):
            server = nil
            state = .failed(SelfTestFailure(error).userMessage)
            return nil
        }
    }

    func cancel() {
        server?.cancel()
        server = nil
        if isRunning { state = .idle }
    }

    private static func secureNonce() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func bundledExpectations() -> (generation: String?, runtimeRevision: String?) {
        let reportURL = Bundle.main.url(forResource: "conversion-report", withExtension: "json")
        let manifestURL = Bundle.main.url(forResource: "build-manifest", withExtension: "json")
        let report = reportURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let outputs = report?["outputs"] as? [String: Any]
        let manifest = manifestURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let generation = outputs?["advancedRulesSHA256"] as? String
        let revision = manifest?["runtimeRevision"] as? String
        return (generation.flatMap(validHash), revision.flatMap(validHash))
    }

    private static func validHash(_ value: String) -> String? {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase } ? value : nil
    }
}

private struct SelfTestFailure: Error, Sendable {
    let code: Code

    enum Code: Sendable {
        case startup
        case resources
        case invalidReport
        case requestLimit
        case timedOut
    }

    init(_ code: Code) { self.code = code }
    init(_ error: Error) { self.code = (error as? SelfTestFailure)?.code ?? .startup }

    var userMessage: String {
        switch code {
        case .startup:
            return "A helyi működéspróba nem indítható el. Próbáld újra."
        case .resources:
            return "A működéspróba egyik csomagolt fájlja hiányzik. Telepítsd újra az alkalmazást."
        case .invalidReport:
            return "A Safari próbajelentése hiányos vagy nem az aktuális futtatáshoz tartozik."
        case .requestLimit:
            return "A működéspróba túl sok kérést kapott, ezért biztonságosan leállt."
        case .timedOut:
            return "A Safari nem igazolta a teljes védelmet 20 másodpercen belül. Ellenőrizd mindkét bővítményt és az oldalengedélyt."
        }
    }
}

private final class SelfTestLoopbackServer: @unchecked Sendable {
    private struct HTTPRequest {
        let method: String
        let target: String
        let headers: [String: String]
        let body: Data
    }

    private let nonce: String
    private let expectedAppVersion: String
    private let expectedAdvancedGeneration: String
    private let expectedRuntimeRevision: String
    private let resourceDirectory: URL?
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "org.local.adblocker.self-test")
    private var listener: NWListener?
    private var terminal: ((Result<ProtectionSelfTest.Result, SelfTestFailure>) -> Void)?
    private var port: NWEndpoint.Port?
    private var requestCount = 0
    private var allowedPhases = Set<String>()
    private var blockedSeen = false
    private var pageReportAccepted = false
    private var extensionGeneration: String?
    private var extensionRuntimeRevision: String?
    private var completionScheduled = false
    private var finished = false
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var readyCallback: ((Swift.Result<URL, Error>) -> Void)?
    private var readyReported = false

    init(
        nonce: String,
        expectedAppVersion: String,
        expectedAdvancedGeneration: String,
        expectedRuntimeRevision: String,
        resourceDirectory: URL?,
        timeout: TimeInterval
    ) {
        self.nonce = nonce
        self.expectedAppVersion = expectedAppVersion
        self.expectedAdvancedGeneration = expectedAdvancedGeneration
        self.expectedRuntimeRevision = expectedRuntimeRevision
        self.resourceDirectory = resourceDirectory
        self.timeout = timeout
    }

    func start(
        onTerminal: @escaping (Result<ProtectionSelfTest.Result, SelfTestFailure>) -> Void,
        onReady: @escaping (Result<URL, Error>) -> Void
    ) {
        queue.async { [self] in
            terminal = onTerminal
            readyCallback = onReady
            queue.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, !self.readyReported else { return }
                self.completeReady(.failure(SelfTestFailure(.startup)))
                self.stop()
            }
            do {
                for name in ["index.html", "self-test.css", "self-test.js"] {
                    guard resourceURL(name) != nil else { throw SelfTestFailure(.resources) }
                }
                let parameters = NWParameters.tcp
                parameters.includePeerToPeer = false
                parameters.allowLocalEndpointReuse = false
                let listener = try NWListener(using: parameters, on: .any)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    self.queue.async { [self] in
                        switch state {
                        case .ready:
                            guard let port = listener.port else { return }
                            self.port = port
                            let url = URL(string: "http://127.0.0.1:\(port.rawValue)/session/\(self.nonce)/")!
                            self.completeReady(.success(url))
                            self.queue.asyncAfter(deadline: .now() + self.timeout) { [weak self] in
                                self?.finish(.failure(SelfTestFailure(.timedOut)))
                            }
                        case .failed(let error):
                            if !self.readyReported {
                                self.completeReady(.failure(error))
                                self.stop()
                            } else {
                                self.finish(.failure(SelfTestFailure(.startup)))
                            }
                        default:
                            break
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.queue.async { [weak self] in self?.accept(connection) }
                }
                listener.start(queue: self.queue)
            } catch {
                completeReady(.failure(error))
                stop()
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            if !readyReported { completeReady(.failure(CancellationError())) }
            stop()
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !finished,
              case .hostPort(let host, _) = connection.endpoint,
              host == .ipv4(.loopback) else {
            connection.cancel()
            return
        }
        let identifier = ObjectIdentifier(connection)
        connections[identifier] = connection
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { [weak self, weak connection] in
            guard let self, let connection, self.connections[identifier] != nil else { return }
            self.connections[identifier] = nil
            connection.cancel()
        }
        readMore(connection, buffer: Data())
    }

    private func readMore(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            self.queue.async {
                var accumulated = buffer
                if let data { accumulated.append(data) }
                if accumulated.count > 24_576 {
                    self.respond(connection, status: 413, body: Data())
                    return
                }
                if let request = self.parseRequest(accumulated) {
                    self.handle(request, connection: connection)
                } else if complete || error != nil {
                    self.respond(connection, status: 400, body: Data())
                } else {
                    self.readMore(connection, buffer: accumulated)
                }
            }
        }
    }

    private func parseRequest(_ data: Data) -> HTTPRequest? {
        let separator = Data([13, 10, 13, 10])
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let requestLine = first.split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2] == "HTTP/1.1" else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, headers[key] == nil else { return nil }
            headers[key] = value
        }
        guard let lengthText = headers["content-length"] ?? "0" as String?,
              let length = Int(lengthText), (0...8192).contains(length) else { return nil }
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + length else { return nil }
        return HTTPRequest(
            method: String(requestLine[0]),
            target: String(requestLine[1]),
            headers: headers,
            body: data.subdata(in: bodyStart..<(bodyStart + length))
        )
    }

    private func handle(_ request: HTTPRequest, connection: NWConnection) {
        requestCount += 1
        guard requestCount <= 32 else {
            respond(connection, status: 429, body: Data())
            finish(.failure(SelfTestFailure(.requestLimit)))
            return
        }
        guard let port,
              request.headers["host"] == "127.0.0.1:\(port.rawValue)" else {
            respond(connection, status: 400, body: Data())
            return
        }
        let parts = request.target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts[0])
        let query = parts.count == 2 ? String(parts[1]) : ""
        let pageOrigin = "http://127.0.0.1:\(port.rawValue)"
        let sessionPath = "/session/\(nonce)/"

        if request.method == "GET", path == sessionPath, query.isEmpty {
            serve("index.html", type: "text/html; charset=utf-8", connection: connection)
        } else if request.method == "GET", path == "/self-test.css", query.isEmpty {
            serve("self-test.css", type: "text/css; charset=utf-8", connection: connection)
        } else if request.method == "GET", path == "/self-test.js", query.isEmpty {
            serve("self-test.js", type: "text/javascript; charset=utf-8", connection: connection)
        } else if request.method == "GET", path == "/allowed.svg",
                  (query == "session=\(nonce)&phase=before" || query == "session=\(nonce)&phase=after") {
            allowedPhases.insert(query.hasSuffix("before") ? "before" : "after")
            respond(connection, status: 200, type: "image/svg+xml", body: Self.allowedSVG)
        } else if request.method == "GET", path == "/adblocker-self-test-blocked.svg", query == "session=\(nonce)" {
            blockedSeen = true
            respond(connection, status: 200, type: "image/svg+xml", body: Self.blockedSVG)
        } else if request.method == "OPTIONS", path == sessionPath + "extension-report" {
            handlePreflight(request, origin: request.headers["origin"], connection: connection)
        } else if request.method == "POST", path == sessionPath + "page-report", query.isEmpty {
            guard request.headers["origin"] == pageOrigin,
                  request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                  validPageReport(request.body) else {
                respond(connection, status: 422, body: Data())
                return
            }
            pageReportAccepted = true
            respond(connection, status: 204, body: Data())
            completeIfPossible()
        } else if request.method == "POST", path == sessionPath + "extension-report", query.isEmpty {
            let origin = request.headers["origin"]
            guard validExtensionOrigin(origin),
                  request.headers["content-type"]?.lowercased().hasPrefix("text/plain") == true,
                  let evidence = validExtensionReport(request.body) else {
                respond(connection, status: 422, body: Data(), corsOrigin: origin)
                return
            }
            extensionGeneration = evidence.generation
            extensionRuntimeRevision = evidence.runtimeRevision
            respond(connection, status: 204, body: Data(), corsOrigin: origin)
            completeIfPossible()
        } else {
            respond(connection, status: 404, body: Data())
        }
    }

    private func validPageReport(_ data: Data) -> Bool {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(value.keys) == Set(["schema", "nonce", "allowedLoaded", "blockedRejected",
                                      "nativeCosmeticHidden", "advancedEffectHidden", "usefulControlWorked"]),
              value["schema"] as? Int == 1,
              value["nonce"] as? String == nonce else { return false }
        let required = ["allowedLoaded", "blockedRejected", "nativeCosmeticHidden",
                        "advancedEffectHidden", "usefulControlWorked"]
        return allowedPhases == Set(["before", "after"]) && !blockedSeen
            && required.allSatisfy { Self.strictBool(value[$0]) == true }
    }

    private func validExtensionReport(_ data: Data) -> (generation: String, runtimeRevision: String)? {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(value.keys) == Set(["schema", "nonce", "extensionVersion", "generation",
                                      "runtimeRevision", "contentGeneration", "contentRuntimeRevision",
                                      "advancedPhase", "advancedError"]),
              value["schema"] as? Int == 1,
              value["nonce"] as? String == nonce,
              value["extensionVersion"] as? String == expectedAppVersion,
              let generation = value["generation"] as? String,
              let contentGeneration = value["contentGeneration"] as? String,
              generation == contentGeneration, generation == expectedAdvancedGeneration,
              let revision = value["runtimeRevision"] as? String,
              let contentRevision = value["contentRuntimeRevision"] as? String,
              revision == contentRevision, revision == expectedRuntimeRevision,
              value["advancedPhase"] as? String == "background_attempted_unverified",
              value["advancedError"] as? String == "" else { return nil }
        return (generation, revision)
    }

    private func handlePreflight(_ request: HTTPRequest, origin: String?, connection: NWConnection) {
        guard validExtensionOrigin(origin),
              request.headers["access-control-request-method"] == "POST" else {
            respond(connection, status: 403, body: Data())
            return
        }
        respond(connection, status: 204, body: Data(), corsOrigin: origin)
    }

    private func validExtensionOrigin(_ origin: String?) -> Bool {
        guard let origin, origin.count <= 512 else { return false }
        return origin.hasPrefix("safari-web-extension://")
            || origin.hasPrefix("browser-extension://")
            || origin.hasPrefix("moz-extension://")
    }

    private func completeIfPossible() {
        guard pageReportAccepted, extensionGeneration != nil, extensionRuntimeRevision != nil,
              allowedPhases == Set(["before", "after"]), !blockedSeen, !completionScheduled else { return }
        completionScheduled = true
        queue.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self, !self.finished else { return }
            guard self.pageReportAccepted,
                  let generation = self.extensionGeneration,
                  let runtimeRevision = self.extensionRuntimeRevision,
                  self.allowedPhases == Set(["before", "after"]), !self.blockedSeen else {
                self.finish(.failure(SelfTestFailure(.invalidReport)))
                return
            }
            self.finish(.success(ProtectionSelfTest.Result(
                nativeNetworkBlocked: true,
                nativeCosmeticHidden: true,
                webExtensionPresent: true,
                advancedEffectApplied: true,
                usefulContentWorked: true,
                advancedGeneration: generation,
                runtimeRevision: runtimeRevision
            )))
        }
    }

    private func serve(_ name: String, type: String, connection: NWConnection) {
        guard let url = resourceURL(name), let data = try? Data(contentsOf: url) else {
            respond(connection, status: 500, body: Data())
            finish(.failure(SelfTestFailure(.resources)))
            return
        }
        respond(connection, status: 200, type: type, body: data)
    }

    private func resourceURL(_ name: String) -> URL? {
        if let resourceDirectory {
            let candidate = resourceDirectory.appendingPathComponent(name, isDirectory: false)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
        if let root = Bundle.main.resourceURL {
            let nested = root.appendingPathComponent("SelfTest", isDirectory: true).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
            let flat = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: flat.path) { return flat }
        }
        return nil
    }

    private func respond(
        _ connection: NWConnection,
        status: Int,
        type: String = "text/plain; charset=utf-8",
        body: Data,
        corsOrigin: String? = nil
    ) {
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 403: "Forbidden",
                      404: "Not Found", 413: "Content Too Large", 422: "Unprocessable Content",
                      429: "Too Many Requests", 500: "Internal Server Error"][status] ?? "Error"
        var headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Length: \(body.count)",
            "Content-Type: \(type)",
            "Cache-Control: no-store",
            "Content-Security-Policy: default-src 'self'; img-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'",
            "X-Content-Type-Options: nosniff",
            "Connection: close",
        ]
        if let corsOrigin {
            headers.append("Access-Control-Allow-Origin: \(corsOrigin)")
            headers.append("Access-Control-Allow-Methods: POST, OPTIONS")
            headers.append("Access-Control-Allow-Headers: Content-Type")
            headers.append("Vary: Origin")
        }
        var response = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        response.append(body)
        let identifier = ObjectIdentifier(connection)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            self?.queue.async { self?.connections[identifier] = nil }
        })
    }

    private func finish(_ result: Result<ProtectionSelfTest.Result, SelfTestFailure>) {
        guard !finished else { return }
        finished = true
        let callback = terminal
        stop()
        callback?(result)
    }

    private func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        terminal = nil
    }

    private func completeReady(_ result: Swift.Result<URL, Error>) {
        guard !readyReported else { return }
        readyReported = true
        let callback = readyCallback
        readyCallback = nil
        callback?(result)
    }

    private static func strictBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static let allowedSVG = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"2\" height=\"2\"><path fill=\"#0a6\" d=\"M0 0h2v2H0z\"/></svg>".utf8)
    private static let blockedSVG = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"2\" height=\"2\"><path fill=\"#d43\" d=\"M0 0h2v2H0z\"/></svg>".utf8)
}
#endif
