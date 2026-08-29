import Foundation
import UIKit
import Security

/// Thin HTTP client for the Convex auth endpoints.
enum AuthAPIService {
  private static let baseURL = AppConfig.baseURL

  // MARK: - Response types

  private struct SendOTPResponse: Decodable {
    let success: Bool
    let message: String?
    let error: String?
  }

  private struct VerifyOTPResponse: Decodable {
    let success: Bool
    let token: String?
    let user: AuthUser?
    let error: String?
  }

  private struct TravelDeskAuthUser: Decodable {
    let _id: String?
    let name: String?
    let phone: String?
    let role: String?
  }

  private struct TravelDeskVerifyOTPResponse: Decodable {
    let success: Bool
    let token: String?
    let user: TravelDeskAuthUser?
    let error: String?
  }

  private struct EmployeePasswordLoginResponse: Decodable {
    let success: Bool
    let token: String?
    let user: AuthUser?
    let mustChangePassword: Bool?
    let error: String?
    let message: String?
  }

  private struct SimpleResponse: Decodable {
    let success: Bool
    let message: String?
    let error: String?
  }

  private struct ValidateSessionResponse: Decodable {
    let success: Bool
    let user: AuthUser?
    let error: String?
  }

  private struct MyIAMPermissionsResponse: Decodable {
    let success: Bool?
    let total: Int?
    let permissions: [String]
    let role: String?
    let isAdmin: Bool
    let error: String?
  }

  private struct LogoutResponse: Decodable {
    let success: Bool
    let message: String?
    let error: String?
  }

  // MARK: - Public API

