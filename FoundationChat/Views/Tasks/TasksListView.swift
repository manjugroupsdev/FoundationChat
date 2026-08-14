import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TasksListView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var tasks: [DailyTask] = []
    @State private var teamIds: Set<String> = []
    @State private var scope: String?
    @State private var moduleLabels: [String: String] = [:]
    @State private var statusFilter: DailyTaskStatusFilter = .all
    @State private var categoryFilter = "All"
    @State private var renderedTaskLimit = 20
    @State private var hasLoadedOnce = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var webLinkTask: DailyTask?
    @State private var selectedRoute: TaskManagerRoute?

    private var todayString: String {
        AppModuleFormatters.ymd.string(from: Date())
    }

    private var currentStaffId: String? {
        authStore.currentSession?.user.staffId?.nonBlank ?? authStore.currentSession?.user._id.nonBlank
    }

    private var isSuperTaskManagerViewer: Bool {
        authStore.isAdmin
            || authStore.currentSession?.user.role?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "super-admin"
    }

    private var metrics: DailyTaskMetrics {
        DailyTaskMetrics(tasks: tasks, teamIds: teamIds, scope: scope, staffId: currentStaffId, todayString: todayString)
    }

    private var categories: [String] {
        let modules = Set(tasks.map(moduleLabel(for:))).sorted()
        return ["All"] + modules
    }

    private var visibleTasks: [DailyTask] {
        tasks
            .filter { statusFilter.matches($0, todayString: todayString) }
            .filter { categoryFilter == "All" || moduleLabel(for: $0) == categoryFilter }
    }

    private var renderedTasks: [DailyTask] {
        Array(visibleTasks.prefix(renderedTaskLimit))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                metricsRow

                TaskFilterSection(title: "STATUS") {
                    ForEach(DailyTaskStatusFilter.allCases) { filter in
                        TaskManagerChip(
                            title: filter.title,
                            count: metrics.count(for: filter),
                            isSelected: statusFilter == filter
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                statusFilter = filter
                                renderedTaskLimit = 20
                            }
                        }
                    }
                }

                TaskFilterSection(title: "CATEGORY") {
                    ForEach(categories, id: \.self) { category in
                        TaskCategoryChip(
                            title: category,
                            isSelected: categoryFilter == category
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                categoryFilter = category
                                renderedTaskLimit = 20
                            }
                        }
                    }
                }

                taskContent
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("Task Manager")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadTasks() }
        .onAppear {
            if hasLoadedOnce {
                Task { await loadTasks() }
            }
        }
        .refreshable { await loadTasks() }
        .sheet(item: $webLinkTask) { task in
            TaskWebLinkSheet(task: task)
                .presentationDetents([.height(300)])
                .presentationBackground(Color.white)
        }
        .navigationDestination(item: $selectedRoute) { route in
            route.view
        }
        .alert("Error", isPresented: errorAlertBinding, actions: {
            Button("OK", role: .cancel) { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var metricsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DailyTaskScopeFilter.allCases) { filter in
                    TaskMetricCard(
                        title: filter.title,
                        value: filter.count(in: metrics),
                        isDanger: filter == .overdue
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var taskContent: some View {
        if isLoading && tasks.isEmpty {
            TaskManagerLoadingSkeleton()
                .padding(.top, 4)
        } else if visibleTasks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checklist.unchecked")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Color(hex: 0x98A2B3))

                Text("Inbox zero")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))

                Text("No tasks match this filter.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 150)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(renderedTasks) { task in
                    DailyTaskManagerCard(
                        task: task,
                        module: moduleLabel(for: task),
                        isOverdue: DailyTaskStatusFilter.isOverdue(task, todayString: todayString),
                        onOpen: { openTask(task) },
                        onComplete: { Task { await updateDailyTaskStatus(task, to: "completed") } },
                        onCancel: { Task { await updateDailyTaskStatus(task, to: "cancelled") } }
                    )
                }

                if renderedTasks.count < visibleTasks.count {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .onAppear(perform: loadMoreTasks)
                }
            }
            .padding(.top, 2)
        }
    }

    private func openTask(_ task: DailyTask) {
        if let route = TaskManagerRoute(task: task) {
            selectedRoute = route
        } else {
            webLinkTask = task
        }
    }

    @MainActor
    private func updateDailyTaskStatus(_ task: DailyTask, to status: String) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            try await TasksConvexAPIService.updateDailyTaskStatus(token: token, id: task.id, status: status)
            await loadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func tasksCacheKey() -> String {
        let staff = currentStaffId?.nonBlank ?? "anon"
        return "tasks.manager.\(staff)"
    }

    private func loadTasks() async {
        guard let token = authStore.currentSession?.token else { return }

        // Cache-first: paint the last-known tasks INSTANTLY so the skeleton only
        // shows on a genuine first load with nothing cached (Android parity).
        if tasks.isEmpty,
           let cached = LocalCache.get(tasksCacheKey(), as: DailyTaskManagerCacheSnapshot.self) {
            let cachedTeamIds = Set(cached.teamIds)
            let scoped = scopedTaskManagerTasks(cached.tasks, teamIds: cachedTeamIds)
                .sorted { ($0.creationTime ?? 0) > ($1.creationTime ?? 0) }
            tasks = scoped
            teamIds = cachedTeamIds
            scope = cached.scope
            moduleLabels = moduleLabelCache(for: scoped)
            renderedTaskLimit = 20
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await TasksConvexAPIService.getTaskManagerTasks(token: token, today: todayString)
            let scoped = scopedTaskManagerTasks(payload.tasks, teamIds: payload.teamIds)
                .sorted { ($0.creationTime ?? 0) > ($1.creationTime ?? 0) }
            tasks = scoped
            teamIds = payload.teamIds
            scope = payload.scope
            moduleLabels = moduleLabelCache(for: scoped)
            renderedTaskLimit = 20
            LocalCache.put(
                tasksCacheKey(),
                DailyTaskManagerCacheSnapshot(tasks: payload.tasks, teamIds: Array(teamIds), scope: scope)
            )
            if !categories.contains(categoryFilter) {
                categoryFilter = "All"
            }
        } catch {
            // Offline-keep: leave the cached/in-memory tasks on screen; only
            // surface an error when there is nothing to show.
            if tasks.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        hasLoadedOnce = true
    }

    private func loadMoreTasks() {
        guard renderedTaskLimit < visibleTasks.count else { return }
        renderedTaskLimit += 20
    }

    private func scopedTaskManagerTasks(_ source: [DailyTask], teamIds: Set<String>) -> [DailyTask] {
        guard !isSuperTaskManagerViewer else { return source }
        guard let staffId = currentStaffId else { return [] }
        return source.filter { task in
            task.assignedTo == staffId || task.assignedTo.map(teamIds.contains) == true
        }
    }

    private func moduleLabelCache(for tasks: [DailyTask]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, computeModuleLabel(for: $0)) })
    }

    private func moduleLabel(for task: DailyTask) -> String {
        if let cached = moduleLabels[task.id] { return cached }
        return computeModuleLabel(for: task)
    }

    private func computeModuleLabel(for task: DailyTask) -> String {
        if let module = task.module?.nonBlank { return module }
        let path = normalizedPath(task.actionUrl)
        let source = task.sourceReferenceType?.lowercased() ?? ""

        if path.hasPrefix("/telecaller") { return "Telecaller" }
        if path.hasPrefix("/marketing/fleet") || path.hasPrefix("/fleet") { return "Fleets" }
        if path.hasPrefix("/marketing") { return "Marketing" }
        if path.hasPrefix("/post-sales") { return "Post Sales" }
        if ["/projects", "/tasks", "/issues", "/library", "/workforce", "/procurement", "/materials", "/purchase-orders", "/vendors", "/equipment", "/assets", "/manpower", "/geotrack"].contains(where: path.hasPrefix) {
            return "Project Management"
        }
        if path.hasPrefix("/land-procurement") { return "Land Procurement" }
        if ["/hr", "/attendance", "/my-team", "/payroll"].contains(where: path.hasPrefix) { return "HR" }
        if path.hasPrefix("/accounts") { return "Accounts" }
        if path.hasPrefix("/finance") || path.hasPrefix("/financials") { return "Finance" }
        if path.hasPrefix("/complaints") { return "CRM" }
        if path.hasPrefix("/settings") { return "Settings" }
        if path.hasPrefix("/task-manager") { return "Task Manager" }

        if ["staff-attendance", "leave", "permission", "work-from-home", "loan", "hiring-request", "onboarding", "staff-asset", "shift_update"].contains(source) {
            return "HR"
        }
        if source.hasPrefix("loan_") { return "Post Sales" }
        if source.contains("booking") { return "Marketing" }
        if source.contains("site_visit") || source == "out_of_station_handoff" || source == "client_place_visit" {
            return "Marketing"
        }
        if source.contains("project") || source.contains("boq") || source == "work-order" || source == "issue" {
            return "Project Management"
        }
        return "Task Manager"
    }

    private func normalizedPath(_ raw: String?) -> String {
        guard let raw = raw?.nonBlank else { return "" }
        let urlPath = URL(string: raw)?.path ?? raw
        return urlPath
            .components(separatedBy: "?").first?
            .components(separatedBy: "#").first?
            .lowercased() ?? ""
    }
}

