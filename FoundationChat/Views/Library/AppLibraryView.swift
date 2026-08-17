import SwiftUI

/// Native iOS counterpart to Android `AppLibraryFragment`: sticky blue header,
/// filter pills, and section cards with module rows.
struct AppLibraryView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var selectedFilter: AppLibraryFilter = .all
    @State private var listDidAppear = false
    @State private var navDidAppear = false
    @State private var isRefreshingPermissions = false

    private var sections: [AppLibrarySection] {
        AppLibrarySection.makeSections(authStore: authStore)
    }

    private var availableFilters: [AppLibraryFilter] {
        let representedFilters = Set(sections.map(\.filter))
        return [.all] + AppLibraryFilter.allCases.filter {
            $0 != .all && representedFilters.contains($0)
        }
    }

    private var visibleSections: [AppLibrarySection] {
        sections.filter { selectedFilter == .all || $0.filter == selectedFilter }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Blue base fills the top safe area (status-bar strip) so there is
                // no white gap above the header. The grey page background is kept
                // OUT of the top safe area so it can't repaint the status bar white.
                Color(hex: 0x0B61CA)
                    .ignoresSafeArea(edges: .top)

                Color(.systemGroupedBackground)
                    .ignoresSafeArea(edges: .bottom)

                appHeaderTopFill

                headerHero

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 145)

                        scrollingPanel
                    }
                }
                .refreshable {
                    await refreshLibraryPresentation()
                }
                .ignoresSafeArea(edges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
            .onChange(of: availableFilters) { _, filters in
                if !filters.contains(selectedFilter) {
                    selectedFilter = .all
                }
            }
        }
        .background(AppLibraryStatusBarStyle(style: .lightContent))
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
            .frame(height: 172)
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
    private func refreshLibraryPresentation() async {
        restartEntranceAnimation()
        try? await Task.sleep(for: .milliseconds(600))
    }

    @MainActor
    private func refreshPermissions() async {
        guard !isRefreshingPermissions else { return }
        isRefreshingPermissions = true
        defer { isRefreshingPermissions = false }
        await authStore.refreshIAMPermissions()
        if !availableFilters.contains(selectedFilter) {
            selectedFilter = .all
        }
    }

    private var headerHero: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x02499D)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("App Library")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Everything grouped for quick access")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color(hex: 0xD9D6FE))
                        .lineLimit(2)
                }
                .frame(maxWidth: 268, alignment: .leading)
                .offset(y: -22)

                Spacer(minLength: 8)

                Image("AppLibraryIconAppsHeader")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 88)
                    .padding(.top, -36)
            }
            .padding(.top, 80)
            .padding(.horizontal, 28)
        }
        .frame(height: 168)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private var scrollingPanel: some View {
        VStack(spacing: 0) {
            AppLibraryFilterStrip(
                selectedFilter: $selectedFilter,
                filters: availableFilters
            )
                .opacity(navDidAppear ? 1 : 0)
                .offset(y: navDidAppear ? 0 : 18)
                .animation(.spring(response: 0.38, dampingFraction: 0.86).delay(0.06), value: navDidAppear)

            AppLibraryLoadingStrip(isLoading: isRefreshingPermissions)

            LazyVStack(spacing: 24) {
                appSections
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 120)
        }
        .background(Color(.systemGroupedBackground))
        .clipShape(.rect(topLeadingRadius: 36, topTrailingRadius: 36))
    }
}

private struct AppLibraryLoadingStrip: View {
    let isLoading: Bool

    var body: some View {
        Color.clear
            .frame(height: 0)
    }
}

private struct AppLibraryTableSection: View {
    let section: AppLibrarySection

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                LibraryIconView(
                    icon: section.icon,
                    systemIcon: section.systemIcon,
                    foreground: section.iconTint,
                    background: section.iconBackground,
                    size: 40,
                    symbolSize: 20
                )

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
                    if item.isComingSoon {
                        NativeAppLibraryRow(item: item)
                            .opacity(0.9)
                    } else {
                        NavigationLink {
                            item.destination.view
                        } label: {
                            NativeAppLibraryRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }

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
            rowIcon

            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x111111))

            Spacer(minLength: 8)

            if item.isComingSoon {
                Text("Coming soon")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xB54708))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color(hex: 0xFEF0C7), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: 0xFEDF89), lineWidth: 1)
                    )
            } else {
                Image(systemName: "chevron.right")
                    .font(AppModuleFont.rowMetaSemibold)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var rowIcon: some View {
        LibraryIconView(
            icon: item.icon,
            systemIcon: item.systemIcon,
            foreground: item.iconTint ?? Color(hex: 0x0B61CA),
            background: item.iconBackground ?? Color(hex: 0xEAF4FF),
            size: 32,
            symbolSize: 17
        )
    }
}

