import SwiftUI

struct ThreadReplyBanner: View {
    let originalContent: String
    let originalSenderName: String
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(originalSenderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(originalContent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }
}

struct InlineReplyPreview: View {
    let content: String
    let senderName: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(senderName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(content)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}
