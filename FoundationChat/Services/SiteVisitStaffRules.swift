import Foundation

enum SiteVisitStaffRules {
    static func isActive(_ status: String?) -> Bool {
        let value = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty || value == "active"
    }

    static func salesMarketing(status: String?, department: String?) -> Bool {
        let value = normalize(department)
        return isActive(status) && value.contains("sales") && value.contains("marketing")
    }

    // Sales & Marketing accepts every designation; other departments retain
    // the create API's existing eligibility rules.
    static func lmoOrBdo(status: String?, department: String?, designation: String?) -> Bool {
        guard isActive(status) else { return false }
        let value = normalize(department)
        let title = normalize(designation).trimmingCharacters(in: .whitespacesAndNewlines)
        let telesalesLmo = value.contains("telesales") && (title == "lmo"
            || title.contains("lead management executive") || title.contains("telecaller"))
        return salesMarketing(status: status, department: department) || telesalesLmo || value.contains("channel partner")
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