private struct LibraryIconView: View {
    let icon: String
    let systemIcon: String?
    let foreground: Color
    let background: Color?
    let size: CGFloat
    let symbolSize: CGFloat

    var body: some View {
        if let symbol = systemIcon ?? sfSymbol {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background((background ?? foreground.opacity(0.12)), in: Circle())
        } else {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }

    private var sfSymbol: String? {
        icon.hasPrefix("sf:") ? String(icon.dropFirst(3)) : nil
    }
}

private enum AppLibraryFilter: String, CaseIterable, Identifiable {
    case all, taskManager, hr, marketing, project, land, fleet, sales, accounts, frontDesk, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Apps"
        case .taskManager: return "Tasks"
        case .hr: return "HR"
        case .marketing: return "Marketing"
        case .project: return "Project"
        case .land: return "Land"
        case .fleet: return "Fleet"
        case .sales: return "Post Sales"
        case .accounts: return "Accounts"
        case .frontDesk: return "Front Desk"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .all: return "AppLibraryIconAppsPillAll"
        case .taskManager: return "AppLibraryIconAppsTasks"
        case .hr: return "AppLibraryIconAppsPillHr"
        case .marketing: return "AppLibraryIconAppsPillMarketing"
        case .project: return "AppLibraryIconAppsPillProject"
        case .land: return "AppLibraryIconAppsPillProject"
        case .fleet: return "AppLibraryIconAppsPillProject"
        case .sales: return "AppLibraryIconAppsPillMarketing"
        case .accounts: return "AppLibraryIconAppsPillSettings"
        case .frontDesk: return "AppLibraryIconAppsPillSettings"
        case .settings: return "AppLibraryIconAppsPillSettings"
        }
    }

    var systemIcon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .taskManager: return "checklist"
        case .hr: return "person"
        case .marketing: return "megaphone"
        case .project: return "folder"
        case .land: return "map"
        case .fleet: return "car"
        case .sales: return "creditcard"
        case .accounts: return "checkmark.seal"
        case .frontDesk: return "qrcode.viewfinder"
        case .settings: return "gearshape"
        }
    }

    var selectedSystemIcon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .taskManager: return "checklist.checked"
        case .hr: return "person.fill"
        case .marketing: return "megaphone.fill"
        case .project: return "folder.fill"
        case .land: return "map.fill"
        case .fleet: return "car.fill"
        case .sales: return "creditcard.fill"
        case .accounts: return "checkmark.seal.fill"
        case .frontDesk: return "qrcode.viewfinder"
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
    var systemIcon: String? = nil
    var iconTint: Color = Color(hex: 0x0B61CA)
    var iconBackground: Color? = nil
    let items: [AppLibraryItem]

    static func makeSections(authStore: AuthStore) -> [AppLibrarySection] {
        func canAny(_ permissions: [String]) -> Bool {
            permissions.isEmpty || permissions.contains { authStore.hasPermission($0) }
        }

        let normalizedDesignation = authStore.currentSession?.user.designation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let isTelesalesRestricted = normalizedDesignation.contains("lead management executive")
            || normalizedDesignation.contains("telesales")

        let hrItems: [AppLibraryItem] = [
            canAny(["attendance.view", "attendance.viewAll"])
                ? .init(title: "Attendance", icon: "AppLibraryIconAppsAttendance", destination: .attendance)
                : nil,
            canAny(["fines.viewOwn", "fines.view"])
                ? .init(
                    title: "Fines & Deductions",
                    icon: "sf:scalemass",
                    destination: .fines,
                    systemIcon: "scalemass",
                    iconTint: Color(hex: 0x0B61CA),
                    iconBackground: Color(hex: 0xEAF4FF)
                )
                : nil,
            canAny(["leaves.view", "leaves.viewAll", "leaves.approve"])
                ? .init(title: "Leave", icon: "AppLibraryIconAppsLeave", destination: .leave)
                : nil,
            canAny(["permissions.view", "permissions.viewAll", "permissions.approve"])
                ? .init(title: "Permissions", icon: "AppLibraryIconAppsPermissions", destination: .permissions)
                : nil,
            canAny(["loans.view", "loans.manage", "loans.approve"])
                ? .init(title: "Loans", icon: "AppLibraryIconAppsLoans", destination: .loans)
                : nil
        ].compactMap(\.self)

        let taskManagerItems: [AppLibraryItem] = [
            canAny(["dailyTasks.view", "dailyTasks.viewAll", "dailyTasks.create"])
                ? .init(
                    title: "Task Manager",
                    icon: "AppLibraryIconAppsTasks",
                    destination: .taskManager,
                    systemIcon: "checklist",
                    iconTint: Color(hex: 0x0891B2),
                    iconBackground: Color(hex: 0xE0F7FA)
                )
                : nil
        ].compactMap(\.self)

        let marketingItems: [AppLibraryItem] = [
            canAny(["marketing.cpVisits.view"])
                ? .init(title: "CP Visits", icon: "AppLibraryIconAppsDealer", destination: .cpVisits)
                : nil,
            canAny(["marketing.siteVisits.view"])
                ? .init(title: "Site Visits", icon: "AppLibraryIconAppsFieldVisits", destination: .siteVisits)
                : nil,
            canAny(["telecaller.externalLeads.viewOwn", "telecaller.externalLeads.viewAll"])
                ? .init(title: "Leads", icon: "AppLibraryIconAppsLeads", destination: .leads)
                : nil,
            canAny(["telecaller.dashboard", "telecaller.calls"])
                ? .init(title: "Dialer", icon: "AppLibraryIconAppsLeads", destination: .dialer)
                : nil,
            canAny(["projects.view"])
                ? .init(title: "Inventory", icon: "AppLibraryIconAppsFieldVisits", destination: .inventory)
                : nil,
            canAny(["marketing.bookings.view", "marketing.bookings.create"])
                ? .init(title: "Booking", icon: "AppLibraryIconAppsDealer", destination: .bookings)
                : nil
        ].compactMap(\.self)

        let projectItems: [AppLibraryItem] = [
            canAny(["tasks.view", "tasks.viewAll", "tasks.create"])
                ? .init(title: "Tasks", icon: "AppLibraryIconAppsTasks", destination: .projectTasks)
                : nil,
            canAny(["projects.view"])
                ? .init(
                    title: "Daily Log",
                    icon: "sf:doc.text.magnifyingglass",
                    destination: .dailyLog,
                    systemIcon: "doc.text.magnifyingglass",
                    iconTint: Color(hex: 0x16A34A),
                    iconBackground: Color(hex: 0xDCFCE7)
                )
                : nil,
            canAny(["projects.view"])
                ? .init(
                    title: "Issues",
                    icon: "sf:questionmark.bubble",
                    destination: .issues,
                    systemIcon: "questionmark.bubble",
                    iconTint: Color(hex: 0x16A34A),
                    iconBackground: Color(hex: 0xDCFCE7)
                )
                : nil,
            canAny(["projects.expenses.view", "projects.expenses.create", "projects.expenses.approve"])
                ? .init(
                    title: "Expenses",
                    icon: "AppLibraryIconAppsLoans",
                    destination: .expenses,
                    systemIcon: "indianrupeesign.circle",
                    iconTint: Color(hex: 0x16A34A),
                    iconBackground: Color(hex: 0xDCFCE7)
                )
                : nil
        ].compactMap(\.self)

        let landItems: [AppLibraryItem] = [
            canAny(["land.inspect", "land.inspection.view", "land.inspection.edit", "land.view"])
                ? .init(
                    title: "Inspection",
                    icon: "AppLibraryIconAppsFieldVisits",
                    destination: .landInspection,
                    systemIcon: "doc.text.magnifyingglass",
                    iconTint: Color(hex: 0xE401B3),
                    iconBackground: Color(hex: 0xFFE8FC)
                )
                : nil,
            canAny(["land.view", "land.inspect", "land.inspection.view"])
                ? .init(
                    title: "Queries",
                    icon: "AppLibraryIconAppsLeads",
                    destination: .landQueries,
                    systemIcon: "questionmark.bubble",
                    iconTint: Color(hex: 0xE401B3),
                    iconBackground: Color(hex: 0xFFE8FC)
                )
                : nil
        ].compactMap(\.self)

        // Fleet Management. Mirrors Android AppLibraryFragment: only the
        // "My Trips" tile is surfaced to staff, gated on canViewFleetMyTrips
        // (drivers by roster, super-admins, or marketing.fleet.myTrips.view).
        // The agency-only Admin Fleet portal is deliberately NOT listed —
        // every screen inside it authenticates agency tokens only, so a staff
        // token 401s and trips the forced-logout watchdog.
        let fleetItems: [AppLibraryItem] = [
            authStore.currentSession?.user.canViewFleetMyTrips == true
                ? .init(
                    title: "My Trips",
                    icon: "AppLibraryIconAppsFieldVisits",
                    destination: .fleetMyTrips,
                    systemIcon: "car",
                    iconTint: Color(hex: 0x0B61CA),
                    iconBackground: Color(hex: 0xEAF4FF)
                )
                : nil
        ].compactMap(\.self)

        let salesItems: [AppLibraryItem] = [
            canAny(["postSales.collections.create"])
                ? .init(
                    title: "Collections",
                    icon: "AppLibraryIconAppsLoans",
                    destination: .collections,
                    systemIcon: "creditcard",
                    iconTint: Color(hex: 0xD01784),
                    iconBackground: Color(hex: 0xFCE7F3)
                )
                : nil,
            canAny(["postSales.loanDesk.manage"])
                ? .init(
                    title: "Loan Desk",
                    icon: "AppLibraryIconAppsLoans",
                    destination: .loanDesk,
                    systemIcon: "indianrupeesign.circle",
                    iconTint: Color(hex: 0xD01784),
                    iconBackground: Color(hex: 0xFCE7F3)
                )
                : nil
        ].compactMap(\.self)

        let accountsItems: [AppLibraryItem] = [
            !isTelesalesRestricted && canAny(["accounts.requests.view", "postSales.accounts.verify"])
                ? .init(
                    title: "Post Sales Verification",
                    icon: "AppLibraryIconAppsSettingsCard",
                    destination: .postSalesVerification,
                    systemIcon: "checkmark.seal",
                    iconTint: Color(hex: 0x1F2937),
                    iconBackground: Color(hex: 0xE2E8F0)
                )
                : nil
        ].compactMap(\.self)

        let frontDeskItems: [AppLibraryItem] = [
            // Mirrors Android AppLibraryFragment: field-marketing staff who scan
            // consulting QR codes reach the scanner via the marketing.siteVisits.*
            // keys, not just the frontdesk.* set.
            canAny([
                "frontdesk.view", "frontdesk.checkin", "frontdesk.invite",
                "marketing.siteVisits.view", "marketing.siteVisits.viewTeam",
                "marketing.siteVisits.viewAll", "marketing.siteVisits.scanConsulting"
            ])
                ? .init(
                    title: "QR Scanner",
                    icon: "sf:qrcode.viewfinder",
                    destination: .qrScanner,
                    systemIcon: "qrcode.viewfinder",
                    iconTint: Color(hex: 0x6D28D9),
                    iconBackground: Color(hex: 0xEDE9FE)
                )
                : nil
        ].compactMap(\.self)

        let settingsItems: [AppLibraryItem] = [
            AppLibraryItem(title: "Settings", icon: "AppLibraryIconAppsSettingsCard", destination: .settings)
        ]

        return [
            .init(
                id: "taskManager",
                filter: .taskManager,
                title: "Task Manager",
                subtitle: "Tasks • Followups",
                icon: "AppLibraryIconAppsCatPm",
                systemIcon: "checklist",
                iconTint: Color(hex: 0x0891B2),
                iconBackground: Color(hex: 0xE0F7FA),
                items: taskManagerItems
            ),
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
                title: "Project Management",
                subtitle: "Tasks • Daily Log • Issues • Expenses",
                icon: "AppLibraryIconAppsCatPm",
                systemIcon: "folder.badge.gearshape",
                iconTint: Color(hex: 0x16A34A),
                iconBackground: Color(hex: 0xDCFCE7),
                items: projectItems
            ),
            .init(
                id: "land",
                filter: .land,
                title: "Land Procurement",
                subtitle: "Inspection • Queries",
                icon: "AppLibraryIconAppsCatMarketing",
                systemIcon: "map",
                iconTint: Color(hex: 0xE401B3),
                iconBackground: Color(hex: 0xFFE8FC),
                items: landItems
            ),
            .init(
                id: "fleet",
                filter: .fleet,
                title: "Fleet Management",
                subtitle: "My Trips",
                icon: "AppLibraryIconAppsCatMarketing",
                systemIcon: "car.fill",
                iconTint: Color(hex: 0x0B61CA),
                iconBackground: Color(hex: 0xEAF4FF),
                items: fleetItems
            ),
            .init(
                id: "sales",
                filter: .sales,
                title: "Post Sales",
                subtitle: "Post Sales • Collections",
                icon: "AppLibraryIconAppsCatMarketing",
                systemIcon: "megaphone",
                iconTint: Color(hex: 0xD01784),
                iconBackground: Color(hex: 0xFCE7F3),
                items: salesItems
            ),
            .init(
                id: "accounts",
                filter: .accounts,
                title: "Accounts",
                subtitle: "Verification • Approvals",
                icon: "AppLibraryIconAppsCatConfig",
                systemIcon: "checkmark.seal.fill",
                iconTint: Color(hex: 0x1F2937),
                iconBackground: Color(hex: 0xE2E8F0),
                items: accountsItems
            ),
            .init(
                id: "frontDesk",
                filter: .frontDesk,
                title: "Front Desk",
                subtitle: "Visitor Entry • Scanning",
                icon: "AppLibraryIconAppsCatConfig",
                systemIcon: "person.crop.rectangle",
                iconTint: Color(hex: 0x7C3AED),
                iconBackground: Color(hex: 0xF3E8FF),
                items: frontDeskItems
            ),
            .init(
                id: "configuration",
                filter: .settings,
                title: "Configuration",
                subtitle: "Settings",
                icon: "AppLibraryIconAppsCatConfig",
                items: settingsItems
            )
        ].filter { !$0.items.isEmpty }
    }
}