/// Codable snapshot of the Task Manager list, cached so it paints instantly on
/// the next open and stays visible offline. `teamIds` is stored as an array
/// because `Set` round-trips fine but arrays keep the JSON stable/inspectable.
private struct DailyTaskManagerCacheSnapshot: Codable {
    let tasks: [DailyTask]
    let teamIds: [String]
    let scope: String?
}

private enum TaskManagerRoute: String, Identifiable {
    case attendance
    case cpVisits
    case siteVisits
    case landInspection
    case issues
    case leaves
    case permissions
    case fines
    case loanDesk
    case loans
    case bookings

    var id: String { rawValue }

    init?(task: DailyTask) {
        let source = (task.sourceReferenceType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        switch source {
        case "staff_attendance":
            self = .attendance
        case "client_place_visit", "clientplacevisit":
            self = .cpVisits
        case "site_visit", "sitevisit":
            self = .siteVisits
        case "land_inspection", "landinspection", "landproperty":
            self = .landInspection
        case "issue":
            self = .issues
        case "leave":
            self = .leaves
        case "permission":
            self = .permissions
        case "fine", "fines":
            self = .fines
        case "loan":
            self = .loans
        default:
            if source.hasPrefix("fine_") {
                self = .fines
            } else if source.hasPrefix("loan_") {
                self = .loanDesk
            } else if source.hasPrefix("loan") {
                self = .loans
            } else if source.contains("booking") {
                self = .bookings
            } else {
                return nil
            }
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .attendance:
            ConvexAttendanceListView()
        case .cpVisits:
            CpVisitsView()
        case .siteVisits:
            SiteVisitsListView()
        case .landInspection:
            LandInspectionView()
        case .issues:
            IssuesView()
        case .leaves:
            LeavesListView()
        case .permissions:
            ConvexPermissionListView()
        case .fines:
            FinesDeductionsView()
        case .loanDesk:
            LoanDeskView()
        case .loans:
            LoansView()
        case .bookings:
            BookingsListView()
        }
    }
}

private struct DailyTaskMetrics {
    let myTasks: Int
    let teamTasks: Int
    let assignedByMe: Int
    let extensionRequests: Int
    let overdue: Int
    let all: Int
    let pending: Int
    let inProgress: Int
    let completed: Int
    let cancelled: Int

