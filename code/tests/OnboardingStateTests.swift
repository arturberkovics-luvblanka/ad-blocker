import Foundation

@main
struct OnboardingStateTests {
    static func main() {
        let name = "AdBlocker.OnboardingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = OnboardingStore(defaults: defaults)
        precondition(store.evidence == nil && store.resumeStep == .welcome)
        store.save(step: .websites)
        precondition(OnboardingStore(defaults: defaults).resumeStep == .websites)
        print("PASS: interrupted onboarding resumes without a completion record")

        let evidence = OnboardingEvidence(date: Date(), appVersion: "0.0.2", appBuild: "5",
                                          nativeGeneration: String(repeating: "a", count: 64),
                                          webGeneration: String(repeating: "b", count: 64),
                                          runtimeRevision: String(repeating: "c", count: 64))
        let enabled = OnboardingReadiness(nativeKnown: true, nativeEnabled: true,
                                         webKnown: true, webEnabled: true, rulesAcknowledged: true)
        precondition(!store.complete(evidence, readiness: enabled, selfTestSucceeded: false))
        precondition(store.evidence == nil)
        print("PASS: enabled switches alone cannot complete onboarding")

        var unknown = enabled
        unknown.webKnown = false
        precondition(!store.complete(evidence, readiness: unknown, selfTestSucceeded: true))
        var revoked = enabled
        revoked.nativeEnabled = false
        precondition(!store.complete(evidence, readiness: revoked, selfTestSucceeded: true))
        var pending = enabled
        pending.rulesAcknowledged = false
        precondition(!store.complete(evidence, readiness: pending, selfTestSucceeded: true))
        precondition(store.evidence == nil)
        print("PASS: a successful page cannot override unknown, revoked or unacknowledged Safari state")

        precondition(store.complete(evidence, readiness: enabled, selfTestSucceeded: true))
        precondition(store.evidence == evidence && store.resumeStep == .welcome)
        precondition(!revoked.canTest)
        precondition(!store.complete(evidence, readiness: revoked, selfTestSucceeded: true))
        precondition(store.evidence == evidence)
        print("PASS: historical success survives relaunch but never overrides current permission loss")

        defaults.set(Data("broken".utf8), forKey: "onboardingVerifiedSetupV1")
        precondition(store.evidence == nil)
        defaults.set(1000, forKey: "onboardingResumeStepV1")
        precondition(store.resumeStep == .welcome)
        print("PASS: invalid saved state falls back to unverified onboarding")
    }
}
