import Foundation

@MainActor
final class NativeRuleActivation {
    enum Outcome: Equatable {
        case current
        case reloaded
        case disabled
        case failed(String)
        case timedOut
    }

    private struct Active {
        let id: UUID
        let generation: String
        let task: Task<Outcome, Never>
    }

    private let readAcknowledged: () -> String?
    private let writeAcknowledged: (String) -> Void
    private var active: Active?
    private var automaticFailures: [String: Outcome] = [:]

    init(
        readAcknowledged: @escaping () -> String?,
        writeAcknowledged: @escaping (String) -> Void
    ) {
        self.readAcknowledged = readAcknowledged
        self.writeAcknowledged = writeAcknowledged
    }

    func activate(
        generation: String,
        enabled: Bool,
        force: Bool = false,
        reload: @escaping @MainActor () async -> String?
    ) async -> Outcome {
        guard Self.isGeneration(generation) else { return .failed("Invalid generation") }
        guard enabled else { return .disabled }

        if let active {
            if active.generation == generation {
                return await active.task.value
            }
            _ = await active.task.value
            return await activate(generation: generation, enabled: enabled, force: force, reload: reload)
        }

        if !force, readAcknowledged() == generation { return .current }
        if !force, let previous = automaticFailures[generation] { return previous }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            let outcome: Outcome
            switch await reload() {
            case "": outcome = .reloaded
            case let error?: outcome = .failed(error)
            case nil: outcome = .timedOut
            }
            self?.complete(id: id, generation: generation, outcome: outcome)
            return outcome
        }
        active = Active(id: id, generation: generation, task: task)
        return await task.value
    }

    private func complete(id: UUID, generation: String, outcome: Outcome) {
        guard active?.id == id else { return }
        active = nil
        switch outcome {
        case .reloaded:
            writeAcknowledged(generation)
            automaticFailures.removeValue(forKey: generation)
        case .failed, .timedOut:
            automaticFailures[generation] = outcome
        case .current, .disabled:
            break
        }
    }

    private static func isGeneration(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}