    init(tasks: [DailyTask], teamIds: Set<String>, scope: String?, staffId: String?, todayString: String) {
        var my = 0
        var team = 0
        var assigned = 0
        var ext = 0
        var overdueCount = 0
        var pendingCount = 0
        var inProgressCount = 0
        var completedCount = 0
        var cancelledCount = 0

        for task in tasks {
            if let staffId, task.assignedTo == staffId { my += 1 }
            if scope == "all" || task.assignedTo.map(teamIds.contains) == true { team += 1 }
            if let staffId, task.assignedBy == staffId { assigned += 1 }
            if task.pendingExtensionRequest == true { ext += 1 }
            if DailyTaskStatusFilter.isOverdue(task, todayString: todayString) { overdueCount += 1 }

            switch task.status {
            case "pending": pendingCount += 1
            case "in-progress": inProgressCount += 1
            case "completed": completedCount += 1
            case "cancelled": cancelledCount += 1
            default: break
            }
        }

        myTasks = my
        teamTasks = team
        assignedByMe = assigned
        extensionRequests = ext
        overdue = overdueCount
        all = tasks.count
        pending = pendingCount
        inProgress = inProgressCount
        completed = completedCount
        cancelled = cancelledCount
    }

    func count(for filter: DailyTaskStatusFilter) -> Int {
        switch filter {
        case .all: return all
        case .pending: return pending
        case .overdue: return overdue
        case .inProgress: return inProgress
        case .completed: return completed
        case .cancelled: return cancelled
        }
    }
}

private enum DailyTaskStatusFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case overdue
    case inProgress
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .pending: return "Pending"
        case .overdue: return "Overdue"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    func matches(_ task: DailyTask, todayString: String) -> Bool {
        switch self {
        case .all: return true
        case .pending: return task.status == "pending"
        case .overdue: return Self.isOverdue(task, todayString: todayString)
        case .inProgress: return task.status == "in-progress"
        case .completed: return task.status == "completed"
        case .cancelled: return task.status == "cancelled"
        }
    }

