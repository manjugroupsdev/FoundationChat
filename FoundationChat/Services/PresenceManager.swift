import Foundation
import SwiftUI

@MainActor
@Observable
final class PresenceManager {
    private var heartbeatTask: Task<Void, Never>?
    private var authStore: AuthStore?

    func start(authStore: AuthStore) {
        self.authStore = authStore
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                do {
                    try await authStore.sendPresenceHeartbeat()
                } catch {}
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if let authStore {
            Task {
                try? await authStore.setPresenceStatus(status: .offline)
            }
        }
    }

    func setAway() {
        guard let authStore else { return }
        Task {
            try? await authStore.setPresenceStatus(status: .away)
        }
    }

    func setOnline() {
        guard let authStore else { return }
        Task {
            try? await authStore.setPresenceStatus(status: .online)
        }
    }
}
