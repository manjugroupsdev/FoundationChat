import SwiftUI

struct ProjectTasksView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var tasks: [ConvexTask] = []
    @State private var searchText = ""
    @State private var selectedFilter: TaskListFilter = .all
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let headerHeight: CGFloat = 208
    private let panelOverlap: CGFloat = 28

    private var visibleTasks: [ConvexTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks
            .filter(selectedFilter.matches)
            .filter { task in
                guard !query.isEmpty else { return true }
                return task.displayTitle.lowercased().contains(query)
                    || (task.displayDescription ?? "").lowercased().contains(query)
                    || task.displayProject.lowercased().contains(query)
                    || (task.assignedToDisplay ?? "").lowercased().contains(query)
            }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.white.ignoresSafeArea()

            headerTopFill

            header

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: headerHeight - panelOverlap)

                        content
                            .frame(
                                minHeight: max(proxy.size.height - (headerHeight - panelOverlap), 0),
                                alignment: .top
                            )
                            .background(Color.white)
                            .clipShape(.rect(topLeadingRadius: 32, topTrailingRadius: 32))
                    }
                }
                .refreshable { await loadTasks() }
                .ignoresSafeArea(edges: .top)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadTasks() }
        .alert("Tasks", isPresented: errorAlertBinding, actions: {
            Button("OK", role: .cancel) { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    private var headerTopFill: some View {
        Color(hex: 0x0B61CA)
            .frame(height: headerHeight)
            .frame(maxWidth: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
    }

    private var header: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(hex: 0x0B6ED8), Color(hex: 0x0755B8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: headerHeight)
            .ignoresSafeArea(edges: .top)

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("My Tasks")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Manage and track all tasks")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: 0xD9D6FE))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image("TasksHeader3D")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 152, height: 104)
                    .offset(x: 8, y: -5)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 28)
            .padding(.trailing, 16)
            .padding(.top, 76)
        }
        .frame(height: headerHeight)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private var content: some View {
        VStack(spacing: 0) {
            NativeInlineSearchBar(text: $searchText, placeholder: "Search Tasks")
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .frame(height: 50)

            filterStrip
                .padding(.top, 12)
                .padding(.bottom, 10)

            taskContent
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color.white)
        .clipShape(.rect(topLeadingRadius: 32, topTrailingRadius: 32))
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskListFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .medium))
                            .foregroundStyle(selectedFilter == filter ? .white : Color(hex: 0x475467))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(selectedFilter == filter ? Color(hex: 0x0B61CA) : Color(hex: 0xF2F4F7), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var taskContent: some View {
        if isLoading && tasks.isEmpty {
            LazyVStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    ProjectTaskSkeletonCard()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        } else if visibleTasks.isEmpty {
            ProjectTasksEmptyState()
                .frame(maxWidth: .infinity)
                .padding(.top, 112)
                .padding(.bottom, 180)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(visibleTasks) { task in
                    NavigationLink {
                        TaskDetailView(taskId: task.id, initial: task) {
                            await loadTasks()
                        }
                    } label: {
                        ProjectTaskCard(task: task)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadTasks() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await TasksConvexAPIService.getMyTasks(token: token)
            tasks = loaded.sorted { lhs, rhs in
                (lhs.creationTime ?? 0) > (rhs.creationTime ?? 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProjectTaskCard: View {
    let task: ConvexTask

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                icon

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(2)

                    Text(task.displayProject)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                priorityChip
            }

            if let description = task.displayDescription {
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: 0x667085))
                    .lineLimit(2)
            }

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(task.displayProgress)%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x344054))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0xE7EAF0))
                        Capsule()
                            .fill(Color(hex: 0x0B6ED8))
                            .frame(width: proxy.size.width * CGFloat(task.displayProgress) / 100)
                    }
                }
                .frame(height: 5)
            }

            HStack(spacing: 10) {
                statusChip

                Spacer()

                if let dueDate = task.displayDueDate {
                    Label(projectTaskDisplayDate(dueDate), systemImage: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0xEEF2F7), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
    }

    private var icon: some View {
        Image("AppLibraryIconAppsTasks")
            .resizable()
            .scaledToFit()
            .frame(width: 19, height: 19)
            .frame(width: 44, height: 44)
            .background(Color(hex: 0x0B6ED8), in: Circle())
    }

    private var priorityChip: some View {
        Text(priorityLabel)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(priorityColor)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(priorityColor.opacity(0.12), in: Capsule())
    }

    private var statusChip: some View {
        Text(task.normalizedStatus.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var priorityLabel: String {
        let value = task.priority?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value!.capitalized : "Medium"
    }

    private var priorityColor: Color {
        switch priorityLabel.lowercased() {
        case "high", "urgent": return Color(hex: 0xEF4444)
        case "low": return Color(hex: 0x16A34A)
        default: return Color(hex: 0xF59E0B)
        }
    }

    private var statusColor: Color {
        switch task.normalizedStatus {
        case .completed: return Color(hex: 0x16A34A)
        case .inProgress: return Color(hex: 0x0B6ED8)
        case .delayed: return Color(hex: 0xEF4444)
        case .pending: return Color(hex: 0xB45309)
        }
    }
}

private struct ProjectTasksEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image("HomeEmptyTrips")
                .resizable()
                .scaledToFit()
                .frame(width: 188, height: 176)
                .opacity(0.95)
                .accessibilityHidden(true)

            Text("No Tasks Available")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            Text("It looks like you don't have any tasks scheduled at the moment.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: 0x98A2B3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }
}

private struct ProjectTaskSkeletonCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white)
            .frame(height: 140)
            .redacted(reason: .placeholder)
    }
}

private func projectTaskDisplayDate(_ raw: String) -> String {
    if let date = AppModuleFormatters.ymd.date(from: raw) {
        return projectTaskDayFormatter.string(from: date)
    }

    let isoFractional = ISO8601DateFormatter()
    isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFractional.date(from: raw) {
        return projectTaskDayFormatter.string(from: date)
    }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: raw) {
        return projectTaskDayFormatter.string(from: date)
    }

    return raw
}

private let projectTaskDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd MMM"
    return formatter
}()
