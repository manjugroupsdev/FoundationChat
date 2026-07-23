import Observation
import SwiftUI

/// Tracks create/edit flows that should not be interrupted by app-wide nudges.
@MainActor
@Observable
final class AppFormActivityStore {
    static let shared = AppFormActivityStore()

    private var activeSessions: Set<UUID> = []

    var isFormActive: Bool {
        !activeSessions.isEmpty
    }

    private init() {}

    func begin(_ sessionID: UUID) {
        activeSessions.insert(sessionID)
    }

    func end(_ sessionID: UUID) {
        activeSessions.remove(sessionID)
    }
}

private struct AppFormActivityModifier: ViewModifier {
    @State private var sessionID = UUID()
    @State private var isRegistered = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isRegistered else { return }
                isRegistered = true
                AppFormActivityStore.shared.begin(sessionID)
            }
            .onDisappear {
                guard isRegistered else { return }
                isRegistered = false
                AppFormActivityStore.shared.end(sessionID)
            }
    }
}

extension View {
    /// Marks this view as an active create/edit form for global presentation rules.
    func appFormActivity() -> some View {
        modifier(AppFormActivityModifier())
    }
}
