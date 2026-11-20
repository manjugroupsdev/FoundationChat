import Foundation

enum ScreenReadRefreshPolicy {
    nonisolated static func canRefresh(
        isSelected: Bool, isVisible: Bool, isForeground: Bool, isFormPresented: Bool = false
    ) -> Bool {
        isSelected && isVisible && isForeground && !isFormPresented
    }

    /// Schedule from completion, not a timer that can queue overlapping reads.
    @MainActor static func poll(
        every interval: UInt64,
        sleep: @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        refresh: @MainActor () async -> Void
    ) async {
        while !Task.isCancelled {
            do {
                try await sleep(interval)
                try Task.checkCancellation()
            } catch { return }
            await refresh()
        }
    }
}
