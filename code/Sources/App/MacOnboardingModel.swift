#if os(macOS)
import AppKit
import Combine
import SafariServices
import Security

@MainActor
final class MacOnboardingModel: ObservableObject {
    @Published var step: OnboardingStep
    @Published var walkthrough: Bool
    @Published private(set) var readiness = OnboardingReadiness()
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var nativeDetail = "Még nincs ellenőrizve"
    @Published private(set) var webDetail = "Még nincs ellenőrizve"
    @Published private(set) var evidence: OnboardingEvidence?
    @Published private(set) var completing = false

    let selfTest = ProtectionSelfTest()
    let localBuild: Bool
    let installationIssue: String?
    let version: String
    let build: String
    private let store: OnboardingStore
    private var discovery: Task<Void, Never>?
    private var observation: AnyCancellable?
    private var handledTestResult = false

    init(defaults: UserDefaults = .standard, validateInstallation: Bool = true) {
        store = OnboardingStore(defaults: defaults)
        evidence = store.evidence
        walkthrough = store.evidence == nil
        step = store.resumeStep
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        if validateInstallation {
            if Bundle.main.bundleURL.standardizedFileURL.path != "/Applications/Ad Blocker.app" {
                installationIssue = "Az Ad Blockert az Alkalmazások mappából használd. A telepítő az /Applications/Ad Blocker.app példányt készíti elő; a letöltött vagy kicsomagolt másolatot zárd be."
            } else if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                        .contains(where: { $0.bundleURL != nil && $0.bundleURL != Bundle.main.bundleURL }) {
                installationIssue = "Az Ad Blocker egy másik mappából is fut. Zárd be a másik példányt, majd nyisd meg újra az Alkalmazások mappában található Ad Blockert."
            } else if let plugins = Bundle.main.builtInPlugInsURL,
                      ["AdBlockerContentBlocker.appex", "AdBlockerWebExtension.appex"].allSatisfy({
                          FileManager.default.fileExists(atPath: plugins.appendingPathComponent($0).path)
                      }) {
                installationIssue = nil
            } else {
                installationIssue = "Az alkalmazásból hiányzik egy Safari-bővítmény. Telepítsd újra az ellenőrzött Ad Blocker-csomagot."
            }
        } else {
            installationIssue = nil
        }
        var ownCode: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        if SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode,
           SecCodeCopyStaticCode(ownCode, [], &staticCode) == errSecSuccess, let staticCode,
           SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
           let details = information as? [String: Any],
           let team = details[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            localBuild = false
        } else {
            localBuild = true
        }
        observation = selfTest.objectWillChange.sink { [weak self] _ in
            // Published values change after objectWillChange has been sent.
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
                await self?.acceptTestIfReady()
            }
        }
    }

    var previouslyCompleted: Bool { evidence != nil }
    var verifiedThisBuild: Bool {
        evidence?.appVersion == version && evidence?.appBuild == build
            && evidence?.nativeGeneration == NativeRuleBundle.generation
            && evidence?.webGeneration == selfTest.expectedAdvancedGeneration
            && evidence?.runtimeRevision == selfTest.expectedRuntimeRevision
    }

    func go(to step: OnboardingStep) {
        guard step != .complete else { return }
        self.step = step
        store.save(step: step)
        message = nil
    }

    func showWalkthrough() {
        walkthrough = true
        go(to: .welcome)
    }

    func beginDiscovery() {
        discovery?.cancel()
        discovery = Task { [weak self] in
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            repeat {
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
                if self.installationIssue != nil || self.readiness.canTest || ContinuousClock.now >= deadline { return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            } while !Task.isCancelled
        }
    }

    func stop() {
        discovery?.cancel()
        discovery = nil
        selfTest.cancel()
    }

    func refresh(forceRules: Bool = false) async {
        guard !busy else { return }
        if let installationIssue {
            readiness = OnboardingReadiness()
            message = installationIssue
            return
        }
        guard let identifier = Bundle.main.bundleIdentifier else {
            message = "Az alkalmazás adatai nem olvashatók. Telepítsd újra a hivatalos csomagot."
            return
        }
        busy = true
        defer { busy = false }
        let native = await SafariSetupState.native(identifier + ".ContentBlocker")
        let web = await SafariSetupState.web(identifier + ".WebExtension")
        readiness = OnboardingReadiness(nativeKnown: native.known, nativeEnabled: native.enabled,
                                        webKnown: web.known, webEnabled: web.enabled)
        nativeDetail = Self.detail(native)
        webDetail = Self.detail(web)
        if native.known && native.enabled {
            switch await NativeRuleBundle.activate(enabled: true, force: forceRules) {
            case .current, .reloaded:
                readiness.rulesAcknowledged = true
            case .timedOut:
                nativeDetail = "A Safari még nem igazolta vissza a szabálybetöltést."
            case .failed:
                nativeDetail = "A szabályokat nem sikerült betölteni. Próbáld újra."
            case .disabled:
                break
            }
        }
        record()
    }

    func openSettings(native: Bool) {
        if let installationIssue { message = installationIssue; return }
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        message = nil
        SFSafariApplication.showPreferencesForExtension(withIdentifier: identifier + (native ? ".ContentBlocker" : ".WebExtension")) { [weak self] error in
            Task { @MainActor in
                if error != nil {
                    self?.message = "Nyisd meg a Safari → Beállítások → Bővítmények oldalt. Ha az Ad Blocker nem látszik, várj egy kicsit, majd kérj új ellenőrzést."
                }
            }
        }
        beginDiscovery()
    }

    func runTest() async {
        guard !selfTest.isRunning, !busy else { return }
        message = nil
        await refresh()
        guard readiness.canTest else {
            message = "A próbához mindkét bővítmény és a betöltött szűrőlista szükséges. Ellenőrizd a Bekapcsolás lépést."
            return
        }
        handledTestResult = false
        guard let url = await selfTest.start() else { return }
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            selfTest.cancel()
            message = "Nem található a Safari."
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in
                if error != nil {
                    self?.selfTest.cancel()
                    self?.message = "A tesztoldal nem nyílt meg. Próbáld meg újra."
                }
            }
        }
    }

    private func acceptTestIfReady() async {
        guard selfTest.succeeded, !completing, !handledTestResult else { return }
        handledTestResult = true
        completing = true
        defer { completing = false }
        // Do not save success while an earlier refresh still has stale state.
        while busy {
            try? await Task.sleep(for: .milliseconds(100))
            guard selfTest.succeeded, !Task.isCancelled else { return }
        }
        await refresh()
        guard case .succeeded(let tested) = selfTest.state,
              let generation = NativeRuleBundle.generation,
              tested.advancedGeneration == selfTest.expectedAdvancedGeneration,
              tested.runtimeRevision == selfTest.expectedRuntimeRevision else { return }
        let result = OnboardingEvidence(date: Date(), appVersion: version, appBuild: build,
                                       nativeGeneration: generation, webGeneration: tested.advancedGeneration,
                                       runtimeRevision: tested.runtimeRevision)
        if store.complete(result, readiness: readiness, selfTestSucceeded: selfTest.succeeded) {
            evidence = result
            step = .complete
            record()
        } else {
            message = "A teszt közben megváltozott a Safari állapota. Ellenőrizd a kapcsolókat, majd indíts új próbát."
        }
    }

    private static func detail(_ state: SafariSetupState) -> String {
        if !state.known { return "A Safari még nem adott ellenőrizhető állapotot." }
        return state.enabled ? "Bekapcsolva a Safariban" : "Bekapcsolásra vár"
    }

    private func record() {
        UserDefaults.standard.set([
            "phase": readiness.canTest ? "extensions-enabled-self-test-separate" : "setup-needs-attention",
            "date": Date().timeIntervalSince1970,
            "version": version,
            "build": build,
            "native": ["known": readiness.nativeKnown, "enabled": readiness.nativeEnabled],
            "web": ["known": readiness.webKnown, "enabled": readiness.webEnabled],
            "rulesAcknowledged": readiness.rulesAcknowledged,
            "ownWindowCount": NSApplication.shared.windows.count,
        ], forKey: "lastBackgroundSetup")
    }
}
#endif