    static func isOverdue(_ task: DailyTask, todayString: String) -> Bool {
        guard task.status != "completed", task.status != "cancelled" else { return false }
        if let deadline = task.deadline?.nonBlank {
            return deadline < todayString
        }
        guard let creationTime = task.creationTime else { return false }
        let ageMs = Date().timeIntervalSince1970 * 1000 - creationTime
        return ageMs >= 24 * 60 * 60 * 1000
    }
}

private enum DailyTaskScopeFilter: String, CaseIterable, Identifiable {
    case myTasks
    case teamTasks
    case assignedByMe
    case extensionRequests
    case overdue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myTasks: return "My Tasks"
        case .teamTasks: return "My Team Tasks"
        case .assignedByMe: return "Assigned By Me"
        case .extensionRequests: return "Extension Requests"
        case .overdue: return "Overdue"
        }
    }

    func count(in metrics: DailyTaskMetrics) -> Int {
        switch self {
        case .myTasks: return metrics.myTasks
        case .teamTasks: return metrics.teamTasks
        case .assignedByMe: return metrics.assignedByMe
        case .extensionRequests: return metrics.extensionRequests
        case .overdue: return metrics.overdue
        }
    }

}

private struct TaskMetricCard: View {
    let title: String
    let value: Int
    let isDanger: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: 0x475467))
                .lineLimit(1)

            Text("\(value)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isDanger ? Color(hex: 0xDC2626) : Color(hex: 0x101828))
                .monospacedDigit()
        }
        .frame(width: 112, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }
}

private struct TaskManagerLoadingSkeleton: View {
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 7) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(hex: 0xE8EEF6))
                                .frame(width: 178, height: 15)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(hex: 0xEEF2F6))
                                .frame(width: 130, height: 11)
                        }
                        Spacer()
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(hex: 0xFFF3D6))
                            .frame(width: 74, height: 24)
                    }

                    HStack(spacing: 16) {
                        skeletonMetric(width: 86)
                        Spacer(minLength: 12)
                        skeletonMetric(width: 112)
                            .frame(width: 132, alignment: .leading)
                    }

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: 0xF2F4F7))
                        .frame(width: 108, height: 20)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .redacted(reason: .placeholder)
            }
        }
    }

    private func skeletonMetric(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(hex: 0xEEF2F6))
                .frame(width: 62, height: 10)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hex: 0xE8EEF6))
                .frame(width: width, height: 13)
        }
    }
}

private struct TaskFilterSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: 0x98A2B3))
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    content
                }
            }
        }
    }
}

