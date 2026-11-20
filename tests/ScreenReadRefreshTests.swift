import Foundation

@main struct ScreenReadRefreshTests {
    actor SleepGate {
        private(set) var count = 0
        private var continuation: CheckedContinuation<Void, Error>?
        func sleep() async throws {
            count += 1
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func waitForCount(_ expected: Int) async {
            while count < expected { await Task.yield() }
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    @MainActor static func main() async throws {
        for selected in [false, true] {
            for visible in [false, true] {
                for foreground in [false, true] {
                    for form in [false, true] {
                        precondition(ScreenReadRefreshPolicy.canRefresh(
                            isSelected: selected, isVisible: visible, isForeground: foreground, isFormPresented: form
                        ) == (selected && visible && foreground && !form))
                    }
                }
            }
        }
        let sleep = SleepGate()
        let refresh = SleepGate()
        var calls = 0
        let poll = Task { @MainActor in
            await ScreenReadRefreshPolicy.poll(every: 60, sleep: { _ in try await sleep.sleep() }) {
                calls += 1
                try? await refresh.sleep()
            }
        }
        await sleep.waitForCount(1)
        precondition(calls == 0, "No extra initial request from periodic polling")
        await sleep.release()
        await refresh.waitForCount(1)
        precondition(calls == 1)
        let sleepCount = await sleep.count
        precondition(sleepCount == 1, "A slow response cannot schedule an overlapping refresh")
        await refresh.release()
        await sleep.waitForCount(2)
        poll.cancel()
        await sleep.release()
        await poll.value
        precondition(calls == 1, "A cancelled hidden/background screen cannot make another request")
        print("Screen read visibility, completion scheduling and cancellation: passed")
    }
}
