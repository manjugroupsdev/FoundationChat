import SwiftUI

struct TasksListView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var tasks: [DailyTask] = []
    @State private var teamIds: Set<String> = []
    @State private var scope: String?
    @State private var selectedTaskScope: DailyTaskScopeFilter = .teamTasks
    @State private var statusFilter: DailyTaskStatusFilter = .all
    @State private var categoryFilter = "All"
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var todayString: String {
        AppModuleFormatters.ymd.string(from: Date())
    }

    private var currentStaffId: String? {
        authStore.currentSession?.user.staffId?.nonBlank ?? authStore.currentSession?.user._id.nonBlank
    }

    private var metrics: DailyTaskMetrics {
        DailyTaskMetrics(tasks: tasks, teamIds: teamIds, scope: scope, staffId: currentStaffId, todayString: todayString)
    }

    private var scopedTasks: [DailyTask] {
        tasks.filter {
            selectedTaskScope.matches(
                $0,
                teamIds: teamIds,
                scope: scope,
                staffId: currentStaffId,
                todayString: todayString
            )
        }
    }

    private var scopedMetrics: DailyTaskMetrics {
        DailyTaskMetrics(tasks: scopedTasks, teamIds: teamIds, scope: scope, staffId: currentStaffId, todayString: todayString)
    }

    private var categories: [String] {
        let modules = Set(scopedTasks.map(moduleLabel(for:))).sorted()
        return ["All"] + modules
    }

    private var visibleTasks: [DailyTask] {
        scopedTasks
            .filter { statusFilter.matches($0, todayString: todayString) }
            .filter { categoryFilter == "All" || moduleLabel(for: $0) == categoryFilter }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                metricsRow

                TaskFilterSection(title: "STATUS") {
                    ForEach(DailyTaskStatusFilter.allCases) { filter in
                        TaskManagerChip(
                            title: filter.title,
                            count: scopedMetrics.count(for: filter),
                            isSelected: statusFilter == filter
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                statusFilter = filter
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
        .refreshable { await loadTasks() }
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
                        isSelected: selectedTaskScope == filter,
                        isDanger: filter == .overdue
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTaskScope = filter
                            statusFilter = .all
                            categoryFilter = "All"
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var taskContent: some View {
        if isLoading && tasks.isEmpty {
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                        .frame(height: 112)
                        .redacted(reason: .placeholder)
                }
            }
            .padding(.top, 4)
        } else if visibleTasks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checklist.unchecked")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Color(hex: 0x98A2B3))

                Text("No tasks")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))

                Text("Task manager items will land here.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 150)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(visibleTasks) { task in
                    DailyTaskManagerCard(
                        task: task,
                        module: moduleLabel(for: task),
                        isOverdue: DailyTaskStatusFilter.isOverdue(task, todayString: todayString)
                    )
                }
            }
            .padding(.top, 2)
        }
    }

    private func loadTasks() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await TasksConvexAPIService.getTaskManagerTasks(token: token, today: todayString)
            tasks = payload.tasks.sorted { ($0.creationTime ?? 0) > ($1.creationTime ?? 0) }
            teamIds = payload.teamIds
            scope = payload.scope
            if !categories.contains(categoryFilter) {
                categoryFilter = "All"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moduleLabel(for task: DailyTask) -> String {
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

    func matches(
        _ task: DailyTask,
        teamIds: Set<String>,
        scope: String?,
        staffId: String?,
        todayString: String
    ) -> Bool {
        switch self {
        case .myTasks:
            guard let staffId else { return false }
            return task.assignedTo == staffId
        case .teamTasks:
            return scope == "all" || task.assignedTo.map(teamIds.contains) == true
        case .assignedByMe:
            guard let staffId else { return false }
            return task.assignedBy == staffId
        case .extensionRequests:
            return task.pendingExtensionRequest == true
        case .overdue:
            return DailyTaskStatusFilter.isOverdue(task, todayString: todayString)
        }
    }
}

private struct TaskMetricCard: View {
    let title: String
    let value: Int
    let isSelected: Bool
    let isDanger: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0x475467))
                    .lineLimit(1)

                Text("\(value)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isDanger ? Color(hex: 0xDC2626) : Color(hex: 0x101828))
                    .monospacedDigit()
            }
            .frame(width: 112, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                isSelected ? Color(hex: 0xEFF6FF) : Color.white,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0xE5E7EB), lineWidth: isSelected ? 1.4 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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

    var body: some View {
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
