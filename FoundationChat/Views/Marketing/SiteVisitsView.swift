import SwiftUI

/// Marketing "Site Visits" entry from the App Library. Forwards to the full
/// `SiteVisitsListView` (status filter + search + ±30-day window).
struct SiteVisitsView: View {
    var body: some View {
        SiteVisitsListView()
    }
}

#Preview {
    NavigationStack {
        SiteVisitsView()
    }
    .environment(AuthStore())
}
