import SwiftUI

extension View {
    func appLibraryNativeSheet(_ detents: Set<PresentationDetent>) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
    }
}
