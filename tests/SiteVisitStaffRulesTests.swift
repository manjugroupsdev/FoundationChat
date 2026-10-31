import Foundation

@main
struct SiteVisitStaffRulesTests {
    static func main() {
        let eligible: [(String?, String?, String?)] = [
            ("active", "Sales & Marketing", "Assistant Manager"),
            ("active", "Sales & Marketing", "Senior Business Development Executive"),
            ("active", "Sales and Marketing", "General Manager"),
            ("active", "Telesales", "LMO"),
            ("active", "Telesales", "Lead Management Executive"),
            ("active", "Channel-Partner", "Executive"),
            ("active", "Telesales", "Telecaller"),
            (" ACTIVE ", " SALES&MARKETING ", nil),
            (nil, "Sales / Marketing", "Assistant Manager"),
            ("", "Telesales", "LMO")
        ]
        for (status, department, designation) in eligible {
            precondition(SiteVisitStaffRules.lmoOrBdo(status: status, department: department, designation: designation))
        }
        for status in ["inactive", "terminated", "suspended", "invited", "pending-approval"] {
            precondition(!SiteVisitStaffRules.lmoOrBdo(status: status, department: "Sales & Marketing", designation: "BDO"))
        }
        precondition(!SiteVisitStaffRules.lmoOrBdo(status: "active", department: "Accounts", designation: "BDO"))
        precondition(!SiteVisitStaffRules.lmoOrBdo(status: "active", department: nil, designation: "Assistant Manager"))
        precondition(SiteVisitStaffRules.salesMarketing(status: "active", department: "Sales&Marketing"))
        precondition(!SiteVisitStaffRules.salesMarketing(status: "active", department: "Telesales"))
        precondition(!SiteVisitStaffRules.salesMarketing(status: "terminated", department: "Sales & Marketing"))
        precondition(!SiteVisitStaffRules.lmoOrBdo(status: "active", department: "Telesales", designation: "Assistant Manager"))
        precondition(!SiteVisitStaffRules.lmoOrBdo(status: "active", department: "Telesales", designation: nil))
        precondition(!SiteVisitStaffRules.lmoOrBdo(status: "active", department: "External", designation: "Channel Partner"))
        print("SiteVisitStaffRules: 23 assertions passed")
    }
}
