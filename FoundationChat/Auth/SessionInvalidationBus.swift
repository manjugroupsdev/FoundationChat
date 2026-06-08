import Foundation

extension Notification.Name {
    static let didInvalidateSession = Notification.Name("didInvalidateSession")
}

enum SessionInvalidationBus {
    static func emit(reason: String = "Session expired. Please sign in again.") {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .didInvalidateSession, object: reason)
        }
    }
}
