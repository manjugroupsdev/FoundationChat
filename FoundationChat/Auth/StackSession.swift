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

extension AuthUser {
  var isFleetAdminDriver: Bool {
    designation?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .localizedCaseInsensitiveCompare("Driver") == .orderedSame
      && department?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .localizedCaseInsensitiveCompare("Administration") == .orderedSame
  }

  var isExternalFleetPrincipal: Bool {
    designation?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .localizedCaseInsensitiveCompare("External Fleet") == .orderedSame
  }

  var isFleetPortalMode: Bool {
    isExternalFleetPrincipal || isFleetAdminDriver
  }

  var isFleetDriverMode: Bool {
    return !isFleetAdminDriver && designation?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .localizedCaseInsensitiveCompare("Driver") == .orderedSame
  }

  /// Any driver designation, incl. qualified forms like "Driver (Transport)"
  /// / "Driver - Transport" — not just the bare word "Driver". Mirrors Android
  /// `SessionManager.isDriverDesignation`; matching only the exact word left
  /// internal transport drivers out of the driver / fleet-trip gates.
  private var isAnyDriverDesignation: Bool {
    let d = designation?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    return d == "driver"
      || d.hasPrefix("driver ")
      || d.hasPrefix("driver(")
      || d.hasPrefix("driver-")
  }

  /// Mirrors Android `SessionManager.canViewFleetMyTrips()`: drivers (roster
  /// check), super-admins, and anyone explicitly granted
  /// `marketing.fleet.myTrips.view`. Deliberately does NOT collapse to the
  /// broad `isAdmin` flag (the phantom-key leak Android documents).
  var canViewFleetMyTrips: Bool {
    if isAnyDriverDesignation { return true }
    let normalizedRole = role?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if normalizedRole == "super-admin" { return true }
    return iamPermissions?.contains("marketing.fleet.myTrips.view") == true
  }

  /// Mirrors Android `SessionManager.canCompleteOfflineFleet()`: external
  /// agency operators, super-admins, or an explicit
  /// `marketing.fleet.completeOffline` grant.
  var canCompleteOfflineFleet: Bool {
    if isExternalFleetPrincipal { return true }
    let normalizedRole = role?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if normalizedRole == "super-admin" { return true }
    return iamPermissions?.contains("marketing.fleet.completeOffline") == true
  }

  /// Mirrors Android `SessionManager.canViewVpDashboard()`.
  /// Do not key this off broad `isAdmin`; Android only allows super-admin,
  /// explicit `vpDashboard.view`, or VP/GM/MD designation families.
  var canViewManagementDashboard: Bool {
    let normalizedRole = role?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if normalizedRole == "super-admin" { return true }
    if iamPermissions?.contains("vpDashboard.view") == true { return true }

    let normalizedDesignation = designation?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    guard !normalizedDesignation.isEmpty else { return false }
    if normalizedDesignation.contains("vice president")
      || normalizedDesignation.contains("vice-president")
      || normalizedDesignation.contains("general manager")
      || normalizedDesignation.contains("managing director") {
      return true
    }
    return normalizedDesignation.range(
      of: #"(^|[^a-z])(vp|avp|gm|agm|dgm)([^a-z]|$)"#,
      options: .regularExpression
    ) != nil
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
