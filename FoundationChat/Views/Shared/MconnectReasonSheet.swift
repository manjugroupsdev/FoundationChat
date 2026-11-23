import SwiftUI

/// Mconnect confirmation that needs a typed reason: parity with Android's
/// `AppBottomSheets.showRequiredReason` (e.g. rejecting an approval, matching
/// the web's required "Rejection reason"). A blank reason keeps the sheet open
/// with an inline error; `onConfirm` gets the trimmed text.
///
///     .mconnectRequiredReason(item: $target, title: { _ in "Reject?" }, message: { _ in "…" },
///                             reasonPrompt: "Why?", confirmLabel: "Reject") { target, reason in … }
struct MconnectReasonSheet: View {
    let title: String
    let message: String
    let reasonPrompt: String
    let confirmLabel: String
    var cancelLabel: String = "Cancel"
    var destructive: Bool = true
    var missingReasonError: String = "Please share a reason"
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var reason = ""
    @State private var showError = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.appPrimaryText)
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.appSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField(reasonPrompt, text: $reason, axis: .vertical)
                    .lineLimit(3...5)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.appPrimaryText)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(showError ? MconnectButtonStyle.dangerColor : Color.appSeparator, lineWidth: 1)
                    )
                    .onChange(of: reason) { _, value in
                        if RequiredReason.normalized(value) != nil { showError = false }
                    }
                if showError {
                    Text(missingReasonError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MconnectButtonStyle.dangerColor)
                }
            }
            VStack(spacing: 8) {
                Button(confirmLabel) {
                    guard let value = RequiredReason.normalized(reason) else {
                        showError = true
                        focused = true
                        return
                    }
                    onConfirm(value)
                }
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
        .presentationDetents([.height(400), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
    }
}

extension View {
    /// Shows `MconnectReasonSheet` while `item` is non-nil.
    func mconnectRequiredReason<Item: Identifiable>(
        item: Binding<Item?>,
        title: @escaping (Item) -> String,
        message: @escaping (Item) -> String,
        reasonPrompt: String,
        confirmLabel: String,
        cancelLabel: String = "Cancel",
        destructive: Bool = true,
        missingReasonError: String = "Please share a reason",
        onConfirm: @escaping (Item, String) -> Void
    ) -> some View {
        sheet(item: item) { target in
            MconnectReasonSheet(
                title: title(target),
                message: message(target),
                reasonPrompt: reasonPrompt,
                confirmLabel: confirmLabel,
                cancelLabel: cancelLabel,
                destructive: destructive,
                missingReasonError: missingReasonError,
                onConfirm: { reason in
                    item.wrappedValue = nil
                    onConfirm(target, reason)
                },
                onCancel: { item.wrappedValue = nil }
            )
        }
    }
}
