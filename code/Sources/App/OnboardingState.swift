import Foundation

// A saved walkthrough is a preference, never evidence of current Safari state.
enum OnboardingStep: Int, CaseIterable {
    case welcome, extensions, websites, test, complete

    var title: String {
        switch self {
        case .welcome: return "Így működik"
        case .extensions: return "Bekapcsolás"
        case .websites: return "Webhelyek"
        case .test: return "Működéspróba"
        case .complete: return "Kész"
        }
    }
}

struct OnboardingEvidence: Codable, Equatable {
    let date: Date
    let appVersion: String
    let appBuild: String
    let nativeGeneration: String
    let webGeneration: String
    let runtimeRevision: String
}

struct OnboardingReadiness: Equatable {
    var nativeKnown = false
    var nativeEnabled = false
    var webKnown = false
    var webEnabled = false
    var rulesAcknowledged = false

    var extensionsEnabled: Bool {
        nativeKnown && webKnown && nativeEnabled && webEnabled
    }

    var canTest: Bool { extensionsEnabled && rulesAcknowledged }

    func canComplete(selfTestSucceeded: Bool) -> Bool {
        canTest && selfTestSucceeded
    }
}

struct OnboardingStore {
    let defaults: UserDefaults
    private let evidenceKey = "onboardingVerifiedSetupV1"
    private let stepKey = "onboardingResumeStepV1"

    var evidence: OnboardingEvidence? {
        guard let data = defaults.data(forKey: evidenceKey) else { return nil }
        return try? JSONDecoder().decode(OnboardingEvidence.self, from: data)
    }

    var resumeStep: OnboardingStep {
        guard let step = OnboardingStep(rawValue: defaults.integer(forKey: stepKey)),
              step != .complete else { return .welcome }
        return step
    }

    func save(step: OnboardingStep) {
        guard step != .complete else { return }
        defaults.set(step.rawValue, forKey: stepKey)
    }

    @discardableResult
    func complete(_ evidence: OnboardingEvidence, readiness: OnboardingReadiness,
                  selfTestSucceeded: Bool) -> Bool {
        guard readiness.canComplete(selfTestSucceeded: selfTestSucceeded),
              evidence.nativeGeneration.count == 64,
              evidence.webGeneration.count == 64, evidence.runtimeRevision.count == 64,
              let data = try? JSONEncoder().encode(evidence) else { return false }
        defaults.set(data, forKey: evidenceKey)
        defaults.removeObject(forKey: stepKey)
        return true
    }
}
