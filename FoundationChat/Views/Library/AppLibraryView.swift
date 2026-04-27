import SwiftUI

/// iOS counterpart to the Mconnect `AppLibraryFragment` — a launcher grid of
/// HR / Marketing / Project apps plus Settings. Tapping a tile opens the
/// matching feature screen.
struct AppLibraryView: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section(title: "HR") {
                        AppLibraryTile(
                            icon: "clock.fill",
                            title: "Attendance",
                            tint: .blue
                        ) { ConvexAttendanceListView() }

                        AppLibraryTile(
                            icon: "calendar.badge.minus",
                            title: "Leave",
                            tint: .purple
                        ) { LeavesListView() }

                        AppLibraryTile(
                            icon: "calendar.badge.clock",
                            title: "Permissions",
                            tint: .green
                        ) { ConvexPermissionListView() }

                        AppLibraryTile(
                            icon: "indianrupeesign.circle.fill",
                            title: "Loans",
                            tint: .orange
                        ) {
                            ComingSoonView(
                                title: "Loans",
                                systemImage: "indianrupeesign.circle.fill"
                            )
                        }
                    }

                    section(title: "Marketing") {
                        AppLibraryTile(
                            icon: "mappin.and.ellipse",
                            title: "Site Visits",
                            tint: .teal
                        ) { SiteVisitsView() }

                        AppLibraryTile(
                            icon: "phone.fill",
                            title: "Dialer",
                            tint: .indigo
                        ) { DialerView() }

                        AppLibraryTile(
                            icon: "person.crop.rectangle.stack.fill",
                            title: "My Leads",
                            tint: .pink
                        ) { MyLeadsView() }
                    }

                    section(title: "Projects") {
                        AppLibraryTile(
                            icon: "checklist",
                            title: "Tasks",
                            tint: .mint
                        ) { TasksListView() }
                    }

                    section(title: "Settings") {
                        AppLibraryTile(
                            icon: "person.crop.circle",
                            title: "Profile",
                            tint: .gray
                        ) { ProfileView() }
                    }
                }
                .padding()
            }
            .navigationTitle("Apps")
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                content()
            }
        }
    }
}

/// Single tile in the library grid. Pushes its destination via NavigationLink
/// and renders a tinted SF Symbol over a `.regularMaterial` rounded rectangle.
struct AppLibraryTile<Destination: View>: View {
    let icon: String
    let title: String
    let tint: Color
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AppLibraryView()
        .environment(AuthStore())
}
