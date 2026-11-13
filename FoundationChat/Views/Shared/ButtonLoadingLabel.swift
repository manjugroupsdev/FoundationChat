import SwiftUI

/// The one button loading state for the whole app (same as Android's
/// ButtonLoader): a small spinner next to an in-progress label ("Signing in",
/// "Saving") in the label's own colour. Use it as a Button's label:
///
///     Button { save() } label: {
///         ButtonLoadingLabel("Save", loading: isSaving, loadingTitle: "Saving")
///     }
///     .disabled(isSaving)
struct ButtonLoadingLabel: View {
    let title: String
    let loadingTitle: String
    let isLoading: Bool
    var font: Font = .system(size: 14, weight: .medium)
    var color: Color = .white

    init(
        _ title: String,
        loading isLoading: Bool,
        loadingTitle: String,
        font: Font = .system(size: 14, weight: .medium),
        color: Color = .white
    ) {
        self.title = title
        self.loadingTitle = loadingTitle
        self.isLoading = isLoading
        self.font = font
        self.color = color
    }

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(color)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
            Text(isLoading ? loadingTitle : title)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .animation(.easeOut(duration: 0.18), value: isLoading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLoading ? loadingTitle : title)
    }
}
