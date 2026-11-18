import Foundation

/// SV outcome "Booking Follow Up" (stored outcome follow_up): the counselling
/// person ticks the reasons that apply; each ticked reason requires its fields.
/// Same keys, budgets, facings and remark rules as the server
/// (zeus convex/lib/svFollowUp.ts) and Android (SvFollowUpRules.kt).
nonisolated enum SvFollowUpRules {
    struct Option: Identifiable, Hashable, Sendable {
        let key: String
        let label: String
        var id: String { key }
    }

    static let reasons: [Option] = [
        Option(key: "location", label: "Location"),
        Option(key: "distance", label: "Distance"),
        Option(key: "budget", label: "Preferred Budget"),
        Option(key: "loan_eligibility", label: "Loan Eligibility issue"),
        Option(key: "plot_not_available", label: "Preferred Plot Not Available"),
        Option(key: "misguided_visit", label: "Mis-guided Site Visit"),
        Option(key: "hospitality_service", label: "Hospitality & Service Issue"),
    ]

    static let budgets: [Option] = [
        Option(key: "below_10l", label: "Below 10 Lacs"),
        Option(key: "10_20l", label: "10 to 20 Lacs"),
        Option(key: "20_40l", label: "20 to 40 Lacs"),
        Option(key: "above_40l", label: "Above 40 Lacs"),
    ]

    static let facings: [Option] = [
        Option(key: "east", label: "East"),
        Option(key: "west", label: "West"),
        Option(key: "north", label: "North"),
        Option(key: "south", label: "South"),
        Option(key: "corner", label: "Corner"),
        Option(key: "parkview", label: "Parkview"),
    ]

    static let remarksMin = 250
    static let remarksMax = 500

    struct Draft: Equatable, Sendable {
        var reasons: Set<String> = []
        var locationLabel = ""
        var locationPincode: String?
        var locationLat: Double?
        var locationLng: Double?
        var locationPlaceId: String?
        var distanceKm = ""
        var preferredBudget = ""
        var handCashAmount = ""
        var plotFacing = ""
        var plotAreaSqft = ""
        var plotBudget = ""
        var misguidedRemarks = ""
        var hospitalityRemarks = ""

        /// Ticked reasons in display order.
        var orderedReasons: [String] { SvFollowUpRules.reasons.map(\.key).filter(reasons.contains) }
    }

    static func normalizeRemarks(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when remarks are filler: one character dominating ("xxxxx", "……"),
    /// a short unit repeated ("ababab", "asdasdasd"), mostly non-letters, a long
    /// run of one character, or very few distinct words.
    static func isRepetitiveText(_ input: String) -> Bool {
        let text = normalizeRemarks(input).lowercased()
        if text.isEmpty { return false }
        let compact = Array(text.replacingOccurrences(of: " ", with: ""))
        if compact.isEmpty { return true }

        let letters = compact.filter(\.isLetter).count
        if Double(letters) / Double(compact.count) < 0.6 { return true }

        var counts: [Character: Int] = [:]
        for ch in compact { counts[ch, default: 0] += 1 }
        let top = counts.values.max() ?? 0
        if Double(top) / Double(compact.count) > 0.4 { return true }
        if counts.count <= 3 && compact.count >= 12 { return true }

        for unit in 1...6 {
            if compact.count < unit * 4 { break }
            let pattern = Array(compact[0..<unit])
            var matched = 0
            var i = 0
            while i + unit <= compact.count {
                if Array(compact[i..<(i + unit)]) == pattern { matched += unit }
                i += unit
            }
            if Double(matched) / Double(compact.count) > 0.7 { return true }
        }

        var run = 1
        for i in 1..<compact.count {
            run = compact[i] == compact[i - 1] ? run + 1 : 1
            if run >= 6 { return true }
        }

        let words = text.split(separator: " ")
        if words.count >= 8, Double(Set(words).count) / Double(words.count) < 0.35 { return true }
        return false
    }

    /// Staff-facing problem with a remarks text, or nil when it's fine.
    static func remarksProblem(_ input: String) -> String? {
        let text = normalizeRemarks(input)
        if text.count < remarksMin { return "Write at least \(remarksMin) characters (\(text.count) so far)." }
        if text.count > remarksMax { return "Keep it within \(remarksMax) characters (\(text.count) now)." }
        if isRepetitiveText(text) { return "Write real remarks, not repeated characters." }
        return nil
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// First problem, as the message to show, or nil when the draft can be saved.
    static func validate(_ d: Draft) -> String? {
        if d.reasons.isEmpty { return "Select at least one follow-up reason." }
        for reason in d.orderedReasons {
            switch reason {
            case "location":
                if d.locationLabel.trimmingCharacters(in: .whitespaces).isEmpty {
                    return "Enter the client's preferred location."
                }
            case "distance":
                guard let km = number(d.distanceKm), km > 0, km <= 1000 else { return "Enter the expected distance in km." }
            case "budget":
                if !budgets.contains(where: { $0.key == d.preferredBudget }) { return "Choose the preferred budget." }
            case "loan_eligibility":
                guard let amount = number(d.handCashAmount), amount > 0 else {
                    return "Enter how much the client can afford as hand cash."
                }
            case "plot_not_available":
                if !facings.contains(where: { $0.key == d.plotFacing }) { return "Choose the expected facing." }
                guard let area = number(d.plotAreaSqft), area > 0 else { return "Enter the expected plot area." }
                if !budgets.contains(where: { $0.key == d.plotBudget }) { return "Choose the budget for the plot." }
            case "misguided_visit":
                if let p = remarksProblem(d.misguidedRemarks) { return "Mis-guided Site Visit: \(p)" }
            case "hospitality_service":
                if let p = remarksProblem(d.hospitalityRemarks) { return "Hospitality & Service Issue: \(p)" }
            default:
                return "Unknown follow-up reason \"\(reason)\"."
            }
        }
        return nil
    }

    /// followUpDetails for the request: only the fields of ticked reasons.
    static func details(_ d: Draft) -> SvFollowUpDetailsPayload {
        let ticked = d.reasons
        return SvFollowUpDetailsPayload(
            location: ticked.contains("location")
                ? .init(
                    label: d.locationLabel.trimmingCharacters(in: .whitespaces),
                    pincode: d.locationPincode,
                    lat: d.locationLat,
                    lng: d.locationLng,
                    placeId: d.locationPlaceId
                )
                : nil,
            distanceKm: ticked.contains("distance") ? number(d.distanceKm) : nil,
            preferredBudget: ticked.contains("budget") ? d.preferredBudget : nil,
            handCashAmount: ticked.contains("loan_eligibility") ? number(d.handCashAmount) : nil,
            plot: ticked.contains("plot_not_available")
                ? .init(facing: d.plotFacing, areaSqft: number(d.plotAreaSqft) ?? 0, budget: d.plotBudget)
                : nil,
            misguidedRemarks: ticked.contains("misguided_visit") ? normalizeRemarks(d.misguidedRemarks) : nil,
            hospitalityRemarks: ticked.contains("hospitality_service") ? normalizeRemarks(d.hospitalityRemarks) : nil
        )
    }
}

/// Wire shape of followUpDetails (server: convex/lib/svFollowUp.ts).
nonisolated struct SvFollowUpDetailsPayload: Encodable, Sendable, Equatable {
    struct Location: Encodable, Sendable, Equatable {
        let label: String
        let pincode: String?
        let lat: Double?
        let lng: Double?
        let placeId: String?
    }

    struct Plot: Encodable, Sendable, Equatable {
        let facing: String
        let areaSqft: Double
        let budget: String
    }

    let location: Location?
    let distanceKm: Double?
    let preferredBudget: String?
    let handCashAmount: Double?
    let plot: Plot?
    let misguidedRemarks: String?
    let hospitalityRemarks: String?
}
