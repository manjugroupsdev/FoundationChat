import SwiftUI

struct PresenceIndicatorView: View {
    let status: PresenceStatus
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .strokeBorder(.white, lineWidth: size > 10 ? 2 : 1.5)
            }
    }

    private var statusColor: Color {
        switch status {
        case .online: return .green
        case .away: return .yellow
        case .busy: return .red
        case .offline: return Color(.systemGray3)
        }
    }
}
