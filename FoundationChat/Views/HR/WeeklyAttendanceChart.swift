import SwiftUI

struct WeeklyAttendanceChart: View {
    let summary: [DayAttendanceSummary]
    private let targetHours: Double = 9.0

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(summary) { day in
                VStack(spacing: 6) {
                    if let hours = day.hours {
                        Text(String(format: "%.0f", hours))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(colorForHours(hours))
                    } else {
                        Text("--")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor(for: day))
                        .frame(width: 28, height: barHeight(for: day))

                    Text(day.day)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 120)
    }

    private func barHeight(for day: DayAttendanceSummary) -> CGFloat {
        guard let hours = day.hours else { return 8 }
        let ratio = min(hours / targetHours, 1.0)
        return max(8, CGFloat(ratio) * 80)
    }

    private func barColor(for day: DayAttendanceSummary) -> Color {
        guard let hours = day.hours else { return Color(.systemGray4) }
        return colorForHours(hours)
    }

    private func colorForHours(_ hours: Double) -> Color {
        if hours >= 8 { return .green }
        if hours >= 4 { return .orange }
        return .red
    }
}
