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
    /// MMS-289: the screen's main "do it" action (Apply / Submit / Create /
    /// Next). Its colour is the one-line choice in `MconnectButtonStyle.ctaKind`.
    case cta
}

/// MMS-289 sizes by placement (parity with Android `.Medium` / `.Compact`):
/// `.large` 52pt footer CTA, `.medium` 48pt action inside a card (the
/// "Call Client" size), `.compact` 36pt row action that wraps its content.
enum MconnectButtonSize {
    case large, medium, compact

    var height: CGFloat { switch self { case .large: 52; case .medium: 48; case .compact: 36 } }
    var fontSize: CGFloat { switch self { case .large: 16; case .medium: 14; case .compact: 13 } }
    var horizontalPadding: CGFloat { switch self { case .large, .medium: 16; case .compact: 12 } }
    var iconSpacing: CGFloat { self == .compact ? 6 : 8 }
    var fullWidth: Bool { self != .compact }
}

struct MconnectButtonStyle: ButtonStyle {
    let kind: MconnectButtonKind
    var size: MconnectButtonSize = .large
    @Environment(\.isEnabled) private var isEnabled

    /// ONE-LINE CHOICE (user decision A): `.success` = flat green, `.primary` =
    /// brand blue. Mirrors Android's Widget.Mconnect.Button.Cta parent.
    static let ctaKind: MconnectButtonKind = .primary

    static let primaryColor = Color(hex: 0x0B61CA)
    static let successColor = Color(hex: 0x16A34A)
    static let dangerColor = Color(hex: 0xDC2626)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.fontSize, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isEnabled ? foreground : Color.appSecondaryText)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: size.fullWidth ? .infinity : nil)
            .frame(height: size.height)
            .background(isEnabled ? fill : disabledFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isEnabled ? stroke : disabledStroke, lineWidth: (isEnabled ? stroke : disabledStroke) == .clear ? 0 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled && configuration.isPressed ? 0.85 : 1)
    }

    /// `.cta` resolves to the chosen variant; everything else is itself.
    private var resolvedKind: MconnectButtonKind { kind == .cta ? Self.ctaKind : kind }

    private var foreground: Color {
        switch resolvedKind {
        case .primary, .success, .danger, .cta: .white
        case .secondary: Color.appPrimaryText
        case .dangerOutline: Self.dangerColor
        }
    }

    private var fill: Color {
        switch resolvedKind {
        case .primary, .cta: Self.primaryColor // .cta never reaches here (resolvedKind)
        case .success: Self.successColor
        case .danger: Self.dangerColor
        case .secondary, .dangerOutline: .clear
        }
    }

    /// MMS-289: one disabled look for every variant (muted fill, secondary text).
    private var disabledFill: Color {
        switch resolvedKind {
        case .secondary, .dangerOutline: .clear
        default: Color.appSeparator
        }
    }

    private var disabledStroke: Color {
        switch resolvedKind {
        case .secondary, .dangerOutline: Color.appSeparator
        default: .clear
        }
    }

    private var stroke: Color {
        switch resolvedKind {
        case .secondary: Color.appSeparator
        case .dangerOutline: Self.dangerColor
        default: .clear
        }
    }
}

extension ButtonStyle where Self == MconnectButtonStyle {
    static func mconnect(_ kind: MconnectButtonKind, compact: Bool = false) -> MconnectButtonStyle {
        MconnectButtonStyle(kind: kind, size: compact ? .compact : .large)
    }

    static func mconnect(_ kind: MconnectButtonKind, size: MconnectButtonSize) -> MconnectButtonStyle {
        MconnectButtonStyle(kind: kind, size: size)
    }
}

/// Label for an Mconnect button with a leading SF Symbol (the "Call Client"
/// look) and an optional loading state that keeps the button's width.
///
///     Button { call() } label: { MconnectButtonLabel("Call Client", systemImage: "phone") }
///         .buttonStyle(.mconnect(.primary, size: .medium))
struct MconnectButtonLabel: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    var spacing: CGFloat = 8
    /// White suits the filled variants; pass `.appPrimaryText` on outline ones.
    var spinnerTint: Color = .white

    init(_ title: String, systemImage: String? = nil, isLoading: Bool = false, spacing: CGFloat = 8, spinnerTint: Color = .white) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.spacing = spacing
        self.spinnerTint = spinnerTint
    }

    var body: some View {
        ZStack {
            HStack(spacing: spacing) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView().tint(spinnerTint)
            }
        }
        .accessibilityLabel(title)
    }
}
