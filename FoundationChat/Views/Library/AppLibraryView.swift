import SwiftUI

/// Native iOS counterpart to Android `AppLibraryFragment`: keeps the App
/// Library header while presenting the modules as iOS-style grouped tables.
struct AppLibraryView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var selectedFilter: AppLibraryFilter = .all
    @State private var listDidAppear = false
    @State private var navDidAppear = false
    @State private var isRefreshingPermissions = false

    private var visibleSections: [AppLibrarySection] {
        AppLibrarySection.makeSections(
            showsInventory: authStore.hasPermission("projects.view"),
            showsNewBooking: authStore.hasPermission("marketing.bookings.create")
        )
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
        VStack(alignment: .leading, spacing: 7) {
            Text(section.title.uppercased())
                .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

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
                            .padding(.leading, 58)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

        }
    }
}

private struct NativeAppLibraryRow: View {
    let item: AppLibraryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)

            Text(item.title)
                .font(AppModuleFont.rowBody)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

private enum AppLibraryFilter: String, CaseIterable, Identifiable {
    case all, hr, marketing, project, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Apps"
        case .hr: return "HR"
        case .marketing: return "Marketing"
        case .project: return "Project"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .all: return "AppLibraryIconAppsPillAll"
        case .hr: return "AppLibraryIconAppsPillHr"
        case .marketing: return "AppLibraryIconAppsPillMarketing"
        case .project: return "AppLibraryIconAppsPillProject"
        case .settings: return "AppLibraryIconAppsPillSettings"
        }
    }

    var systemIcon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .hr: return "person"
        case .marketing: return "megaphone"
        case .project: return "folder"
        case .settings: return "gearshape"
        }
    }

    var selectedSystemIcon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .hr: return "person.fill"
        case .marketing: return "megaphone.fill"
        case .project: return "folder.fill"
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

    static func makeSections(showsInventory: Bool, showsNewBooking: Bool) -> [AppLibrarySection] {
        var marketingItems: [AppLibraryItem] = [
            .init(title: "CP Visits", icon: "AppLibraryIconAppsDealer", destination: .cpVisits),
            .init(title: "Leads", icon: "AppLibraryIconAppsLeads", destination: .leads),
            .init(title: "Dialer", icon: "AppLibraryIconAppsLeads", destination: .dialer)
        ]
        if showsInventory {
            marketingItems.append(.init(title: "Inventory", icon: "AppLibraryIconAppsFieldVisits", destination: .inventory))
        }
        if showsNewBooking {
            marketingItems.append(.init(title: "New Booking", icon: "AppLibraryIconAppsDealer", destination: .newBooking))
        }

        return [
            .init(
                id: "hr",
                filter: .hr,
                title: "HR",
                subtitle: "People • Policies • Operations",
                icon: "AppLibraryIconAppsCatHr",
                items: [
                    .init(title: "Attendance", icon: "AppLibraryIconAppsAttendance", destination: .attendance),
                    .init(title: "Leave", icon: "AppLibraryIconAppsLeave", destination: .leave),
                    .init(title: "Permissions", icon: "AppLibraryIconAppsPermissions", destination: .permissions),
                    .init(title: "Loans", icon: "AppLibraryIconAppsLoans", destination: .loans)
                ]
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
                subtitle: "Projects • Tasks",
                icon: "AppLibraryIconAppsCatPm",
                items: [
                    .init(title: "Tasks", icon: "AppLibraryIconAppsTasks", destination: .tasks)
                ]
            ),
            .init(
                id: "configuration",
                filter: .settings,
                title: "Configuration",
                subtitle: "Personal Settings • Configuration",
                icon: "AppLibraryIconAppsCatConfig",
                items: [
                    .init(title: "Settings", icon: "AppLibraryIconAppsSettingsCard", destination: .settings)
                ]
            )
        ]
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
    case leave
    case permissions
    case loans
    case cpVisits
    case leads
    case dialer
    case inventory
    case newBooking
    case tasks
    case settings

    @ViewBuilder
    var view: some View {
        switch self {
        case .attendance:
            ConvexAttendanceListView()
        case .leave:
            LeavesListView()
        case .permissions:
            ConvexPermissionListView()
        case .loans:
            LoansView()
        case .cpVisits:
            CpVisitsView()
        case .leads:
            MyLeadsView()
        case .dialer:
            DialerView()
        case .inventory:
            InventoryProjectsListView()
        case .newBooking:
            BookingCreateView()
        case .tasks:
            TasksListView()
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
