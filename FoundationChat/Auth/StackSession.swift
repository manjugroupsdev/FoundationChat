import Foundation

/// User returned from the auth API after OTP verification or session validation.
struct AuthUser: Codable, Sendable, Equatable {
  let _id: String
  let employeeId: String?
  let name: String?
  let phone: String?
  let email: String?
  let role: String?
  let roleLevel: Int?
  let isAdmin: Bool?
  let designation: String?
  let department: String?
  let status: String?
  let photo: String?

  init(
    _id: String,
    employeeId: String? = nil,
    name: String? = nil,
    phone: String? = nil,
    email: String? = nil,
    role: String? = nil,
    roleLevel: Int? = nil,
    isAdmin: Bool? = nil,
    designation: String? = nil,
    department: String? = nil,
    status: String? = nil,
    photo: String? = nil
  ) {
    self._id = _id
    self.employeeId = employeeId
    self.name = name
    self.phone = phone
    self.email = email
    self.role = role
    self.roleLevel = roleLevel
    self.isAdmin = isAdmin
    self.designation = designation
    self.department = department
    self.status = status
    self.photo = photo
  }
}

/// Local session stored in Keychain — token + user snapshot.
struct OtpSession: Codable, Sendable, Equatable {
  let token: String
  let user: AuthUser
}
