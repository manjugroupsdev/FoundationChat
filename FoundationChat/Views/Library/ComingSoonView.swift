import SwiftUI

/// Generic "feature in progress" placeholder used by App Library tiles whose
/// destination has not been built on iOS yet (e.g. Loans).
struct ComingSoonView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(
            "Coming Soon",
            systemImage: systemImage,
            description: Text("\(title) will be available in a future update.")
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ComingSoonView(title: "Loans", systemImage: "indianrupeesign.circle.fill")
    }
}
