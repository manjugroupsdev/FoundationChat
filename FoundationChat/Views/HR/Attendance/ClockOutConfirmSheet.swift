import SwiftUI

struct ClockOutConfirmSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 68, height: 68)
                Image(systemName: "arrow.up.forward.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .padding(.top, 22)

            Text("Clock Out?")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            Text("Please confirm before closing your active attendance session.")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x475467))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color(hex: 0x344054))

                Button(action: onConfirm) {
                    Text("Confirm")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
        .background(.white)
    }
}

#Preview {
    ClockOutConfirmSheet {} onCancel: {}
}
