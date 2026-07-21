import SwiftUI

extension View {
    func appLibraryNativeSheet(_ detents: Set<PresentationDetent>) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
    }

    /// Lets a modal CTA footer use the lower part of the home-indicator safe area.
    /// Footer buttons should still keep their own compact bottom padding (20 pt).
    func appCompactSheetCTAContainer() -> some View {
        ignoresSafeArea(.container, edges: .bottom)
    }
}
