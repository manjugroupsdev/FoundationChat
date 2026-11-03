import Foundation

/// Dark-mode partners for the light-mode-only colours written into screens
/// as hex/RGB literals. Light mode keeps the exact original colour; dark mode
/// keeps its hue:
/// - a pale tint (chip, badge, banner or icon background) becomes a dim
///   version of the same hue, so it no longer glows on a dark screen;
/// - a dark ink (text) becomes a light version of the same hue, so it stays
///   readable instead of disappearing into the background.
nonisolated enum AdaptiveColorRules {
    typealias RGB = (red: Double, green: Double, blue: Double)

    static func darkTint(_ color: RGB) -> RGB {
        let (h, s, _) = hsb(color)
        if s < 0.06 { return rgb(hue: h, saturation: 0, brightness: 0.17) }
        return rgb(hue: h, saturation: min(max(s * 2.5, 0.35), 0.6), brightness: 0.26)
    }

    static func darkInk(_ color: RGB) -> RGB {
        let (h, s, _) = hsb(color)
        let saturation = s < 0.15 ? s * 0.5 : min(s, 0.45)
        return rgb(hue: h, saturation: saturation, brightness: 0.92)
    }

    /// Relative luminance (sRGB, 0...1), used to tell tints from inks.
    static func luminance(_ color: RGB) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    static func rgb(hex: UInt) -> RGB {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func hsb(_ c: RGB) -> (Double, Double, Double) {
        let maxV = max(c.red, c.green, c.blue), minV = min(c.red, c.green, c.blue)
        let delta = maxV - minV
        var hue = 0.0
        if delta > 0 {
            if maxV == c.red { hue = ((c.green - c.blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxV == c.green { hue = (c.blue - c.red) / delta + 2 }
            else { hue = (c.red - c.green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxV == 0 ? 0 : delta / maxV, maxV)
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> RGB {
        let c = brightness * saturation
        let x = c * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double)
        switch Int(hue * 6) % 6 {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}
