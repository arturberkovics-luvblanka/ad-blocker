import Foundation

// Some Safari callbacks may never arrive. Resolve once, including after timeout.
@MainActor
private final class SafariReply<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Value?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}

@MainActor
func safariRequest<Value: Sendable>(
    timeout: Duration,
    start: (@escaping @Sendable (Value) -> Void) -> Void
) async -> Value? {
    await withCheckedContinuation { continuation in
        let reply = SafariReply(continuation)
        let timer = Task { @MainActor in
            do { try await Task.sleep(for: timeout) }
            catch { return }
            reply.finish(nil)
        }
        start { value in
            Task { @MainActor in
                reply.finish(value)
                timer.cancel()
            }
        }
    }
}
