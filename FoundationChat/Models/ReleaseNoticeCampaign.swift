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
    // The 10 Sep "Sorry for the inconvenience" apology notice is retired
    // (26 Sep); no release notice is shown until a new campaign is set here.
    static let active: ReleaseNoticeCampaign? = nil
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
