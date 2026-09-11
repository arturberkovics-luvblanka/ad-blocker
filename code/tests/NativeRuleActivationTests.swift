import Foundation

@MainActor
final class ReloadGate {
    private var entered = false
    private var releaseRequested = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func enterAndWait() async {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        guard !releaseRequested else { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func release() {
        releaseRequested = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@main
struct NativeRuleActivationTests {
    static let old = String(repeating: "a", count: 64)
    static let new = String(repeating: "b", count: 64)

    @MainActor
    static func main() async {
        await currentAndDisabled()
        await sameGenerationDeduplicates()
        await differentGenerationsSerialize()
        await failureTimeoutAndForce()
    }

    @MainActor
    static func currentAndDisabled() async {
        var acknowledged = old
        var writes: [String] = []
        var reloads = 0
        let activation = NativeRuleActivation(readAcknowledged: { acknowledged }, writeAcknowledged: { writes.append($0); acknowledged = $0 })

        let current = await activation.activate(generation: old, enabled: true) { reloads += 1; return "" }
        let disabled = await activation.activate(generation: new, enabled: false) { reloads += 1; return "" }
        let invalid = await activation.activate(generation: "bad", enabled: true) { reloads += 1; return "" }
        precondition(current == .current && disabled == .disabled && invalid == .failed("Invalid generation"))
        precondition(reloads == 0 && writes.isEmpty)
        print("PASS: current, disabled, and invalid generations avoid reload and acknowledgement writes")
    }

    @MainActor
    static func sameGenerationDeduplicates() async {
        var writes: [String] = []
        var reloads = 0
        var secondStarted = false
        let gate = ReloadGate()
        let activation = NativeRuleActivation(readAcknowledged: { nil }, writeAcknowledged: { writes.append($0) })
        let first = Task { @MainActor in await activation.activate(generation: new, enabled: true) {
            reloads += 1
            await gate.enterAndWait()
            return ""
        } }
        await gate.waitUntilEntered()
        let second = Task { @MainActor in
            secondStarted = true
            return await activation.activate(generation: new, enabled: true) {
                reloads += 100
                return ""
            }
        }
        while !secondStarted { await Task.yield() }
        precondition(reloads == 1 && writes.isEmpty)
        gate.release()
        let outcomes = await (first.value, second.value)
        precondition(outcomes.0 == .reloaded && outcomes.1 == .reloaded)
        precondition(writes == [new])
        print("PASS: concurrent same-generation calls share one reload")
    }

    @MainActor
    static func differentGenerationsSerialize() async {
        var writes: [String] = []
        var events: [String] = []
        var secondStarted = false
        let gate = ReloadGate()
        let activation = NativeRuleActivation(readAcknowledged: { nil }, writeAcknowledged: { writes.append($0) })
        let first = Task { @MainActor in await activation.activate(generation: old, enabled: true) {
            events.append("old-start")
            await gate.enterAndWait()
            events.append("old-end")
            return ""
        } }
        await gate.waitUntilEntered()
        let second = Task { @MainActor in
            secondStarted = true
            return await activation.activate(generation: new, enabled: true) {
                events.append("new")
                return ""
            }
        }
        while !secondStarted { await Task.yield() }
        precondition(events == ["old-start"] && writes.isEmpty)
        gate.release()
        let outcomes = await (first.value, second.value)
        precondition(outcomes.0 == .reloaded && outcomes.1 == .reloaded)
        precondition(events == ["old-start", "old-end", "new"] && writes == [old, new])
        print("PASS: different generations serialize and acknowledge in completion order")
    }

    @MainActor
    static func failureTimeoutAndForce() async {
        var acknowledged = old
        var writes: [String] = []
        var attempts = 0
        let activation = NativeRuleActivation(readAcknowledged: { acknowledged }, writeAcknowledged: { writes.append($0); acknowledged = $0 })

        let failed = await activation.activate(generation: new, enabled: true) { attempts += 1; return "metadata unavailable" }
        let retainedFailure = await activation.activate(generation: new, enabled: true) { attempts += 100; return "" }
        precondition(failed == .failed("metadata unavailable") && retainedFailure == failed)
        precondition(acknowledged == old && writes.isEmpty && attempts == 1)

        let forced = await activation.activate(generation: new, enabled: true, force: true) { attempts += 1; return "" }
        precondition(forced == .reloaded && acknowledged == new && writes == [new] && attempts == 2)

        let timeoutGeneration = String(repeating: "c", count: 64)
        let timedOut = await activation.activate(generation: timeoutGeneration, enabled: true) { attempts += 1; return nil }
        let retainedTimeout = await activation.activate(generation: timeoutGeneration, enabled: true) { attempts += 100; return "" }
        precondition(timedOut == .timedOut && retainedTimeout == .timedOut && attempts == 3)
        precondition(acknowledged == new && writes == [new])
        print("PASS: failure and timeout retain the old acknowledgement; force retries once")
    }
}
