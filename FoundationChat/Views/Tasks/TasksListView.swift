import SwiftUI

struct TasksListView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var tasks: [ConvexTask] = []
    @State private var summary: ConvexTaskSummary?
    @State private var filter: TaskListFilter = .all
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didAnimateIn = false

    private var filteredTasks: [ConvexTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks.filter { task in
            filter.matches(task) && (
                query.isEmpty
                || task.displayTitle.lowercased().contains(query)
                || task.displayProject.lowercased().contains(query)
                || (task.displayDescription?.lowercased().contains(query) ?? false)
            )
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: 0xF1F3F8).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .zIndex(1)

                contentSheet
                    .padding(.top, -20)
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadDataAsync() }
        .refreshable { await loadDataAsync() }
        .alert("Error", isPresented: errorAlertBinding, actions: {
            Button("OK", role: .cancel) { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .onAppear { playEntryAnimation() }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            Color(hex: 0x0B61CA)

            Image("onboard_todays_tasks")
                .resizable()
                .scaledToFit()
                .frame(width: 138, height: 112)
                .opacity(0.95)
                .offset(x: 18, y: 52)
                .opacity(didAnimateIn ? 1 : 0)
                .scaleEffect(didAnimateIn ? 1 : 0.88)
                .animation(.spring(response: 0.52, dampingFraction: 0.82).delay(0.16), value: didAnimateIn)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("My Tasks")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 10)

                Text("Manage and track all tasks")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0xD9D6FE))
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .opacity(didAnimateIn ? 1 : 0)
            .offset(x: didAnimateIn ? 0 : -28)
            .animation(.easeOut(duration: 0.42).delay(0.08), value: didAnimateIn)
        }
        .frame(height: 204)
    }

    private var contentSheet: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 20)
                .padding(.top, 20)

            filterChips
                .padding(.top, 16)

            taskList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x98A2B3))

            TextField("Search Tasks", text: $searchText)
                .font(.system(size: 14, weight: .medium))
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color(hex: 0xF7F8FA), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        }
        .opacity(didAnimateIn ? 1 : 0)
        .offset(y: didAnimateIn ? 0 : 16)
        .animation(.easeOut(duration: 0.34).delay(0.2), value: didAnimateIn)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskListFilter.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            filter = item
                        }
                    } label: {
                        Text(item.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(filter == item ? .white : Color(hex: 0x475467))
                            .padding(.horizontal, 15)
                            .frame(height: 34)
                            .background(
                                filter == item ? Color(hex: 0x0B61CA) : Color(hex: 0xF2F4F7),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(filter == item ? 1 : 0.98)
                }
            }
            .padding(.horizontal, 20)
        }
        .sensoryFeedback(.selection, trigger: filter)
        .opacity(didAnimateIn ? 1 : 0)
        .offset(y: didAnimateIn ? 0 : 18)
        .animation(.easeOut(duration: 0.36).delay(0.28), value: didAnimateIn)
    }

    @ViewBuilder
    private var taskList: some View {
        if isLoading && tasks.isEmpty {
            ScrollView {
                AppModuleLoadingRows()
                    .padding(.top, 12)
            }
        } else if filteredTasks.isEmpty {
            VStack(spacing: 14) {
                Image("HomeEmptyTrips")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 156, height: 156)
                    .opacity(0.62)

                Text("No Tasks Available")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))

                Text(emptyMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 42)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(Array(filteredTasks.enumerated()), id: \.element.id) { index, task in
                        NavigationLink {
                            TaskDetailView(taskId: task._id, initial: task) {
                                await loadDataAsync()
                            }
                        } label: {
                            AndroidTaskCard(task: task)
                        }
                        .buttonStyle(.plain)
                        .opacity(didAnimateIn ? 1 : 0)
                        .offset(y: didAnimateIn ? 0 : 32)
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.9).delay(0.34 + Double(index) * 0.045),
                            value: didAnimateIn
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .refreshable { await loadDataAsync() }
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all: return "It looks like you don't have any tasks scheduled at the moment."
        case .inProgress: return "No tasks are currently in progress."
        case .pending: return "No pending tasks are waiting on you."
        case .completed: return "No completed tasks yet."
        }
    }

    private func playEntryAnimation() {
        didAnimateIn = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            didAnimateIn = true
        }
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

private struct AndroidTaskCard: View {
    let task: ConvexTask

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0x0B61CA))
                            .frame(width: 40, height: 40)

                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.displayTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: 0x101828))
                            .lineLimit(2)

                        Text(task.displayProject)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0x667085))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    priorityBadge
                }

                HStack(spacing: 12) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(hex: 0xEAECF0))

                            Capsule()
                                .fill(Color(hex: 0x0B61CA))
                                .frame(width: proxy.size.width * CGFloat(task.displayProgress) / 100)
                        }
                    }
                    .frame(height: 6)

                    Text("\(task.displayProgress)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .monospacedDigit()
                }

                Divider()
                    .overlay(Color(hex: 0xF2F4F7))

                HStack(spacing: 12) {
                    statusBadge

                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))

                    Text(shortDueDate)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x344054))

                    Spacer(minLength: 0)
                }
            }
            .padding(16)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var priorityBadge: some View {
        Text((task.priority?.taskNilIfBlank ?? "Medium").capitalized)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(priorityColor, in: Capsule())
    }

    private var statusBadge: some View {
        Text(task.normalizedStatus.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(statusTextColor)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(statusBackground, in: Capsule())
    }

    private var priorityColor: Color {
        switch task.priority?.lowercased() {
        case "high", "urgent", "critical": return Color(hex: 0xF04438)
        case "low": return Color(hex: 0x16A34A)
        default: return Color(hex: 0xF97316)
        }
    }

    private var statusTextColor: Color {
        switch task.normalizedStatus {
        case .completed: return Color(hex: 0x16A34A)
        case .inProgress: return Color(hex: 0x175CD3)
        case .delayed: return Color(hex: 0xB42318)
        case .pending: return Color(hex: 0xB54708)
        }
    }

    private var statusBackground: Color {
        switch task.normalizedStatus {
        case .completed: return Color(hex: 0xECFDF3)
        case .inProgress: return Color(hex: 0xEFF8FF)
        case .delayed: return Color(hex: 0xFEF3F2)
        case .pending: return Color(hex: 0xFFFAEB)
        }
    }

    private var shortDueDate: String {
        guard let raw = task.displayDueDate?.taskNilIfBlank else { return "-" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        if let date = parser.date(from: raw) {
            let display = DateFormatter()
            display.dateFormat = "d MMM"
            return display.string(from: date)
        }
        return raw
    }
}

private extension String {
    var taskNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
