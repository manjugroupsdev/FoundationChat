import Foundation

/// User returned from the auth API after OTP verification or session validation.
struct AuthUser: Codable, Sendable, Equatable {
  let _id: String
  let staffId: String?
  let employeeId: String?
  let name: String?
  let phone: String?
  let email: String?
  let role: String?
  let roleLevel: Int?
  let iamPermissions: [String]?
  let isAdmin: Bool?
  let designation: String?
  let department: String?
  let status: String?
  let photo: String?
  let mustChangePassword: Bool?

  init(
    _id: String,
    staffId: String? = nil,
    employeeId: String? = nil,
    name: String? = nil,
    phone: String? = nil,
    email: String? = nil,
    role: String? = nil,
    roleLevel: Int? = nil,
    iamPermissions: [String]? = nil,
    isAdmin: Bool? = nil,
    designation: String? = nil,
    department: String? = nil,
    status: String? = nil,
    photo: String? = nil,
    mustChangePassword: Bool? = nil
  ) {
    self._id = _id
    self.staffId = staffId
    self.employeeId = employeeId
    self.name = name
    self.phone = phone
    self.email = email
    self.role = role
    self.roleLevel = roleLevel
    self.iamPermissions = iamPermissions
    self.isAdmin = isAdmin
    self.designation = designation
    self.department = department
    self.status = status
    self.photo = photo
    self.mustChangePassword = mustChangePassword
  }
}

/// Local session stored in Keychain — token + user snapshot.
struct OtpSession: Codable, Sendable, Equatable {
  let token: String
  let user: AuthUser
  let mustChangePassword: Bool

  init(token: String, user: AuthUser, mustChangePassword: Bool = false) {
    self.token = token
    self.user = user
    self.mustChangePassword = mustChangePassword
  }

  private enum CodingKeys: String, CodingKey {
    case token
    case user
    case mustChangePassword
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    token = try container.decode(String.self, forKey: .token)
    user = try container.decode(AuthUser.self, forKey: .user)
    mustChangePassword = try container.decodeIfPresent(Bool.self, forKey: .mustChangePassword) ?? false
  }
}
