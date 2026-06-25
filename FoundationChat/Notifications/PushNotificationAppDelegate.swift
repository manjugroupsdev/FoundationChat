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
}

final class PushNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  private let logPrefix = "[push-ios]"

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    print("\(logPrefix) app launched, UNUserNotificationCenter delegate set")

    if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      handleGeoTrackSyncIfNeeded(from: remoteNotification, source: "launchOptions")
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
    handleGeoTrackSyncIfNeeded(from: notification.request.content.userInfo, source: "foreground")
    return [.banner, .sound, .badge]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    handleGeoTrackSyncIfNeeded(from: response.notification.request.content.userInfo, source: "tap")
    handleNotificationRoute(from: response.notification.request.content.userInfo, source: "tap")
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if handleGeoTrackSyncIfNeeded(from: userInfo, source: "background") {
      completionHandler(.newData)
    } else {
      completionHandler(.noData)
    }
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
