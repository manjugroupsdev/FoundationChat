import SwiftUI

struct TaskDetailView: View {
    let taskId: String
    let initial: ConvexTask?
    let onChange: () async -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var task: ConvexTask?
    @State private var resources: [TaskResourceEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showUpdateSheet = false
    @State private var showTimelineSheet = false
    @State private var descriptionExpanded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0xF9FAFB).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if let task {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            overview(task)
                            dateCards(task)
                            descriptionBlock(task)
                            assignmentBlock(task)
                            timelineAccessBlock(task)
                            resourceSummary(task)
                        }
                        .padding(20)
                        .padding(.bottom, 88)
                    }
                    .refreshable { await refresh() }
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            if task != nil {
                Button {
                    showUpdateSheet = true
                } label: {
                    Text("Today's Update")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(hex: 0x1BCA0B), in: Capsule())
                        .shadow(color: Color(hex: 0x1BCA0B).opacity(0.24), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if task == nil { task = initial }
            await refresh()
        }
        .sheet(isPresented: $showUpdateSheet) {
            if let task {
                TaskUpdateSheet(task: task) {
                    await refresh()
                    await onChange()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
        .sheet(isPresented: $showTimelineSheet) {
            TaskTimelineSheet(taskId: taskId)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            Text("Task Overview")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            Spacer()

            Button {
                showTimelineSheet = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Task Timeline")
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(Color.white)
    }

    private func overview(_ task: ConvexTask) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "building.2")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))

                Text(task.displayTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text((task.priority?.taskNilIfBlank ?? "Medium").capitalized)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(priorityColor(task), in: Capsule())
            }

            Text(detailStatusLabel(task))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusTextColor(task.normalizedStatus))

            HStack(spacing: 16) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.02), radius: 6)
                        Capsule()
                            .fill(Color(hex: 0x0B61CA))
                            .frame(width: proxy.size.width * CGFloat(task.displayProgress) / 100)
                    }
                }
                .frame(height: 8)

                Text("\(task.displayProgress)%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .monospacedDigit()
            }
        }
    }

    private func dateCards(_ task: ConvexTask) -> some View {
        HStack(spacing: 12) {
            dateCard(title: "Start Date", value: formatTaskDate(task.startDate))
            dateCard(title: "End Date", value: formatTaskDate(task.displayDueDate))
        }
    }

    private func dateCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))

            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private func descriptionBlock(_ task: ConvexTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task Description")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            Text(task.displayDescription ?? "No description provided.")
                .font(.system(size: 14, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(Color(hex: 0x475467))
                .lineLimit(descriptionExpanded ? nil : 3)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    descriptionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(descriptionExpanded ? "View less" : "View more")
                    Image(systemName: descriptionExpanded ? "chevron.up" : "chevron.down")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
            }
            .buttonStyle(.plain)
        }
    }

    private func assignmentBlock(_ task: ConvexTask) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Work Category")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                    Text("\(task.workCategory?.taskNilIfBlank ?? "Project")  •  \(task.taskId?.taskNilIfBlank ?? "-")")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x475467))
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 9) {
                Text("Assigned To")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                Text(task.assignedToDisplay?.taskNilIfBlank ?? "")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x475467))
            }
        }
    }

    private func timelineAccessBlock(_ task: ConvexTask) -> some View {
        Button {
            showTimelineSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: 0xEAF3FF), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Task Timeline")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text(timelineSubtitle(task))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open task timeline")
    }

    private func resourceSummary(_ task: ConvexTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resource Summary")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                resourceTile(icon: "wallet.pass", iconColor: Color(hex: 0x16A34A), title: "Est. Cost", value: "-")
                resourceTile(icon: "square.stack.3d.up", iconColor: Color(hex: 0x0B61CA), title: "Total Quantity", value: totalQuantityText(task))
                resourceTile(icon: "person.2", iconColor: Color(hex: 0x0B61CA), title: "Labour Count", value: "\(resources.filter { $0.resourceType == "labour" }.count)")
                resourceTile(icon: "wrench.adjustable", iconColor: Color(hex: 0x16A34A), title: "Equipment Qty.", value: trimDouble(resources.filter { $0.resourceType == "equipment" }.reduce(0) { $0 + ($1.budgetQty ?? 0) }))
                resourceTile(icon: "paintbrush.pointed", iconColor: Color(hex: 0x7A5AF8), title: "Materials Qty.", value: materialQtyText(task))
                resourceTile(icon: "ruler", iconColor: Color(hex: 0x0B61CA), title: "Unit", value: task.unit?.taskNilIfBlank ?? "-")
            }
        }
    }

    private func resourceTile(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 74)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func refresh() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let taskReq = TasksConvexAPIService.getTask(token: token, taskId: taskId)
            async let resourceReq = TasksConvexAPIService.getTaskResources(token: token, taskId: taskId)
            task = try await taskReq
            resources = (try? await resourceReq) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func priorityColor(_ task: ConvexTask) -> Color {
        switch task.priority?.lowercased() {
        case "high", "urgent", "critical": return Color(hex: 0xF04438)
        case "low": return Color(hex: 0x16A34A)
        default: return Color(hex: 0xF97316)
        }
    }

    private func detailStatusLabel(_ task: ConvexTask) -> String {
        task.normalizedStatus == .pending ? "Not Started" : task.normalizedStatus.label
    }

    private func timelineSubtitle(_ task: ConvexTask) -> String {
        if let count = task.updates?.count, count > 0 {
            return "\(count) update\(count == 1 ? "" : "s") recorded"
        }
        if task.todaysUpdate?.taskNilIfBlank != nil || task.blocker?.taskNilIfBlank != nil || task.tomorrowsPlan?.taskNilIfBlank != nil {
            return "Latest progress is available"
        }
        return "View task history and progress"
    }

    private func statusTextColor(_ status: TaskStatus) -> Color {
        switch status {
        case .completed: return Color(hex: 0x16A34A)
        case .inProgress: return Color(hex: 0x0B61CA)
        case .delayed: return Color(hex: 0xB42318)
        case .pending: return Color(hex: 0xB54708)
        }
    }

    private func totalQuantityText(_ task: ConvexTask) -> String {
        guard let total = task.totalQuantity else { return "-" }
        return "\(trimDouble(total)) \(task.unit ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func materialQtyText(_ task: ConvexTask) -> String {
        let total = resources.filter { $0.resourceType == "material" }.reduce(0) { $0 + ($1.budgetQty ?? 0) }
        guard total > 0 else { return "-" }
        return "\(trimDouble(total)) \(task.unit ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimDouble(_ value: Double) -> String {
        value == Double(Int(value)) ? "\(Int(value))" : String(format: "%.2f", value)
    }

    private func formatTaskDate(_ raw: String?) -> String {
        guard let raw = raw?.taskNilIfBlank else { return "-" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.dateFormat = "d MMM yyyy"
        return out.string(from: date)
    }
}

