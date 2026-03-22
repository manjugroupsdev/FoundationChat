import Foundation
import Security

struct KeychainTokenStore {
  private let service = "com.manjugroups.foundationchat.otp-session"
  private let account = "default"
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  func save(_ session: OtpSession) throws {
    let data = try encoder.encode(session)
    let query = baseQuery()

    SecItemDelete(query as CFDictionary)

    let attributes = query.merging(
      [
        kSecValueData as String: data
      ],
      uniquingKeysWith: { _, new in new })

    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }

  func load() throws -> OtpSession? {
    let query = baseQuery().merging(
      [
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
      ],
      uniquingKeysWith: { _, new in new })

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data else {
        throw KeychainStoreError.invalidData
      }
      return try decoder.decode(OtpSession.self, from: data)
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }

  func clear() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}

enum KeychainStoreError: LocalizedError {
  case invalidData
  case unexpectedStatus(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidData:
      return "Stored session data is invalid."
    case .unexpectedStatus(let status):
      return "Keychain request failed with status \(status)."
    }
  }
}
