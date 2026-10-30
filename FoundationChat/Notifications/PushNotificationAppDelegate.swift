import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
  static let didRegisterForRemoteNotificationsToken = Notification.Name(
    "didRegisterForRemoteNotificationsToken"
  )
  static let didReceivePushNavigationRoute = Notification.Name(
    "didReceivePushNavigationRoute"
  )
  static let didReceiveGeoTrackSyncPush = Notification.Name(
    "didReceiveGeoTrackSyncPush"
  )
  static let didReceiveMobileAlertPush = Notification.Name(
    "didReceiveMobileAlertPush"
  )
}

final class PushNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  private let logPrefix = "[push-ios]"

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    ModernDialerCallKitCoordinator.shared.start()
    print("\(logPrefix) app launched, UNUserNotificationCenter delegate set")

    // Relaunched by iOS for a location event (monitoring left on by an earlier
    // run): resume only an active shift, otherwise switch it off.
    if launchOptions?[.location] != nil {
      Task { @MainActor in
        await GeoTrackBootstrapCoordinator.shared.handleLocationRelaunch()
      }
    }

    if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      handleGeoTrackSyncIfNeeded(from: remoteNotification, source: "launchOptions")
      handleMobileAlertIfNeeded(from: remoteNotification, source: "launchOptions")
      handleNotificationRoute(from: remoteNotification, source: "launchOptions")
    }
    return true
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    print("\(logPrefix) didRegisterForRemoteNotifications token=\(token.prefix(12))...")
    NotificationCenter.default.post(
      name: .didRegisterForRemoteNotificationsToken,
      object: token
    )
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: any Error
  ) {
    print("\(logPrefix) APNs registration failed: \(error.localizedDescription)")
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    print("\(logPrefix) foreground push received")
    if ModernDialerCallKitCoordinator.shared.handleFallbackRemoteNotification(notification.request.content.userInfo) {
      return []
    }
    handleGeoTrackSyncIfNeeded(from: notification.request.content.userInfo, source: "foreground")
    // A mobile alert still shows its banner; the full-screen alert follows.
    handleMobileAlertIfNeeded(from: notification.request.content.userInfo, source: "foreground")
    return [.banner, .sound, .badge]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    handleGeoTrackSyncIfNeeded(from: response.notification.request.content.userInfo, source: "tap")
    handleMobileAlertIfNeeded(from: response.notification.request.content.userInfo, source: "tap")
    handleNotificationRoute(from: response.notification.request.content.userInfo, source: "tap")
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if ModernDialerCallKitCoordinator.shared.handleFallbackRemoteNotification(userInfo) {
      completionHandler(.newData)
      return
    }
    let isGeoTrackSync = handleGeoTrackSyncIfNeeded(from: userInfo, source: "background")
    let isMobileAlert = handleMobileAlertIfNeeded(from: userInfo, source: "background")
    completionHandler(isGeoTrackSync || isMobileAlert ? .newData : .noData)
  }

  @discardableResult
  private func handleGeoTrackSyncIfNeeded(from userInfo: [AnyHashable: Any], source: String) -> Bool {
    guard let rawType = pushString(userInfo["type"]),
          rawType == "geotrack_sync" else {
      return false
    }
    print("\(logPrefix) geotrack sync push source=\(source)")
    NotificationCenter.default.post(
      name: .didReceiveGeoTrackSyncPush,
      object: pushString(userInfo["reason"]) ?? source
    )
    return true
  }

  /// A mandatory mobile alert: the app root refreshes the pending queue,
  /// which presents the full-screen alert.
  @discardableResult
  private func handleMobileAlertIfNeeded(from userInfo: [AnyHashable: Any], source: String) -> Bool {
    guard pushString(userInfo["type"]) == "mobile_alert" else {
      return false
    }
    print("\(logPrefix) mobile alert push source=\(source) delivery=\(pushString(userInfo["alertDeliveryId"]) ?? "-")")
    let deliveryId = pushString(userInfo["alertDeliveryId"])
    let reopen = source == "tap" || source == "launchOptions"
    Task { @MainActor in
      if reopen { MobileAlertCoordinator.shared.pendingOpenDeliveryId = deliveryId }
      NotificationCenter.default.post(name: .didReceiveMobileAlertPush, object: deliveryId)
    }
    return true
  }

  private func handleNotificationRoute(from userInfo: [AnyHashable: Any], source: String) {
    guard let route = PushNavigationRoute(userInfo) else {
      return
    }
    print("\(logPrefix) push route parsed source=\(source) type=\(route.type.rawValue)")
    Task { @MainActor in
      PushNavigationCoordinator.shared.enqueue(route)
    }
  }

  private func pushString(_ value: Any?) -> String? {
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
  }
}