private struct TaskTimelineSheet: View {
    let taskId: String

    @Environment(AuthStore.self) private var authStore
    @State private var updates: [ConvexTaskUpdate] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 8) {
                    Text("Time Line")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text("Here you can able to history of time line")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 24)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if updates.isEmpty {
                    Text(errorMessage ?? "No timeline yet.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(updates.enumerated()), id: \.element.id) { index, update in
                            TimelineEntryView(update: update, showsDate: index == 0 || updates[index - 1].date != update.date)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Color.white)
        .task { await loadTimeline() }
        .refreshable { await loadTimeline() }
    }

    private func loadTimeline() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            updates = try await TasksConvexAPIService.getTaskTimeline(token: token, taskId: taskId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TimelineEntryView: View {
    let update: ConvexTaskUpdate
    let showsDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsDate {
                Text(formatDate(update.date))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .padding(.top, 12)
            }

            HStack(alignment: .top, spacing: 8) {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: 0xD1E9FF))
                        .frame(width: 2)
                    Circle()
                        .fill(Color(hex: 0x0B61CA))
                        .frame(width: 14, height: 14)
                        .padding(.top, 18)
                }
                .frame(width: 24)
                .frame(minHeight: 150)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(update.displayAuthor)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: 0x101828))
                        Spacer()
                        Text(formatTime(update))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0x98A2B3))
                    }

                    if let progress = update.displayProgress {
                        Text("Progress: \(progress)%")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0x667085))
                    }

                    if let notes = update.displayNotes {
                        Text(notes)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color(hex: 0x344054))
                    }

                    if let images = update.images, !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                                    AsyncImage(url: image.url.flatMap(URL.init(string:))) { phase in
                                        switch phase {
                                        case .success(let img): img.resizable().scaledToFill()
                                        default: Color(hex: 0xF2F4F7)
                                        }
                                    }
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }

                    Text(update.blocker?.taskNilIfBlank ?? "No issues")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(update.blocker?.taskNilIfBlank == nil ? Color(hex: 0x667085) : Color(hex: 0xB42318))

                    if let plan = update.tomorrowsPlan?.taskNilIfBlank {
                        Text(plan)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0x667085))
                    }
                }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
            }
        }
    }

    private func formatDate(_ raw: String?) -> String {
        guard let raw = raw?.taskNilIfBlank else { return "" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.dateFormat = "d MMM yyyy"
        return out.string(from: date)
    }

    private func formatTime(_ update: ConvexTaskUpdate) -> String {
        if let ms = update.creationTime {
            let date = Date(timeIntervalSince1970: ms / 1000)
            let out = DateFormatter()
            out.dateFormat = "hh:mm a"
            return out.string(from: date)
        }
        if let date = update.occurredAt {
            let out = DateFormatter()
            out.dateFormat = "hh:mm a"
            return out.string(from: date)
        }
        return ""
    }
}

private extension String {
    var taskNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
