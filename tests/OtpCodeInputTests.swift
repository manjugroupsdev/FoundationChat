import Foundation

@main
struct OtpCodeInputTests {
    static func main() {
        func end(_ s: String) -> NSRange { NSRange(location: (s as NSString).length, length: 0) }
        // Typing digit by digit appends.
        var code = ""
        for d in "482916" { code = OtpCodeInput.apply(current: code, range: end(code), replacement: String(d)) }
        precondition(code == "482916")
        // A seventh digit is ignored.
        precondition(OtpCodeInput.apply(current: code, range: end(code), replacement: "7") == "482916")
        // Backspace removes the last digit.
        precondition(OtpCodeInput.apply(current: "4829", range: NSRange(location: 3, length: 1), replacement: "") == "482")
        // Autofill / paste of the whole code replaces a partial entry.
        precondition(OtpCodeInput.apply(current: "12", range: end("12"), replacement: "482916") == "482916")
        precondition(OtpCodeInput.apply(current: "", range: end(""), replacement: "Your code is 482916") == "482916")
        // Letters and spaces are dropped.
        precondition(OtpCodeInput.apply(current: "1", range: end("1"), replacement: "a 2") == "12")
        // A short paste appends and is capped.
        precondition(OtpCodeInput.apply(current: "1234", range: end("1234"), replacement: "567") == "123456")
        // An out-of-range selection never crashes.
        precondition(OtpCodeInput.apply(current: "12", range: NSRange(location: 5, length: 3), replacement: "3") == "123")
        // Caret box.
        precondition(OtpCodeInput.activeIndex(for: "") == 0)
        precondition(OtpCodeInput.activeIndex(for: "482") == 3)
        precondition(OtpCodeInput.activeIndex(for: "482916") == 5)
        print("OtpCodeInput: 11 assertions passed")
    }
}
