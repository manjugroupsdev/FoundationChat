import Foundation
import SwiftUI
import UIKit

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Shared semantic surfaces for the operational modules. These keep the
    /// Android-inspired hierarchy while allowing iOS to follow the user's
    /// light/dark appearance instead of painting permanent white cards.
    static let appScreenBackground = Color(uiColor: .systemGroupedBackground)
    static let appSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let appElevatedSurface = Color(uiColor: .systemBackground)
    static let appFieldBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    static let appSeparator = Color(uiColor: .separator)
    static let appPrimaryText = Color(uiColor: .label)
    static let appSecondaryText = Color(uiColor: .secondaryLabel)
    static let appTertiaryText = Color(uiColor: .tertiaryLabel)

    /// A pale light-mode tint (chip, badge, banner, border or icon
    /// background) that dims to the same hue in dark mode instead of glowing.
    /// Light mode is the exact original colour. See `AdaptiveColorRules`.
    nonisolated static func adaptiveTint(_ hex: UInt) -> Color {
        adaptive(AdaptiveColorRules.rgb(hex: hex), ink: false)
    }

    nonisolated static func adaptiveTint(red: Double, green: Double, blue: Double) -> Color {
        adaptive((red, green, blue), ink: false)
    }

    /// A dark light-mode text colour that turns into a light version of the
    /// same hue in dark mode, so it stays readable. Light mode is unchanged.
    nonisolated static func adaptiveInk(_ hex: UInt) -> Color {
        adaptive(AdaptiveColorRules.rgb(hex: hex), ink: true)
    }

    nonisolated static func adaptiveInk(red: Double, green: Double, blue: Double) -> Color {
        adaptive((red, green, blue), ink: true)
    }

    private nonisolated static func adaptive(_ rgb: AdaptiveColorRules.RGB, ink: Bool) -> Color {
        let dark = ink ? AdaptiveColorRules.darkInk(rgb) : AdaptiveColorRules.darkTint(rgb)
        let light = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        let darkColor = UIColor(red: dark.red, green: dark.green, blue: dark.blue, alpha: 1)
        return Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? darkColor : light })
    }
}

extension String {
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AppModuleFormatters {
    static let rupees: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.currencySymbol = "₹"
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_IN")
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    static let shortMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    static let ymd: DateFormatter = {
        let f = CachedDateFormatters.formatter("yyyy-MM-dd", posix: true)
        return f
    }()

    static func rupees(_ amount: Int) -> String {
        rupees.string(from: NSNumber(value: amount)) ?? "₹\(amount)"
    }

    static func rupees(_ amount: Double) -> String {
        rupees.string(from: NSNumber(value: amount)) ?? "₹\(Int(amount))"
    }

    static func prettyScope(_ scope: String?) -> String {
        switch scope {
        case "plots_only": return "Plots only"
        case "villas": return "Villas"
        case "flats": return "Flats"
        case "mixed": return "Mixed"
        case let scope?: return scope
        case nil: return ""
        }
    }

    static func normalizePhone(_ value: String) -> String {
        String(value.filter(\.isNumber).suffix(10))
    }
}

enum AppModuleFont {
    static let screenTitle = Font.system(size: 18, weight: .semibold)
    static let rowTitle = Font.system(size: 16, weight: .semibold)
    static let rowBody = Font.system(size: 15, weight: .regular)
    static let rowMeta = Font.system(size: 12, weight: .regular)
    static let rowMetaSemibold = Font.system(size: 12, weight: .semibold)
    static let action = Font.system(size: 15, weight: .medium)
    static let badge = Font.system(size: 11, weight: .bold)
    static let tabLabel = Font.system(size: 11, weight: .medium)
}

struct AppModuleBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(AppModuleFont.badge)
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct AppModuleLoadingRows: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(height: 74)
                    .redacted(reason: .placeholder)
            }
        }
        .padding()
    }
}
