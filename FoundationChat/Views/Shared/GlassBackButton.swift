import SwiftUI

struct GlassBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Color(hex: 0x101828))
                .frame(width: 72, height: 72)
                .background(Color.white.opacity(0.92), in: Circle())
                .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

#Preview {
    GlassBackButton {}
        .padding()
        .background(Color(hex: 0xF6F7FB))
}
