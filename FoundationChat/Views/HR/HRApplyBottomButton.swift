import SwiftUI

/// The HR "Apply …" bottom button (MMS-290, restyled MMS-289): the CTA button, or a grey
/// disabled "Unavailable" button with a one-line reason under it when nothing
/// is left to apply for. Keeps the existing look and tap action otherwise.
struct HRApplyBottomButton: View {
    let title: String
    let height: CGFloat
    let state: HRApplyAvailability.State
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Text(state.available ? title : HRApplyAvailability.unavailableLabel)
            }
            // MMS-289: the shared CTA button (brand blue); "Unavailable" uses the
            // system's one disabled look. `height` is kept for callers; the
            // footer CTA is the Large size.
            .buttonStyle(.mconnect(.cta))
            .disabled(!state.available)
            .accessibilityLabel(state.available ? title : [HRApplyAvailability.unavailableLabel, state.reason].compactMap { $0 }.joined(separator: ". "))

            if !state.available, let reason = state.reason {
                Text(reason)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
    }
}