private struct AppLibraryItem: Identifiable {
    let title: String
    let icon: String
    let destination: AppLibraryDestination
    var systemIcon: String? = nil
    var iconTint: Color? = nil
    var iconBackground: Color? = nil
    var isComingSoon = false

    var id: String { destination.rawValue }
}

private enum AppLibraryDestination: String {
    case attendance
    case fines
    case leave
    case permissions
    case loans
    case siteVisits
    case cpVisits
    case leads
    case dialer
    case inventory
    case bookings
    case taskManager
    case projectTasks
    case dailyLog
    case issues
    case expenses
    case landInspection
    case landQueries
    case fleetMyTrips
    case collections
    case loanDesk
    case postSalesVerification
    case qrScanner
    case settings

    @ViewBuilder
    var view: some View {
        Group {
            switch self {
            case .attendance:
                ConvexAttendanceListView()
            case .fines:
                FinesDeductionsView()
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
            case .taskManager:
                TasksListView()
            case .projectTasks:
                ProjectTasksView()
            case .dailyLog:
                ProjectDailyLogView()
            case .issues:
                IssuesView()
            case .expenses:
                ProjectExpensesView()
            case .landInspection:
                LandInspectionView()
            case .landQueries:
                LandQueriesView()
            case .fleetMyTrips:
                FleetMyTripsView()
            case .collections:
                CollectionsView()
            case .loanDesk:
                LoanDeskView()
            case .postSalesVerification:
                AccountsCollectionsReviewView()
            case .qrScanner:
                FrontDeskQRScannerView()
            case .settings:
                ProfileView()
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct AppLibraryFilterStrip: View {
    @Binding var selectedFilter: AppLibraryFilter
    let filters: [AppLibraryFilter]

    var body: some View {
        GeometryReader { geometry in
            let tabWidth = max(
                78,
                (geometry.size.width - 12) / CGFloat(max(min(filters.count, 5), 1))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { proxy in
                    HStack(spacing: 0) {
                        ForEach(filters) { filter in
                            Button {
                                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.08)) {
                                    selectedFilter = filter
                                    proxy.scrollTo(filter.id, anchor: .center)
                                }
                            } label: {
                                AppLibraryFilterTab(filter: filter, isSelected: selectedFilter == filter)
                                    .frame(width: tabWidth, height: 76)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(AppLibraryTabButtonStyle())
                            .accessibilityLabel(filter.title)
                            .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
                            .id(filter.id)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
        .frame(height: 84)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .sensoryFeedback(.selection, trigger: selectedFilter)
    }
}

private struct AppLibraryFilterTab: View {
    let filter: AppLibraryFilter
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: isSelected ? filter.selectedSystemIcon : filter.systemIcon)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? .white : Color(hex: 0x6A6D78))
                .frame(width: 36, height: 36)
                .background(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0xF4F6F8), in: Circle())

            Text(filter.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0x667085))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.top, 1)

            Capsule()
                .fill(isSelected ? Color(hex: 0x0B61CA) : Color.clear)
                .frame(width: 24, height: 2)
                .padding(.top, 3)
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

private struct AppLibraryStatusBarStyle: UIViewControllerRepresentable {
    let style: UIStatusBarStyle

    func makeUIViewController(context: Context) -> Controller {
        Controller(style: style)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.style = style
    }

    final class Controller: UIViewController {
        var style: UIStatusBarStyle {
            didSet {
                setNeedsStatusBarAppearanceUpdate()
            }
        }

        init(style: UIStatusBarStyle) {
            self.style = style
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override var preferredStatusBarStyle: UIStatusBarStyle {
            style
        }
    }
}

#Preview {
    AppLibraryView()
        .environment(AuthStore())
}
