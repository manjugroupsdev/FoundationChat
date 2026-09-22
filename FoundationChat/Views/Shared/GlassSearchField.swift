import SwiftUI

struct GlassSearchField: View {
  let placeholder: String
  @Binding var text: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(Color.appTertiaryText)

      TextField(placeholder, text: $text)
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(Color.appPrimaryText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

      Spacer(minLength: 0)

      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color.appTertiaryText)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 50)
    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.appSeparator, lineWidth: 1)
    )
  }
}

#Preview {
  @Previewable @State var text = ""
  VStack {
    GlassSearchField(placeholder: "Search", text: $text)
      .padding()
  }
}
