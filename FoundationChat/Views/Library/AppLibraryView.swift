import SwiftUI

/// Native iOS counterpart to Android `AppLibraryFragment`: sticky blue header,
/// filter pills, and section cards with module rows.
struct AppLibraryView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var selectedFilter: AppLibraryFilter = .all
    @State private var listDidAppear = false
    @State private var navDidAppear = false
    @State private var isRefreshingPermissions = false

    private var visibleSections: [AppLibrarySection] {
        AppLibrarySection.makeSections(authStore: authStore)
        .filter { selectedFilter == .all || $0.filter == selectedFilter }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                appHeaderTopFill

                VStack(spacing: 0) {
                    header
                        .zIndex(1)

                    AppLibraryLoadingStrip(isLoading: isRefreshingPermissions)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 24) {
                            appSections
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 120)
                    }
                    .refreshable {
                        await refreshPermissions()
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await refreshPermissions()
            }
            .onAppear {
                restartEntranceAnimation()
            }
            .onChange(of: selectedFilter) { _, _ in
                listDidAppear = false
                withAnimation(.easeOut(duration: 0.18)) {
                    listDidAppear = true
                }
            }
        }
    }

    private var appSections: some View {
        ForEach(Array(visibleSections.enumerated()), id: \.element.id) { index, section in
            AppLibraryTableSection(section: section)
                .opacity(listDidAppear ? 1 : 0)
                .offset(y: listDidAppear ? 0 : 22)
                .animation(
                    .spring(response: 0.42, dampingFraction: 0.9)
                        .delay(0.08 + Double(index) * 0.05),
                    value: listDidAppear
                )
        }
    }

    private var appHeaderTopFill: some View {
        Color(hex: 0x0B61CA)
            .frame(height: 150)
            .frame(maxWidth: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
    }

    private func restartEntranceAnimation() {
        listDidAppear = false
        navDidAppear = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(25))
            withAnimation(.easeOut(duration: 0.22)) {
                listDidAppear = true
                navDidAppear = true
            }
        }
    }

    @MainActor
    private func refreshPermissions() async {
        isRefreshingPermissions = true
        defer { isRefreshingPermissions = false }
        await authStore.refreshIAMPermissions()
    }

    private var header: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color(hex: 0x0B61CA), Color(hex: 0x02499D)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("App Library")
                            .font(AppModuleFont.screenTitle)
                            .foregroundStyle(.white)

                        Text("Everything grouped for quick access")
                            .font(AppModuleFont.rowBody)
                            .foregroundStyle(Color(hex: 0xD9D6FE))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: 234, alignment: .leading)

                    Spacer(minLength: 8)

                    Image("AppLibraryIconAppsHeader")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 119, height: 89)
                }
                .padding(.top, 71)
                .padding(.horizontal, 24)
            }
            .frame(height: 161)

            AppLibraryFilterStrip(selectedFilter: $selectedFilter)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .background(Color(.systemGroupedBackground))
                .opacity(navDidAppear ? 1 : 0)
                .offset(y: navDidAppear ? 0 : 18)
                .animation(.spring(response: 0.38, dampingFraction: 0.86).delay(0.06), value: navDidAppear)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct AppLibraryLoadingStrip: View {
    let isLoading: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(.systemGroupedBackground))

            if isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color(hex: 0x0B61CA))
                    .transition(.opacity)
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.18), value: isLoading)
    }
}

private struct AppLibraryTableSection: View {
    let section: AppLibrarySection

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(section.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x111111))

                    Text(section.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x6B7280))
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        item.destination.view
                    } label: {
                        NativeAppLibraryRow(item: item)
                    }
                    .buttonStyle(.plain)

                    if index != section.items.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
    }
}

private struct NativeAppLibraryRow: View {
    let item: AppLibraryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x111111))

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private enum AppLibraryFilter: String, CaseIterable, Identifiable {
    case all, hr, marketing, project, land, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Apps"
        case .hr: return "HR"
        case .marketing: return "Marketing"
        case .project: return "Project"
        case .land: return "Land"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .all: return "AppLibraryIconAppsPillAll"
        case .hr: return "AppLibraryIconAppsPillHr"
        case .marketing: return "AppLibraryIconAppsPillMarketing"
        case .project: return "AppLibraryIconAppsPillProject"
        case .land: return "AppLibraryIconAppsPillProject"
        case .settings: return "AppLibraryIconAppsPillSettings"
        }
    }

    var systemIcon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .hr: return "person"
        case .marketing: return "megaphone"
        case .project: return "folder"
        case .land: return "map"
        case .settings: return "gearshape"
        }
    }

    var selectedSystemIcon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .hr: return "person.fill"
        case .marketing: return "megaphone.fill"
        case .project: return "folder.fill"
        case .land: return "map.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

