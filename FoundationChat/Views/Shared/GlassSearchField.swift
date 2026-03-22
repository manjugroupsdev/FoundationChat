import SwiftUI

struct GlassSearchField: View {
  let placeholder: String
  @Binding var text: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField(placeholder, text: $text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

#Preview {
  @Previewable @State var text = ""
  VStack {
    GlassSearchField(placeholder: "Search", text: $text)
      .padding()
  }
}
