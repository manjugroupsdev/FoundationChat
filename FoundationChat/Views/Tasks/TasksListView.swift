import SwiftUI

struct TasksListView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var tasks: [ConvexTask] = []
    @State private var summary: ConvexTaskSummary?
    @State private var filter: TaskListFilter = .all
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader

            Picker("Filter", selection: $filter) {
                ForEach(TaskListFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            taskList
        }
        .navigationTitle("Tasks")
        .task { loadData() }
        .refreshable { await loadDataAsync() }
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

    private var summaryHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                summaryTile(
                    title: "Total",
                    value: "\(summary?.totalCount ?? tasks.count)",
                    color: .blue,
                    icon: "tray.full.fill"
                )
                summaryTile(
                    title: "In Progress",
                    value: "\(summary?.inProgressCount ?? tasks.filter { $0.normalizedStatus == .inProgress }.count)",
                    color: .orange,
                    icon: "hourglass"
                )
                summaryTile(
                    title: "Completed",
                    value: "\(summary?.completedCount ?? tasks.filter { $0.normalizedStatus == .completed }.count)",
                    color: .green,
                    icon: "checkmark.seal.fill"
                )
            }

            overallProgressCard
        }
        .padding()
    }

    private func summaryTile(title: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var overallProgressCard: some View {
        let pct = summary?.overallPercentValue ?? computeFallbackPercent()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Overall Progress")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(pct.rounded()))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.indigo)
            }
            ProgressView(value: max(0, min(1, pct / 100)))
                .tint(.indigo)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func computeFallbackPercent() -> Double {
        guard !tasks.isEmpty else { return 0 }
        let total = tasks.reduce(0) { $0 + $1.displayProgress }
        return Double(total) / Double(tasks.count)
    }

    @ViewBuilder
    private var taskList: some View {
        let filtered = tasks.filter(filter.matches)
        if filtered.isEmpty && !isLoading {
            ContentUnavailableView(
                "No Tasks",
                systemImage: "checklist",
                description: Text(emptyMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(filtered) { task in
                    NavigationLink {
                        TaskDetailView(taskId: task._id, initial: task) {
                            await loadDataAsync()
                        }
                    } label: {
                        TaskRow(task: task)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if isLoading && filtered.isEmpty { ProgressView() }
            }
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all: return "No tasks assigned to you yet."
        case .inProgress: return "No tasks currently in progress."
        case .completed: return "No completed tasks yet."
        }
    }

    private func loadData() {
        Task { await loadDataAsync() }
    }

    private func loadDataAsync() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let tasksReq = TasksConvexAPIService.getMyTasks(token: token)
            async let summaryReq = TasksConvexAPIService.getMySummary(token: token)
            tasks = try await tasksReq
            summary = try? await summaryReq
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TaskRow: View {
    let task: ConvexTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                    if let project = task.projectName, !project.isEmpty {
                        Label(project, systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                statusBadge
            }

            if let description = task.displayDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                ProgressView(value: Double(task.displayProgress) / 100)
                    .tint(progressColor)
                Text("\(task.displayProgress)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(progressColor)
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                if let due = task.dueDate, !due.isEmpty {
                    Label(due, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let priority = task.priority, !priority.isEmpty {
                    priorityBadge(priority)
                }
                Spacer()
                if let by = task.assignedByDisplay, !by.isEmpty {
                    Label(by, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var statusBadge: some View {
        Text(task.normalizedStatus.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch task.normalizedStatus {
        case .completed: return .green
        case .inProgress: return .orange
        case .pending: return .gray
        }
    }

    private var progressColor: Color {
        let p = task.displayProgress
        if p >= 100 { return .green }
        if p >= 50 { return .orange }
        return .blue
    }

    private func priorityBadge(_ priority: String) -> some View {
        let color: Color = {
            switch priority.lowercased() {
            case "high", "urgent", "critical": return .red
            case "medium": return .orange
            case "low": return .blue
            default: return .gray
            }
        }()
        return Text(priority.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
