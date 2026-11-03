import Foundation

/// Editing rules for the single OTP field behind the six code boxes.
///
/// One field holds the whole code, so the keyboard stays up while typing.
/// It used to be six fields; moving first responder to the next one after
/// every digit made the keyboard close and reopen between digits.
nonisolated enum OtpCodeInput {
    static let length = 6

    /// The code after replacing `range` of `current` with `replacement`:
    /// digits only, at most `length`. A full code arriving at once (autofill
    /// "From Messages", paste) replaces whatever was typed.
    static func apply(current: String, range: NSRange, replacement: String, length: Int = length) -> String {
        let incoming = replacement.filter(\.isNumber)
        if incoming.count >= length {
            return String(incoming.suffix(length))
        }
        let base = current as NSString
        let location = min(max(range.location, 0), base.length)
        let safeRange = NSRange(location: location, length: min(max(range.length, 0), base.length - location))
        let edited = base.replacingCharacters(in: safeRange, with: incoming)
        return String(edited.filter(\.isNumber).prefix(length))
    }

    /// The box showing the caret: the next empty one, or the last when full.
    static func activeIndex(for code: String, length: Int = length) -> Int {
        min(code.count, length - 1)
    }
}
