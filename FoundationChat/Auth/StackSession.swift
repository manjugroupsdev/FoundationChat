import Foundation

struct OtpSession: Codable, Sendable, Equatable {
  let sessionToken: String
  let phoneNumber: String
  let stackUserId: String
  let expiresAt: Double
}
