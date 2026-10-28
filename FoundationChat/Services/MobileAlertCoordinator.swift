import Foundation
import Observation
import UserNotifications

/// Queue of mandatory mobile alerts for the signed-in staff member.
///
/// `refresh(token:)` pulls the pending list (app active, sign-in, a
/// `mobile_alert` push). Closing an alert records it locally FIRST, so an
/// alert closed offline never shows again, then acknowledges it to the
/// server; unacknowledged closes are retried on every refresh.
@MainActor
@Observable
final class MobileAlertCoordinator {
    static let shared = MobileAlertCoordinator()

    private enum DefaultsKey {
        static let viewedIds = "mobileAlert.viewedDeliveryIds"
        static let unacknowledgedIds = "mobileAlert.unacknowledgedDeliveryIds"
    }

    /// Newest viewed IDs kept locally; older ones are long gone from the
    /// server's pending list.
    private static let viewedIdsLimit = 500

    /// The alert on screen, nil when none is pending.
    private(set) var current: MobileAlert?

    @ObservationIgnored private var queue: [MobileAlert] = []
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var acknowledging: Set<String> = []
    @ObservationIgnored private var viewedIds: [String]
    @ObservationIgnored private var unacknowledgedIds: Set<String>
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        viewedIds = defaults.stringArray(forKey: DefaultsKey.viewedIds) ?? []
        unacknowledgedIds = Set(defaults.stringArray(forKey: DefaultsKey.unacknowledgedIds) ?? [])
    }

    /// Pass nil when signed out: the queue is dropped and nothing is fetched.
    func refresh(token newToken: String?) async {
        guard let newToken, !newToken.isEmpty else {
            reset()
            return
        }
        if token != newToken {
            // A different session: nothing queued for the old one carries over.
            queue = []
            current = nil
            token = newToken
        }
        // A refresh already in flight runs once more instead of overlapping.
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshAgain = false
            guard let activeToken = token else { return }
            await retryAcknowledgements(token: activeToken)
            do {
                let pending = try await MobileAlertAPIService.fetchPending(token: activeToken)
                // Signed out or switched user while the request was out.
                guard token == activeToken else { continue }
                apply(pending)
            } catch {
                // Keep whatever is queued; the next refresh tries again.
                print("[mobile-alert] pending fetch failed: \(error.localizedDescription)")
            }
        } while refreshAgain
    }

    /// Close tapped on `alert`: remember it, show the next one, acknowledge.
    func close(_ alert: MobileAlert) {
        guard current?.deliveryId == alert.deliveryId else { return }
        rememberViewed(alert.deliveryId)
        current = queue.isEmpty ? nil : queue.removeFirst()
        guard let token else { return }
        Task { await acknowledge(alert.deliveryId, token: token) }
    }

    // MARK: - Queue

    private func reset() {
        token = nil
        queue = []
        current = nil
    }

    private func apply(_ pending: [MobileAlert]) {
        let viewed = Set(viewedIds)
        queue = pending.filter {
            !viewed.contains($0.deliveryId) && $0.deliveryId != current?.deliveryId
        }
        if current == nil, !queue.isEmpty {
            current = queue.removeFirst()
        }
    }

    // MARK: - Acknowledgement

    private func rememberViewed(_ deliveryId: String) {
        viewedIds.removeAll { $0 == deliveryId }
        viewedIds.append(deliveryId)
        if viewedIds.count > Self.viewedIdsLimit {
            viewedIds.removeFirst(viewedIds.count - Self.viewedIdsLimit)
        }
        unacknowledgedIds.insert(deliveryId)
        persist()
    }

    private func retryAcknowledgements(token: String) async {
        for deliveryId in unacknowledgedIds.sorted() {
            await acknowledge(deliveryId, token: token)
        }
    }

    private func acknowledge(_ deliveryId: String, token: String) async {
        guard !acknowledging.contains(deliveryId) else { return }
        acknowledging.insert(deliveryId)
        defer { acknowledging.remove(deliveryId) }
        do {
            try await MobileAlertAPIService.markViewed(token: token, deliveryId: deliveryId)
            unacknowledgedIds.remove(deliveryId)
            persist()
            Self.removeDeliveredNotifications(forDeliveryId: deliveryId)
        } catch let error as MobileAlertAPIError where error.isPermanent {
            // The server will never accept it (e.g. it belongs to a user who
            // has since signed out of this phone); stop retrying.
            print("[mobile-alert] viewed rejected id=\(deliveryId): \(error.localizedDescription)")
            unacknowledgedIds.remove(deliveryId)
            persist()
        } catch {
            print("[mobile-alert] viewed failed id=\(deliveryId), will retry: \(error.localizedDescription)")
        }
    }

    private func persist() {
        defaults.set(viewedIds, forKey: DefaultsKey.viewedIds)
        defaults.set(unacknowledgedIds.sorted(), forKey: DefaultsKey.unacknowledgedIds)
    }

    /// iOS can't make the push itself non-dismissible, so it sits in
    /// Notification Center until cleared; drop it once the alert is viewed.
    private nonisolated static func removeDeliveredNotifications(forDeliveryId deliveryId: String) {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let identifiers = notifications
                .filter { ($0.request.content.userInfo["alertDeliveryId"] as? String) == deliveryId }
                .map { $0.request.identifier }
            guard !identifiers.isEmpty else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }
}