private struct TaskManagerChip: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))

                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : .white)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(isSelected ? Color.white : Color(hex: 0x0B61CA), in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : Color(hex: 0x475467))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0xE8EEF6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TaskCategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(isSelected ? Color.white : Color(hex: 0x0B61CA).opacity(0.45))
                    .frame(width: 7, height: 7)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : Color(hex: 0x344054))
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(isSelected ? Color(hex: 0x0B61CA) : Color.white, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0xD9E2F0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DailyTaskManagerCard: View {
    let task: DailyTask
    let module: String
    let isOverdue: Bool
    let onOpen: () -> Void
    var onComplete: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    // Mirrors Android bindRow: out-of-station handoff tasks that are still
    // open expose inline Complete / Cancel actions.
    private var showsHandoffActions: Bool {
        task.sourceReferenceType == "out_of_station_handoff"
            && (task.status == "pending" || task.status == "in-progress")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.displayTitle)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(hex: 0x101828))
                                .lineLimit(2)

                            if let subtitle = task.displaySubtitle {
                                Text(subtitle)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(Color(hex: 0x667085))
                                    .lineLimit(2)
                            }
                        }

                        Spacer(minLength: 8)

                        statusPill
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Deadline")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Color(hex: 0x98A2B3))

                            Text(shortDeadline)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x101828))
                        }

                        Spacer(minLength: 12)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Assigned to")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Color(hex: 0x98A2B3))

                            Text(task.displayAssignedTo)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x101828))
                                .lineLimit(1)
                        }
                        .frame(width: 132, alignment: .leading)
                    }

                    if let badge = badgeText {
                        Text(badge)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(hex: 0x475467))
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Color(hex: 0xF2F4F7), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsHandoffActions {
                HStack(spacing: 10) {
                    Button {
                        onComplete?()
                    } label: {
                        Text("Complete")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(hex: 0x16A34A), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onCancel?()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0xB42318))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(hex: 0xFEF3F2), in: Capsule())
                            .overlay(Capsule().stroke(Color(hex: 0xFECDCA), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private var badgeText: String? {
        if module != "Task Manager" { return module }
        return task.label?.nonBlank ?? task.taskCategory?.nonBlank
    }

    private var statusPill: some View {
        Text(statusLabel)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(statusTextColor)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(statusBackground, in: Capsule())
    }

    private var statusLabel: String {
        if isOverdue { return "Overdue" }
        switch task.status {
        case "completed": return "Completed"
        case "in-progress": return "In Progress"
        case "cancelled": return "Cancelled"
        default: return "Pending"
        }
    }

    private var statusTextColor: Color {
        if isOverdue { return Color(hex: 0xB42318) }
        switch task.status {
        case "completed": return Color(hex: 0x16A34A)
        case "in-progress": return Color(hex: 0x175CD3)
        case "cancelled": return Color(hex: 0xB42318)
        default: return Color(hex: 0xB54708)
        }
    }

    private var statusBackground: Color {
        if isOverdue { return Color(hex: 0xFEF3F2) }
        switch task.status {
        case "completed": return Color(hex: 0xECFDF3)
        case "in-progress": return Color(hex: 0xEFF8FF)
        case "cancelled": return Color(hex: 0xFEF3F2)
        default: return Color(hex: 0xFFFAEB)
        }
    }

    private var shortDeadline: String {
        guard let raw = task.deadline?.nonBlank else { return "-" }
        if let date = AppModuleFormatters.ymd.date(from: raw) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "d MMM"
            return formatter.string(from: date)
        }
        return raw
    }
}

/// App-styled sheet for a task without a mobile home — shows the deep link and
/// offers Open / Copy. Mirrors Android `WebTaskLinkBottomSheet` (the fallback
/// path of `TaskNavRouter`). Native per-source routing to in-app screens is not
/// yet wired on iOS; every task opens on the web app for now.
private struct TaskWebLinkSheet: View {
    let task: DailyTask

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // Web app origin — matches Android's WEB_APP_URL.
    private let webAppURL = "https://mg.theairix.com"

    private var label: String {
        task.title?.nonBlank ?? task.taskName?.nonBlank ?? "This task"
    }

    private var resolvedURL: String {
        guard let path = task.actionUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank else {
            return webAppURL
        }
        if path.hasPrefix("http") { return path }
        return webAppURL + (path.hasPrefix("/") ? path : "/\(path)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(2)
                Text("Open this task on the web app to act on it.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
            }

            Text(resolvedURL)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: 0x475467))
                .lineLimit(2)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xF2F4F7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                if let url = URL(string: resolvedURL) { openURL(url) }
                dismiss()
            } label: {
                Text("Open Link")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(hex: 0x0B61CA), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = resolvedURL
                #endif
                dismiss()
            } label: {
                Text("Copy Link")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(hex: 0xEAF2FE), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}
