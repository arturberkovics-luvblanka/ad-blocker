import Foundation

@main
struct SafariRequestTests {
    @MainActor
    static func main() async {
        let immediate: String? = await safariRequest(timeout: .seconds(1)) { done in done("ok") }
        precondition(immediate == "ok")
        print("PASS: immediate completion")

        let missing: String? = await safariRequest(timeout: .milliseconds(20)) { _ in }
        precondition(missing == nil)
        print("PASS: missing callback times out")

        let late: String? = await safariRequest(timeout: .milliseconds(10)) { done in
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                done("late")
            }
        }
        precondition(late == nil)
        try? await Task.sleep(for: .milliseconds(100))
        print("PASS: late callback does not resume twice")

        let duplicate: String? = await safariRequest(timeout: .seconds(1)) { done in
            done("first")
            done("second")
        }
        precondition(duplicate == "first" || duplicate == "second")
        try? await Task.sleep(for: .milliseconds(20))
        print("PASS: duplicate callbacks resolve only once")
    }
}
