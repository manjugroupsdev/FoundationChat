import SwiftUI

struct TypingIndicatorView: View {
    let typingUsers: [TypingUser]

    var body: some View {
        if !typingUsers.isEmpty {
            HStack(spacing: 4) {
                TypingDotsView()
                Text(typingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var typingText: String {
        switch typingUsers.count {
        case 1:
            return "\(typingUsers[0].displayName) is typing..."
        case 2:
            return "\(typingUsers[0].displayName) and \(typingUsers[1].displayName) are typing..."
        default:
            return "Several people are typing..."
        }
    }
}

struct TypingDotsView: View {
    @State private var animatingDot = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .opacity(animatingDot == index ? 1.0 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                animatingDot = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                    animatingDot = 2
                }
            }
        }
    }
}
