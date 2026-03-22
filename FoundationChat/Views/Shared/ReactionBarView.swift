import SwiftUI

struct ReactionBarView: View {
    let reactions: [MessageReactionInfo]
    let onToggleReaction: (String) -> Void
    let onShowPicker: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(reactions) { reaction in
                Button {
                    onToggleReaction(reaction.emoji)
                } label: {
                    HStack(spacing: 3) {
                        Text(reaction.emoji)
                            .font(.caption)
                        Text("\(reaction.count)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(reaction.hasReacted ? Color.accentColor : Color.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        reaction.hasReacted ? Color.accentColor.opacity(0.12) : Color(.systemGray5),
                        in: Capsule()
                    )
                }
            }

            Button {
                onShowPicker()
            } label: {
                Image(systemName: "face.smiling")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5), in: Capsule())
            }
        }
    }
}

struct ReactionPickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let reactions = ["👍", "👎", "❤️", "🎉", "😂", "😢", "🔥", "👏", "🙏", "💯", "👀", "🚀"]

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                ForEach(reactions, id: \.self) { emoji in
                    Button {
                        onSelect(emoji)
                        dismiss()
                    } label: {
                        Text(emoji)
                            .font(.title)
                            .frame(width: 48, height: 48)
                    }
                }
            }
            .padding()
            .navigationTitle("Add Reaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}
