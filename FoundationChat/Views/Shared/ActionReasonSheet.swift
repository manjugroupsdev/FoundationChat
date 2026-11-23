import SwiftUI

/// Shared "action with a required reason" sheet: a title, subtitle, one
/// multi-line reason field and a Mconnect action button. Used for Reject SV /
/// Cancel SV on the CP outcome sheet and Reject on SV Approvals (parity with
/// Android `RejectWithReasonBottomSheet`). A blank reason shows
/// `missingReasonError` and never calls `onSubmit`.
///
///     .sheet(item: $target) { target in
///         ActionReasonSheet(title: "Reject site visit", …, submitKind: .danger,
///                           isSaving: busy) { reason in await reject(target, reason) }
///             .appLibraryNativeSheet([.medium, .large])
///     }
struct ActionReasonSheet: View {
    let title: String
    let subtitle: String
    let fieldLabel: String
    let placeholder: String
    let submitTitle: String
    var submitKind: MconnectButtonKind = .success
    var missingReasonError: String = "Remarks are required"
    var savingTitle: String = "Saving"
    let isSaving: Bool
    let onSubmit: (String) async -> Void

    @State private var reason = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(fieldLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    TextField(placeholder, text: $reason, axis: .vertical)
                        .font(.system(size: 13))
                        .lineLimit(3...6)
                        .padding(14)
                        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MconnectButtonStyle.dangerColor)
                }

                Button {
                    guard let trimmed = RequiredReason.normalized(reason) else {
                        errorMessage = missingReasonError
                        return
                    }
                    errorMessage = nil
                    Task { await onSubmit(trimmed) }
                } label: {
                    ButtonLoadingLabel(
                        submitTitle,
                        loading: isSaving,
                        loadingTitle: savingTitle,
                        font: .system(size: 16, weight: .semibold)
                    )
                }
                .buttonStyle(.mconnect(submitKind))
                .disabled(isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .background(Color.appSurface)
        .appCompactSheetCTAContainer()
    }
}
