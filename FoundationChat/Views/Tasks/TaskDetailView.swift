import SwiftUI

struct TaskDetailView: View {
    let taskId: String
    let initial: ConvexTask?
    let onChange: () async -> Void

    @Environment(AuthStore.self) private var authStore

    @State private var task: ConvexTask?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showUpdateSheet = false

    var body: some View {
        List {
            if let task {
                headerSection(task)
                detailsSection(task)
                historySection(task)
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showUpdateSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(task == nil)
            }
        }
        .overlay {
            if isLoading && task == nil { ProgressView() }
        }
        .task {
            if task == nil { task = initial }
            await refresh()
        }
        .refreshable { await refresh() }
        .sheet(isPresented: $showUpdateSheet) {
            if let task {
                NavigationStack {
                    TaskUpdateSheet(task: task) {
                        await refresh()
                        await onChange()
                    }
                }
            }
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func headerSection(_ task: ConvexTask) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(task.displayTitle)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    statusBadge(task.normalizedStatus)
                }

                if let description = task.displayDescription, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Progress")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(task.displayProgress)%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.indigo)
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(task.displayProgress) / 100)
                        .tint(.indigo)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func detailsSection(_ task: ConvexTask) -> some View {
        Section("Details") {
            if let project = task.projectName, !project.isEmpty {
                detailRow(icon: "folder", label: "Project", value: project)
            }
            if let priority = task.priority, !priority.isEmpty {
                detailRow(icon: "flag.fill", label: "Priority", value: priority.capitalized)
            }
            if let due = task.dueDate, !due.isEmpty {
                detailRow(icon: "calendar", label: "Due", value: due)
            }
            if let start = task.startDate, !start.isEmpty {
                detailRow(icon: "calendar.badge.plus", label: "Start", value: start)
            }
            if let by = task.assignedByDisplay, !by.isEmpty {
                detailRow(icon: "person.crop.circle.badge.checkmark", label: "Assigned By", value: by)
            }
            if let to = task.assignedToDisplay, !to.isEmpty {
                detailRow(icon: "person.crop.circle", label: "Assigned To", value: to)
            }
            if let createdAt = task.createdAt, !createdAt.isEmpty {
                detailRow(icon: "clock", label: "Created", value: createdAt)
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func historySection(_ task: ConvexTask) -> some View {
        if let updates = task.updates, !updates.isEmpty {
            Section("History") {
                ForEach(updates) { update in
                    updateRow(update)
                }
            }
        }
    }

    private func updateRow(_ update: ConvexTaskUpdate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let by = update.byName ?? update.by, !by.isEmpty {
                    Label(by, systemImage: "person.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                if let progress = update.progress {
                    Text("\(progress)%")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.15), in: Capsule())
                        .foregroundStyle(.indigo)
                }
            }
            if let comment = update.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
            }
            if let occurredAt = update.occurredAt {
                Text(occurredAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let raw = update.at ?? update.createdAt, !raw.isEmpty {
                Text(raw)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: TaskStatus) -> some View {
        let color: Color = {
            switch status {
            case .completed: return .green
            case .inProgress: return .orange
            case .pending: return .gray
            }
        }()
        return Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func refresh() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            task = try await TasksConvexAPIService.getTask(token: token, taskId: taskId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
