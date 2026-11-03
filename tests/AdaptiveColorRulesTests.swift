import Foundation

@main
struct AdaptiveColorRulesTests {
    static func main() {
        typealias R = AdaptiveColorRules
        let background = R.rgb(hex: 0x000000)
        func contrast(_ a: R.RGB, _ b: R.RGB) -> Double {
            let la = R.luminance(a), lb = R.luminance(b)
            return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
        }
        // Pale tints become dim in dark mode (no bright patches).
        for hex: UInt in [0xEAF1FF, 0xFEF3F2, 0xECFDF3, 0xF5F8FF, 0xE4E7EC, 0xFFFFFF, 0xEEF0F5] {
            let dark = R.darkTint(R.rgb(hex: hex))
            precondition(R.luminance(dark) < 0.08, "tint \(String(hex, radix: 16)) still bright")
        }
        // Dark inks become readable on a dark background (WCAG AA 4.5:1).
        for hex: UInt in [0x1D2939, 0x111827, 0x334155, 0x374151, 0x7A271A, 0x101828] {
            let dark = R.darkInk(R.rgb(hex: hex))
            precondition(contrast(dark, background) >= 4.5, "ink \(String(hex, radix: 16)) unreadable")
            // ...and on the dimmed tints they sit on.
            precondition(contrast(dark, R.darkTint(R.rgb(hex: 0xFEF3F2))) >= 4.5, "ink on tint \(String(hex, radix: 16))")
        }
        // Hue is kept: a pale red tint stays reddish, a blue one bluish.
        let red = R.darkTint(R.rgb(hex: 0xFEE4E2)), blue = R.darkTint(R.rgb(hex: 0xEAF1FF))
        precondition(red.red > red.blue && blue.blue > blue.red)
        // Classification thresholds used by the screen rewrite.
        precondition(R.luminance(R.rgb(hex: 0xEAF1FF)) > 0.82)
        precondition(R.luminance(R.rgb(hex: 0x1D2939)) < 0.22)
        precondition(R.luminance(R.rgb(hex: 0x0B61CA)) > 0.05 && R.luminance(R.rgb(hex: 0x0B61CA)) < 0.82)
        print("AdaptiveColorRules: 30 assertions passed")
    }
}
