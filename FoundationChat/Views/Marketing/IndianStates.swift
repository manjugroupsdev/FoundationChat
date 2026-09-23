import Foundation

/// The 28 states and 8 union territories, in the spellings the rest of the
/// system already uses.
///
/// Mirrors the `STATES` table the web address parser has used in production
/// (`manjusitedevelopment/lib/address-parse.ts`) and the Android
/// `IndianStates`, so a value picked here, a value parsed out of a pasted
/// address and a value the pincode lookup returns all end up identical.
/// Before this, State was free text and one place arrived as "TN",
/// "Tamilnadu", "tamil nadu" and "TAMIL NADU", quietly splitting every report
/// that groups by state.
///
/// District and city are deliberately NOT modelled. There is no source we can
/// verify as complete for them, and a dropdown missing someone's district
/// would block a real address outright - worse than typing it.
enum IndianStates {

    /// Canonical names, alphabetical; what gets stored and displayed.
    static let all: [String] = [
        "Andaman and Nicobar Islands",
        "Andhra Pradesh",
        "Arunachal Pradesh",
        "Assam",
        "Bihar",
        "Chandigarh",
        "Chhattisgarh",
        "Dadra and Nagar Haveli and Daman and Diu",
        "Delhi",
        "Goa",
        "Gujarat",
        "Haryana",
        "Himachal Pradesh",
        "Jammu and Kashmir",
        "Jharkhand",
        "Karnataka",
        "Kerala",
        "Ladakh",
        "Lakshadweep",
        "Madhya Pradesh",
        "Maharashtra",
        "Manipur",
        "Meghalaya",
        "Mizoram",
        "Nagaland",
        "Odisha",
        "Puducherry",
        "Punjab",
        "Rajasthan",
        "Sikkim",
        "Tamil Nadu",
        "Telangana",
        "Tripura",
        "Uttar Pradesh",
        "Uttarakhand",
        "West Bengal",
    ]

    /// Row model for `NativeSearchableSelectionSheet`, which needs Identifiable.
    struct Option: Identifiable, Hashable {
        let id: String
        var name: String { id }
    }

    static let options: [Option] = all.map { Option(id: $0) }

    /// Spellings seen in the wild that must resolve to a canonical name.
    private static let aliases: [String: String] = [
        "tamilnadu": "Tamil Nadu",
        "tn": "Tamil Nadu",
        "pondicherry": "Puducherry",
        "orissa": "Odisha",
        "uttaranchal": "Uttarakhand",
        "ap": "Andhra Pradesh",
        "ka": "Karnataka",
        "kl": "Kerala",
        "ts": "Telangana",
        "mh": "Maharashtra",
        "up": "Uttar Pradesh",
        "wb": "West Bengal",
        "j&k": "Jammu and Kashmir",
        "jk": "Jammu and Kashmir",
        "dadra and nagar haveli": "Dadra and Nagar Haveli and Daman and Diu",
        "daman and diu": "Dadra and Nagar Haveli and Daman and Diu",
        "nct of delhi": "Delhi",
        "new delhi": "Delhi",
        "andaman & nicobar islands": "Andaman and Nicobar Islands",
        "jammu & kashmir": "Jammu and Kashmir",
    ]

    private static func key(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let byKey: [String: String] = {
        var map: [String: String] = [:]
        for name in all { map[key(name)] = name }
        for (alias, canonicalName) in aliases { map[key(alias)] = canonicalName }
        return map
    }()

    /// The canonical name for whatever was typed, pasted or returned by the
    /// pincode lookup, or nil when it matches nothing we recognise.
    ///
    /// Returning nil rather than guessing matters: a wrong state written into
    /// a client record is harder to spot than an empty one.
    static func canonical(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return byKey[key(trimmed)]
    }
}