  /// Send an OTP to the given 10-digit phone number.
  static func sendOTP(phone: String) async throws {
    let url = URL(string: "\(baseURL)/api/auth/send-otp")!
    let body: [String: String] = ["phone": phone]

    let (data, response) = try await post(url: url, body: body)
    let decoded = try JSONDecoder().decode(SendOTPResponse.self, from: data)

    guard decoded.success else {
      throw AuthAPIError.server(
        decoded.error ?? decoded.message ?? "Failed to send OTP",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }
  }

  /// Agency-created drivers are not present in staff auth. Android falls back
  /// to this route only after the staff endpoint reports an unknown phone.
  static func sendTravelDeskOTP(phone: String) async throws {
    let url = URL(string: "\(baseURL)/api/travel-desk/auth/send-otp")!
    let (data, response) = try await post(url: url, body: ["phone": phone])
    let decoded = try JSONDecoder().decode(SendOTPResponse.self, from: data)
    guard decoded.success else {
      throw AuthAPIError.server(
        decoded.error ?? decoded.message ?? "Phone number not registered. Contact admin.",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }
  }

  /// Verify the OTP and return the session (token + user).
  static func verifyOTP(phone: String, otp: String) async throws -> OtpSession {
    let url = URL(string: "\(baseURL)/api/auth/verify-otp")!
    var body: [String: Any] = ["phone": phone, "otp": otp]

    // Device-binding telemetry: lets the backend lock a staff account to one
    // mobile device. All fields are optional — when `deviceId` can't be read
    // we send none and the backend treats their absence as a grace path.
    if let device = LoginDeviceInfo.capture() {
      body["deviceId"] = device.deviceId
      body["devicePlatform"] = device.platform
      body["deviceModel"] = device.model
      if let batteryPct = device.batteryPct {
        body["batteryPct"] = batteryPct
      }
    }

    let (data, response) = try await post(url: url, jsonBody: body)
    let decoded = try JSONDecoder().decode(VerifyOTPResponse.self, from: data)

    guard decoded.success, let token = decoded.token, let user = decoded.user else {
      throw AuthAPIError.server(
        decoded.error ?? "Verification failed",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }

    return OtpSession(token: token, user: user)
  }

  static func verifyTravelDeskOTP(phone: String, otp: String) async throws -> OtpSession {
    let url = URL(string: "\(baseURL)/api/travel-desk/auth/verify-otp")!
    let (data, response) = try await post(url: url, body: ["phone": phone, "otp": otp])
    let decoded = try JSONDecoder().decode(TravelDeskVerifyOTPResponse.self, from: data)
    guard decoded.success, let token = decoded.token, let remoteUser = decoded.user else {
      throw AuthAPIError.server(
        decoded.error ?? "Verification failed",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }

    let role = remoteUser.role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard role == "driver" || role == "agency_staff" else {
      throw AuthAPIError.server(
        "External fleet agencies sign in on the travel-desk web, not the app.",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }
    let isAgencyStaff = role == "agency_staff"
    let user = AuthUser(
      _id: remoteUser._id ?? "travel-desk:\(phone)",
      staffId: remoteUser._id,
      name: remoteUser.name,
      phone: remoteUser.phone ?? phone,
      role: isAgencyStaff ? "agency_staff" : "external_fleet_driver",
      designation: isAgencyStaff ? "External Fleet Staff" : "External Fleet Driver",
      department: "Fleet",
      status: "active"
    )
    return OtpSession(token: token, user: user)
  }

  /// Login with Employee ID + password. Mirrors Android
  /// `POST /api/auth/login-with-employee-id`.
  static func loginWithEmployeeId(employeeId: String, password: String) async throws -> OtpSession {
    let url = URL(string: "\(baseURL)/api/auth/login-with-employee-id")!
    var body: [String: Any] = ["employeeId": employeeId, "password": password]

    // Device-binding telemetry: the password login is locked to the same device
    // as the OTP login. Omitted when a device id can't be read (grace path).
    if let device = LoginDeviceInfo.capture() {
      body["deviceId"] = device.deviceId
      body["devicePlatform"] = device.platform
      body["deviceModel"] = device.model
      if let batteryPct = device.batteryPct {
        body["batteryPct"] = batteryPct
      }
    }

    let (data, response) = try await post(url: url, jsonBody: body)
    let decoded = try JSONDecoder().decode(EmployeePasswordLoginResponse.self, from: data)

    guard decoded.success, let token = decoded.token, let user = decoded.user else {
      throw AuthAPIError.server(
        decoded.error ?? decoded.message ?? "Login failed",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }

    let mustChangePassword = decoded.mustChangePassword == true || user.mustChangePassword == true
    return OtpSession(token: token, user: user, mustChangePassword: mustChangePassword)
  }

  /// Change the signed-in user's password. Used by the forced password-change
  /// flow after Employee ID login.
  static func changeOwnPassword(
    token: String,
    currentPassword: String?,
    newPassword: String
  ) async throws {
    let url = URL(string: "\(baseURL)/api/auth/change-own-password")!
    var body: [String: Any] = ["newPassword": newPassword]
    if let currentPassword, !currentPassword.isEmpty {
      body["currentPassword"] = currentPassword
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    if (response as? HTTPURLResponse)?.statusCode == 401 {
      SessionInvalidationBus.emit()
    }
    let decoded = try JSONDecoder().decode(SimpleResponse.self, from: data)
    guard decoded.success else {
      throw AuthAPIError.server(
        decoded.error ?? decoded.message ?? "Failed to change password",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }
  }

  /// Validate an existing session token and return the current user.
  static func validateSession(token: String) async throws -> AuthUser {
    let url = URL(string: "\(baseURL)/api/auth/validate-session")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    if (response as? HTTPURLResponse)?.statusCode == 401 {
      SessionInvalidationBus.emit()
    }
    let decoded = try JSONDecoder().decode(ValidateSessionResponse.self, from: data)

    guard decoded.success, let user = decoded.user else {
      throw AuthAPIError.sessionInvalid(decoded.error ?? "Invalid or expired session")
    }

    return user
  }

  /// Fetch the signed-in user's IAM permissions. Mirrors Android
  /// `GET /api/iam/my-permissions` used by App Library feature gates.
  static func getMyIAMPermissions(token: String) async throws -> (permissions: [String], role: String?, isAdmin: Bool) {
    let url = URL(string: "\(baseURL)/api/iam/my-permissions")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    if (response as? HTTPURLResponse)?.statusCode == 401 {
      SessionInvalidationBus.emit()
    }
    let decoded = try JSONDecoder().decode(MyIAMPermissionsResponse.self, from: data)

    if decoded.success == false {
      throw AuthAPIError.server(
        decoded.error ?? "Failed to load permissions",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }

    return (decoded.permissions, decoded.role, decoded.isAdmin)
  }

  /// Logout / invalidate the session on the server.
  static func logout(token: String) async throws {
    let url = URL(string: "\(baseURL)/api/auth/logout")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (_, _) = try await URLSession.shared.data(for: request)
    // Best-effort logout — ignore errors.
  }

  static func logoutTravelDesk(token: String) async throws {
    let url = URL(string: "\(baseURL)/api/travel-desk/auth/logout")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{}".utf8)
    _ = try await URLSession.shared.data(for: request)
  }

  static func registerTravelDeskPushToken(token: String, deviceToken: String) async throws {
    let url = URL(string: "\(baseURL)/api/travel-desk/push/register")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "pushToken": deviceToken,
      "platform": "ios",
    ])
    let (data, response) = try await URLSession.shared.data(for: request)
    let decoded = try JSONDecoder().decode(SimpleResponse.self, from: data)
    guard decoded.success else {
      throw AuthAPIError.server(
        decoded.error ?? decoded.message ?? "Push registration failed",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }
  }

  // MARK: - Helpers

  private static func post(url: URL, body: [String: String]) async throws -> (Data, URLResponse) {
    try await post(url: url, jsonBody: body)
  }

  private static func post(url: URL, jsonBody: [String: Any]) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
    return try await URLSession.shared.data(for: request)
  }
}

// MARK: - Device-binding telemetry

/// Snapshot of the current device used to bind a staff account to a single
/// phone on OTP login. Mirrors the Android + backend `verify-otp` device fields.
struct LoginDeviceInfo {
  let deviceId: String
  let platform: String
  let model: String
  let batteryPct: Int?

  /// Captures the current device info, or `nil` when a stable device id can't
  /// be read (caller then omits all device fields — backend grace path).
  static func capture() -> LoginDeviceInfo? {
    guard let deviceId = persistentDeviceId() else { return nil }
    return LoginDeviceInfo(
      deviceId: deviceId,
      platform: "ios",
      model: modelName(),
      batteryPct: batteryPercent()
    )
  }

  // Keychain slot for the persisted device id.
  private static let keychainService = "com.manjugroups.foundationchat.deviceBinding"
  private static let keychainAccount = "device-id"

  /// A device id that survives app REINSTALLS: a UUID persisted in the Keychain
  /// (the Keychain is not wiped when an app is deleted, only on factory reset).
  /// Seeded from `identifierForVendor` on first run so the value is identical to
  /// what we'd have sent before — no re-binding. This is more stable than
  /// identifierForVendor alone, which resets once every app from the vendor is
  /// removed. Stored `…ThisDeviceOnly`, so it never syncs via iCloud Keychain
  /// and is not migrated to a new phone on a backup restore — it stays bound to
  /// this physical device. Still clears on factory reset (the intended "new
  /// device" boundary; admins reset the lock for legitimate device swaps).
  static func persistentDeviceId() -> String? {
    if let existing = keychainReadDeviceId() { return existing }
    let seed = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    keychainWriteDeviceId(seed)
    // Prefer the stored value (confirms persistence); fall back to the seed.
    return keychainReadDeviceId() ?? seed
  }

  private static func keychainReadDeviceId() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data,
          let value = String(data: data, encoding: .utf8),
          !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func keychainWriteDeviceId(_ value: String) {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
    ]
    SecItemDelete(base as CFDictionary)
    var add = base
    add[kSecValueData as String] = Data(value.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(add as CFDictionary, nil)
  }

  /// Hardware model identifier (e.g. "iPhone15,2"), falling back to the
  /// generic `UIDevice` model name.
  private static func modelName() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
      let bytes = raw.prefix { $0 != 0 }
      return String(decoding: bytes, as: UTF8.self)
    }
    return machine.isEmpty ? UIDevice.current.model : machine
  }

  /// Battery percentage 0–100, or `nil` when the level is unavailable.
  private static func batteryPercent() -> Int? {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = UIDevice.current.batteryLevel
    guard level >= 0 else { return nil }
    return Int((level * 100).rounded())
  }
}

// MARK: - Errors

enum AuthAPIError: LocalizedError {
  case server(String, statusCode: Int)
  case sessionInvalid(String)

  var errorDescription: String? {
    switch self {
    case .server(let msg, _): return msg
    case .sessionInvalid(let msg): return msg
    }
  }
}
