import SwiftUI

/// The HR "Apply …" bottom button (MMS-290): the usual green button, or a grey
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
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(state.available ? Color.white : Color.appSecondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background {
                        if state.available {
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        } else {
                            Capsule().fill(Color.appSeparator)
                        }
                    }
            }
            .buttonStyle(.plain)
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
