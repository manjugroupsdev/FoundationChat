import Foundation

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

  private struct ValidateSessionResponse: Decodable {
    let success: Bool
    let user: AuthUser?
    let error: String?
  }

  private struct MyIAMPermissionsResponse: Decodable {
    let success: Bool?
    let total: Int?
    let permissions: [String]
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
        decoded.error ?? "Failed to send OTP",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }
  }

  /// Verify the OTP and return the session (token + user).
  static func verifyOTP(phone: String, otp: String) async throws -> OtpSession {
    let url = URL(string: "\(baseURL)/api/auth/verify-otp")!
    let body: [String: String] = ["phone": phone, "otp": otp]

    let (data, response) = try await post(url: url, body: body)
    let decoded = try JSONDecoder().decode(VerifyOTPResponse.self, from: data)

    guard decoded.success, let token = decoded.token, let user = decoded.user else {
      throw AuthAPIError.server(
        decoded.error ?? "Verification failed",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }

    return OtpSession(token: token, user: user)
  }

  /// Validate an existing session token and return the current user.
  static func validateSession(token: String) async throws -> AuthUser {
    let url = URL(string: "\(baseURL)/api/auth/validate-session")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, _) = try await URLSession.shared.data(for: request)
    let decoded = try JSONDecoder().decode(ValidateSessionResponse.self, from: data)

    guard decoded.success, let user = decoded.user else {
      throw AuthAPIError.sessionInvalid(decoded.error ?? "Invalid or expired session")
    }

    return user
  }

  /// Fetch the signed-in user's IAM permissions. Mirrors Android
  /// `GET /api/iam/my-permissions` used by App Library feature gates.
  static func getMyIAMPermissions(token: String) async throws -> (permissions: [String], isAdmin: Bool) {
    let url = URL(string: "\(baseURL)/api/iam/my-permissions")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    let decoded = try JSONDecoder().decode(MyIAMPermissionsResponse.self, from: data)

    if decoded.success == false {
      throw AuthAPIError.server(
        decoded.error ?? "Failed to load permissions",
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }

    return (decoded.permissions, decoded.isAdmin)
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

  // MARK: - Helpers

  private static func post(url: URL, body: [String: String]) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return try await URLSession.shared.data(for: request)
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
