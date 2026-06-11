import Foundation
import SwiftUI

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

    static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
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
