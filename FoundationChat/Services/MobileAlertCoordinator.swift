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

    /// Server lookups per refresh for alerts that may have been deleted.
    private static let deletedLookupLimit = 10

    /// The alert on screen, nil when none is pending.
    private(set) var current: MobileAlert?
    var openError: String?
    @ObservationIgnored var pendingOpenDeliveryId: String?

    @ObservationIgnored private var queue: [MobileAlert] = []
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var acknowledging: Set<String> = []
    @ObservationIgnored private var retryingAcknowledgements = false
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
            Task { await retryAcknowledgements(token: activeToken) }
            do {
                let pending = try await MobileAlertAPIService.fetchPending(token: activeToken)
                // Signed out or switched user while the request was out.
                guard token == activeToken else { continue }
                apply(pending)
                await clearDeleted(pending: pending, token: activeToken)
            } catch {
                // Keep whatever is queued; the next refresh tries again.
                print("[mobile-alert] pending fetch failed: \(error.localizedDescription)")
            }
            if let deliveryId = pendingOpenDeliveryId, let activeToken = token {
                pendingOpenDeliveryId = nil
                await reopen(deliveryId: deliveryId, token: activeToken)
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

    func reopen(deliveryId: String, token activeToken: String) async {
        do {
            let alert = try await MobileAlertAPIService.fetchDetail(token: activeToken, deliveryId: deliveryId)
            guard token == activeToken else { return }
            if let previous = current, previous.id != alert.id, !viewedIds.contains(previous.id) {
                queue.insert(previous, at: 0)
            }
            queue.removeAll { $0.id == alert.id }
            current = alert
        } catch {
            guard token == activeToken else { return }
            openError = error.localizedDescription
        }
    }

    /// Inbox viewing uses its own cover rather than competing with the root cover.
    func recordViewed(_ alert: MobileAlert, token activeToken: String) {
        guard token == activeToken else { return }
        rememberViewed(alert.id)
        queue.removeAll { $0.id == alert.id }
        Task { await acknowledge(alert.id, token: activeToken) }
    }

    // MARK: - Queue

    private func reset() {
        token = nil
        queue = []
        current = nil
        openError = nil
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

    // MARK: - Deleted on the web

    /// Alerts deleted on the web leave the pending list. iOS gets no withdraw
    /// push (APNs would show it as a banner), so on refresh: delivered alert
    /// notifications and the alert on screen that are no longer pending are
    /// checked with the server and removed only when it says the alert is
    /// gone (404). A viewed alert that still exists keeps its notification.
    private func clearDeleted(pending: [MobileAlert], token activeToken: String) async {
        let pendingIds = Set(pending.map(\.deliveryId))
        let delivered = await Self.deliveredAlertNotifications()
            .filter { !pendingIds.contains($0.deliveryId) }
        var candidates: [String] = []
        if let onScreen = current?.deliveryId, !pendingIds.contains(onScreen) {
            candidates.append(onScreen)
        }
        for item in delivered where !candidates.contains(item.deliveryId) {
            candidates.append(item.deliveryId)
        }
        guard !candidates.isEmpty else { return }

        var gone: Set<String> = []
        for deliveryId in candidates.prefix(Self.deletedLookupLimit) {
            guard token == activeToken else { return }
            do {
                _ = try await MobileAlertAPIService.fetchDetail(token: activeToken, deliveryId: deliveryId)
            } catch let error as MobileAlertAPIError {
                if case .rejected(let status, _) = error, status == 404 { gone.insert(deliveryId) }
            } catch {
                // Offline or a server error: check again on the next refresh.
            }
        }
        guard token == activeToken, !gone.isEmpty else { return }

        let identifiers = delivered.filter { gone.contains($0.deliveryId) }.map { $0.identifier }
        if !identifiers.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
        queue.removeAll { gone.contains($0.deliveryId) }
        if let onScreen = current?.deliveryId, gone.contains(onScreen) {
            current = queue.isEmpty ? nil : queue.removeFirst()
            openError = "This alert was removed"
        }
    }

    /// Delivered `mobile_alert` notifications, as (delivery id, request id).
    private nonisolated static func deliveredAlertNotifications() async -> [(deliveryId: String, identifier: String)] {
        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        return notifications.compactMap { notification in
            let info = notification.request.content.userInfo
            guard (info["type"] as? String) == "mobile_alert",
                  let deliveryId = info["alertDeliveryId"] as? String, !deliveryId.isEmpty else { return nil }
            return (deliveryId: deliveryId, identifier: notification.request.identifier)
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
        guard !retryingAcknowledgements else { return }
        retryingAcknowledgements = true
        defer { retryingAcknowledgements = false }
        for deliveryId in unacknowledgedIds.sorted() {
            guard self.token == token else { return }
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

}