private struct AppLibrarySection: Identifiable {
    let id: String
    let filter: AppLibraryFilter
    let title: String
    let subtitle: String
    let icon: String
    let items: [AppLibraryItem]

    static func makeSections(authStore: AuthStore) -> [AppLibrarySection] {
        func canAny(_ permissions: [String]) -> Bool {
            permissions.isEmpty || permissions.contains { authStore.hasPermission($0) }
        }

        let hrItems: [AppLibraryItem] = [
            canAny(["attendance.view", "attendance.viewAll"])
                ? .init(title: "Attendance", icon: "AppLibraryIconAppsAttendance", destination: .attendance)
                : nil,
            canAny(["leaves.view", "leaves.viewAll", "leaves.approve"])
                ? .init(title: "Leave", icon: "AppLibraryIconAppsLeave", destination: .leave)
                : nil,
            canAny(["permissions.view", "permissions.viewAll", "permissions.approve"])
                ? .init(title: "Permissions", icon: "AppLibraryIconAppsPermissions", destination: .permissions)
                : nil,
            canAny(["loans.view", "loans.manage", "loans.approve"])
                ? .init(title: "Loans", icon: "AppLibraryIconAppsLoans", destination: .loans)
                : nil,
            canAny(["attendance.approve", "attendance.viewAll"])
                ? .init(title: "Attendance Approvals", icon: "AppLibraryIconAppsAttendance", destination: .attendanceReview)
                : nil
        ].compactMap(\.self)

        let marketingItems: [AppLibraryItem] = [
            canAny(["marketing.cpVisits.view", "cpvisits.view", "sitevisits.view", "marketing.view"])
                ? .init(title: "CP Visits", icon: "AppLibraryIconAppsDealer", destination: .cpVisits)
                : nil,
            canAny(["marketing.siteVisits.view", "sitevisits.view", "marketing.view"])
                ? .init(title: "Site Visits", icon: "AppLibraryIconAppsFieldVisits", destination: .siteVisits)
                : nil,
            canAny(["telecaller.leads.view", "leads.view", "marketing.view"])
                ? .init(title: "Leads", icon: "AppLibraryIconAppsLeads", destination: .leads)
                : nil,
            canAny(["telecaller.dialer.view", "dialer.view", "marketing.view"])
                ? .init(title: "Dialer", icon: "AppLibraryIconAppsLeads", destination: .dialer)
                : nil,
            canAny(["projects.view", "marketing.inventory.view", "inventory.view", "marketing.view"])
                ? .init(title: "Inventory", icon: "AppLibraryIconAppsFieldVisits", destination: .inventory)
                : nil,
            canAny(["marketing.bookings.create", "bookings.view", "marketing.view"])
                ? .init(title: "Booking", icon: "AppLibraryIconAppsDealer", destination: .bookings)
                : nil
        ].compactMap(\.self)

        let projectItems: [AppLibraryItem] = [
            canAny(["tasks.view", "projects.tasks.view", "projects.view"])
                ? .init(title: "Tasks", icon: "AppLibraryIconAppsTasks", destination: .tasks)
                : nil,
            canAny(["projects.expenses.view", "expenses.view", "projects.view"])
                ? .init(title: "Expenses", icon: "AppLibraryIconAppsLoans", destination: .expenses)
                : nil
        ].compactMap(\.self)

        let landItems: [AppLibraryItem] = [
            canAny(["land.inspection.view", "land.view"])
                ? .init(title: "Inspection", icon: "AppLibraryIconAppsFieldVisits", destination: .landInspection)
                : nil,
            canAny(["land.queries.view", "land.view"])
                ? .init(title: "Queries", icon: "AppLibraryIconAppsLeads", destination: .landQueries)
                : nil
        ].compactMap(\.self)

        let settingsItems: [AppLibraryItem] = [
            AppLibraryItem(title: "Profile", icon: "AppLibraryIconAppsSettingsCard", destination: .settings)
        ]

        return [
            .init(
                id: "hr",
                filter: .hr,
                title: "HR",
                subtitle: "People • Policies • Operations",
                icon: "AppLibraryIconAppsCatHr",
                items: hrItems
            ),
            .init(
                id: "marketing",
                filter: .marketing,
                title: "Marketing",
                subtitle: "Growth • Campaigns • Reports",
                icon: "AppLibraryIconAppsCatMarketing",
                items: marketingItems
            ),
            .init(
                id: "project",
                filter: .project,
                title: "Project",
                subtitle: "Projects • Tasks • Expenses",
                icon: "AppLibraryIconAppsCatPm",
                items: projectItems
            ),
            .init(
                id: "land",
                filter: .land,
                title: "Land",
                subtitle: "Inspection • Queries",
                icon: "AppLibraryIconAppsCatMarketing",
                items: landItems
            ),
            .init(
                id: "configuration",
                filter: .settings,
                title: "Settings",
                subtitle: "Personal Settings",
                icon: "AppLibraryIconAppsCatConfig",
                items: settingsItems
            )
        ].filter { !$0.items.isEmpty }
    }
}

