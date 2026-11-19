import SwiftUI

/// Mconnect confirmation sheet: parity with Android's
/// `AppBottomSheets.showConfirm` (title, message, one primary or red action,
/// a secondary cancel). Use it instead of a stock `.alert` / `.confirmationDialog`.
///
///     .mconnectConfirm(item: $target, title: { _ in "Delete this photo?" },
///                      message: { _ in "…" }, confirmLabel: "Delete", destructive: true) { target in … }
struct MconnectConfirmSheet: View {
    let title: String
    let message: String
    let confirmLabel: String
    var cancelLabel: String = "Cancel"
    var destructive: Bool = false
    var systemImage: String? = nil
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(destructive ? MconnectButtonStyle.dangerColor : MconnectButtonStyle.primaryColor)
                        .frame(width: 40, height: 40)
                        .background(
                            (destructive ? MconnectButtonStyle.dangerColor : MconnectButtonStyle.primaryColor).opacity(0.12),
                            in: Circle()
                        )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText)
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 8) {
                Button(confirmLabel, action: onConfirm)
                    .buttonStyle(.mconnect(destructive ? .danger : .primary))
                Button(cancelLabel, action: onCancel)
                    .buttonStyle(.mconnect(.secondary))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appSurface.ignoresSafeArea())
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
    }
}

extension View {
    /// Shows `MconnectConfirmSheet` while `item` is non-nil.
    func mconnectConfirm<Item: Identifiable>(
        item: Binding<Item?>,
        title: @escaping (Item) -> String,
        message: @escaping (Item) -> String,
        confirmLabel: String,
        cancelLabel: String = "Cancel",
        destructive: Bool = false,
        systemImage: String? = nil,
        onConfirm: @escaping (Item) -> Void
    ) -> some View {
        sheet(item: item) { target in
            MconnectConfirmSheet(
                title: title(target),
                message: message(target),
                confirmLabel: confirmLabel,
                cancelLabel: cancelLabel,
                destructive: destructive,
                systemImage: systemImage,
                onConfirm: {
                    item.wrappedValue = nil
                    onConfirm(target)
                },
                onCancel: { item.wrappedValue = nil }
            )
        }
    }
}
