import Foundation

/// The staff password rule and generator, matching the web
/// (lib/password-policy.ts and the Security tab's generator) and Android:
/// 8-128 characters, no spaces, at least one upper case letter, lower case
/// letter, number and special character. The server applies the same rule;
/// checking here first says what is wrong before anything is sent.
enum PasswordPolicy {
    static let ruleText = "Use 8+ characters with uppercase, lowercase, number, and special character."

    private static let upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let lower = Array("abcdefghijkmnpqrstuvwxyz")
    private static let digits = Array("23456789")
    private static let symbols = Array("!@#$%&*?")

    /// Nil when `password` is acceptable, otherwise what is missing.
    static func problem(_ password: String) -> String? {
        if password.count < 8 { return "Use at least 8 characters." }
        if password.count > 128 { return "Use at most 128 characters." }
        if password.contains(where: { $0.isWhitespace }) { return "Don't use spaces." }
        if !password.contains(where: { ("A"..."Z").contains($0) }) { return "Add an uppercase letter." }
        if !password.contains(where: { ("a"..."z").contains($0) }) { return "Add a lowercase letter." }
        if !password.contains(where: { ("0"..."9").contains($0) }) { return "Add a number." }
        if password.allSatisfy({ $0.isLetter || $0.isNumber }) { return "Add a special character." }
        return nil
    }

    /// A 12-character password with every required kind of character.
    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        let all = upper + lower + digits + symbols
        var chars: [Character] = [
            upper.randomElement(using: &generator)!,
            lower.randomElement(using: &generator)!,
            digits.randomElement(using: &generator)!,
            symbols.randomElement(using: &generator)!,
        ]
        for _ in 0..<8 { chars.append(all.randomElement(using: &generator)!) }
        chars.shuffle(using: &generator)
        return String(chars)
    }
}