private struct AppLibraryItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let destination: AppLibraryDestination
}

private enum AppLibraryDestination {
    case attendance
    case attendanceReview
    case leave
    case permissions
    case loans
    case siteVisits
    case cpVisits
    case leads
    case dialer
    case inventory
    case bookings
    case tasks
    case expenses
    case landInspection
    case landQueries
    case settings

    @ViewBuilder
    var view: some View {
        switch self {
        case .attendance:
            ConvexAttendanceListView()
        case .attendanceReview:
            AttendanceReviewView()
        case .leave:
            LeavesListView()
        case .permissions:
            ConvexPermissionListView()
        case .loans:
            LoansView()
        case .siteVisits:
            SiteVisitsView()
        case .cpVisits:
            CpVisitsView()
        case .leads:
            MyLeadsView()
        case .dialer:
            DialerView()
        case .inventory:
            InventoryProjectsListView()
        case .bookings:
            BookingsListView()
        case .tasks:
            TasksListView()
        case .expenses:
            ProjectExpensesView()
        case .landInspection:
            LandInspectionView()
        case .landQueries:
            LandQueriesView()
        case .settings:
            ProfileView()
        }
    }
}

private struct AppLibraryFilterStrip: View {
    @Binding var selectedFilter: AppLibraryFilter

    private var selectedIndex: Int {
        AppLibraryFilter.allCases.firstIndex(of: selectedFilter) ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            let tabWidth = proxy.size.width / CGFloat(AppLibraryFilter.allCases.count)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .fill(Color.white.opacity(0.78))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .stroke(Color.white.opacity(0.85), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
                    .frame(width: tabWidth - 8, height: 58)
                    .offset(x: CGFloat(selectedIndex) * tabWidth + 4)
                    .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.08), value: selectedFilter)

                HStack(spacing: 0) {
                    ForEach(AppLibraryFilter.allCases) { filter in
                        Button {
                            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.08)) {
                                selectedFilter = filter
                            }
                        } label: {
                            AppLibraryFilterTab(filter: filter, isSelected: selectedFilter == filter)
                                .frame(width: tabWidth, height: 64)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(AppLibraryTabButtonStyle())
                        .accessibilityLabel(filter.title)
                        .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
                    }
                }
            }
        }
        .frame(height: 70)
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.74))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 3)
        .padding(.horizontal, 6)
        .sensoryFeedback(.selection, trigger: selectedFilter)
    }
}

private struct AppLibraryFilterTab: View {
    let filter: AppLibraryFilter
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: isSelected ? filter.selectedSystemIcon : filter.systemIcon)
                .font(.system(size: 21, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0x1D1D1F))
                .frame(height: 25)

            Text(filter.title)
                .font(isSelected ? AppModuleFont.rowMetaSemibold : AppModuleFont.tabLabel)
                .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0x1D1D1F))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }
}

private struct AppLibraryTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    AppLibraryView()
        .environment(AuthStore())
}
