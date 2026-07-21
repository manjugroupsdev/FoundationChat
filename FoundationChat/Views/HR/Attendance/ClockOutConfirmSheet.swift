import SwiftUI

struct ClockOutConfirmSheet: View {
    var todayMinutes: Int = 0
    var overtimeMinutes: Int = 0
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 32)

                VStack(spacing: 0) {
                    Text("Confirm Clockout")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)

                    Text("Once you clock out, you won't be able to edit this time. Please double-check your hours before proceeding.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x475467))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 12)
                        .padding(.horizontal, 20)

                    HStack(spacing: 8) {
                        statTile(title: "Today", value: Self.format(minutes: todayMinutes))
                        statTile(title: "Overtime", value: Self.format(minutes: overtimeMinutes))
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                    Button(action: onConfirm) {
                        Text("Yes, Clock Out")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(androidGreenGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                    Button(action: onCancel) {
                        Text("No, Let me check")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(androidGreen)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white, in: Capsule())
                            .overlay(Capsule().stroke(androidGreen, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .background(Color.white, in: UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                ))
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: 0x0B61CA))
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
                Image(systemName: "clock.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .background(Color.clear)
        .appCompactSheetCTAContainer()
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x475467))
            } icon: {
                Image(systemName: "clock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x475467))
            }

            Text(value)
                .font(.system(size: 20, weight: .regular).monospacedDigit())
                .foregroundStyle(Color(hex: 0x161B23))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .padding(.horizontal, 11)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
    }

    private static func format(minutes: Int) -> String {
        let safe = max(0, minutes)
        return String(format: "%02d:%02d:00 Hrs", safe / 60, safe % 60)
    }

    private var androidGreen: Color { Color(hex: 0x1BCA0B) }

    private var androidGreenGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x1BCA0B), Color(hex: 0x3D9D02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    ClockOutConfirmSheet(todayMinutes: 34, overtimeMinutes: 0) {} onCancel: {}
}
