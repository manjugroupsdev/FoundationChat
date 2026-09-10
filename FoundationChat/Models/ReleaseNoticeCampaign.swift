import Foundation

struct ReleaseNoticeCampaign: Identifiable, Equatable {
    let id: String
    let label: String
    let title: String
    let tamilTitle: String
    let transliteratedTamilTitle: String
    let message: String
    let highlights: [String]
    let attribution: String

    // Set to nil for releases that should not present a notice. Change the ID
    // only when a newly requested release banner must appear once per install.
    static let active: ReleaseNoticeCampaign? = ReleaseNoticeCampaign(
        id: "2026-09-10-service-apology-v1",
        label: "SERVICE UPDATE",
        title: "Sorry for the inconvenience",
        tamilTitle: "தடங்கல்களுக்கு வருந்துகிறோம்",
        transliteratedTamilTitle: "Thadangalukku varundhugindrom",
        message: "Thank you for your patience. We have improved MConnect and will continue making your daily work faster and more reliable.",
        highlights: [
            "Improved CP and OTP handling",
            "More reliable visit completion and syncing",
            "General stability improvements",
        ],
        attribution: "MMS IT Team"
    )
}

enum ReleaseNoticeStore {
    private static let seenCampaignIDsKey = "releaseNotice.seenCampaignIDs"

    static func shouldShow(_ campaign: ReleaseNoticeCampaign) -> Bool {
        !seenCampaignIDs.contains(campaign.id)
    }

    static func markSeen(_ campaign: ReleaseNoticeCampaign) {
        var seen = seenCampaignIDs
        seen.insert(campaign.id)
        UserDefaults.standard.set(Array(seen).sorted(), forKey: seenCampaignIDsKey)
    }

    private static var seenCampaignIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: seenCampaignIDsKey) ?? [])
    }
}
