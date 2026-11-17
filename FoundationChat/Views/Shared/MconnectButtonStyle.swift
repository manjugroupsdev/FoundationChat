import SwiftUI

/// Mconnect action button component — parity with Android's
/// `Widget.Mconnect.Button*` (values/buttons.xml): 52pt high (36pt compact),
/// 12pt corners, 16pt semibold (13pt compact), full width.
///
///     Button("Approve") { … }.buttonStyle(.mconnect(.success))
///     Button("Cancel") { … }.buttonStyle(.mconnect(.secondary))
///
/// Use it instead of hand-rolled `.frame(height:)` + `.background(Color(hex:))`
/// buttons so every screen's buttons look the same and follow dark mode.
enum MconnectButtonKind {
    case primary, secondary, success, danger, dangerOutline
}

struct MconnectButtonStyle: ButtonStyle {
    let kind: MconnectButtonKind
    var compact: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    static let primaryColor = Color(hex: 0x0B61CA)
    static let successColor = Color(hex: 0x16A34A)
    static let dangerColor = Color(hex: 0xDC2626)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 16, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 14 : 16)
            .frame(maxWidth: compact ? nil : .infinity)
            .frame(height: compact ? 36 : 52)
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke, lineWidth: stroke == .clear ? 0 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .success, .danger: .white
        case .secondary: Color.appPrimaryText
        case .dangerOutline: Self.dangerColor
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: Self.primaryColor
        case .success: Self.successColor
        case .danger: Self.dangerColor
        case .secondary, .dangerOutline: .clear
        }
    }

    private var stroke: Color {
        switch kind {
        case .secondary: Color.appSeparator
        case .dangerOutline: Self.dangerColor
        default: .clear
        }
    }
}

extension ButtonStyle where Self == MconnectButtonStyle {
    static func mconnect(_ kind: MconnectButtonKind, compact: Bool = false) -> MconnectButtonStyle {
        MconnectButtonStyle(kind: kind, compact: compact)
    }
}
