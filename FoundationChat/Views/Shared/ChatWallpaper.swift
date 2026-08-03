import SwiftUI

/// Original low-contrast business-chat wallpaper generated for M-Connect.
/// `ImagePaint` repeats the seamless tile instead of stretching it, keeping
/// the doodles at a comfortable size on every iPhone and iPad.
struct ChatWallpaper: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      backgroundColor

      Rectangle()
        .fill(
          ImagePaint(
            image: Image("ChatDoodleWallpaper"),
            sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            scale: 0.42
          )
        )
        .opacity(colorScheme == .dark ? 0.16 : 0.92)

      if colorScheme == .dark {
        Color.black.opacity(0.52)
      }
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private var backgroundColor: Color {
    colorScheme == .dark
      ? Color(red: 0.055, green: 0.070, blue: 0.065)
      : Color(red: 0.965, green: 0.945, blue: 0.910)
  }
}
