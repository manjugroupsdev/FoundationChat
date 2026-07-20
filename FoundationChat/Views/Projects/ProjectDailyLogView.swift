import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ProjectDailyLogView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var selectedTab: DailyLogTab = .newEntry
    @State private var projects: [ProjectSummary] = []
    @State private var logs: [DailyLogEntry] = []
    @State private var recipients: [DprRecipient] = []
    @State private var reports: [DprReport] = []
    @State private var isLoadingLogs = false
    @State private var isLoadingDpr = false
    @State private var hasLoaded = false
    @State private var showCreateLog = false
    @State private var showAddRecipient = false
    @State private var showSendProjectPicker = false
    @State private var selectedLog: DailyLogEntry?
    @State private var expandedLogProjects: Set<String> = []
    @State private var expandedDprProjects: Set<String> = []
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    private var activeRecipientCount: Int {
        recipients.filter(\.isActive).count
    }

    private var selectableProjects: [ProjectSummary] {
        projects.filter { $0.status?.localizedCaseInsensitiveCompare("completed") != .orderedSame }
    }

    private var logGroups: [DailyLogProjectGroup] {
        DailyLogProjectGroup.make(from: logs)
    }

    private var reportGroups: [DprProjectGroup] {
        DprProjectGroup.make(from: reports)
    }

    private let heroHeight: CGFloat = 220
    private let panelOverlap: CGFloat = 38

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: 0xF5F7FB)
                .ignoresSafeArea()

            hero
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: heroHeight - panelOverlap)

                        scrollingPanel
                            .frame(
                                minHeight: max(proxy.size.height - (heroHeight - panelOverlap), 0),
                                alignment: .top
                            )
                    }
                }
                .refreshable { await reloadCurrentTab() }
                .ignoresSafeArea(edges: .top)
            }

            if let toastMessage {
                Text(toastMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(Color(hex: 0x111827), in: Capsule())
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if !hasLoaded {
                hasLoaded = true
                await loadAll()
            }
        }
        .alert("Daily Log", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showCreateLog) {
            CreateDailyLogSheet(projects: selectableProjects) {
                await loadLogs()
            }
            .appLibraryNativeSheet([.height(720), .large])
            .presentationBackground(Color.white)
        }
        .sheet(isPresented: $showAddRecipient) {
            DprAddRecipientSheet(projects: selectableProjects) {
                await loadDpr()
            }
            .appLibraryNativeSheet([.height(520), .large])
            .presentationBackground(Color.white)
        }
        .sheet(item: $selectedLog) { log in
            DailyLogDetailSheet(log: log)
                .appLibraryNativeSheet([.height(700), .large])
                .presentationBackground(Color.white)
        }
        .sheet(isPresented: $showSendProjectPicker) {
            NativeSearchableSelectionSheet(
                title: "Send DPR for project",
                prompt: "Search projects",
                items: projects,
                selectedId: nil,
                searchText: { [$0.displayName, $0.status ?? ""].joined(separator: " ") },
                rowContent: { project, _ in
                    DailyLogProjectPickerRow(project: project, isSelected: false)
                },
                onSelect: { project in
                    Task { await sendDpr(for: project) }
                }
            )
            .appLibraryNativeSheet([.medium, .large])
            .presentationBackground(Color.white)
        }
    }

    private var scrollingPanel: some View {
        VStack(spacing: 0) {
            tabHeader

            if selectedTab == .newEntry {
                newEntryContent
            } else {
                dprContent
            }
        }
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(hex: 0xF5F7FB))
        .clipShape(.rect(topLeadingRadius: 32, topTrailingRadius: 32))
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x02499D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Daily Log")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("Site progress and DPR WhatsApp")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xD9E8FF))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                Image("TasksHeader3D")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 96)
                    .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 8)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 20)
            .padding(.trailing, 22)
            .padding(.bottom, 62)
        }
        .frame(height: heroHeight)
        .ignoresSafeArea(edges: .top)
    }

    private var tabHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                DailyLogSegmentButton(title: "New Entry", isSelected: selectedTab == .newEntry) {
                    selectedTab = .newEntry
                }
                DailyLogSegmentButton(title: "DPR WhatsApp", isSelected: selectedTab == .dpr) {
                    selectedTab = .dpr
                }
            }
            .padding(3)
            .frame(height: 44)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                if selectedTab == .newEntry {
                    showCreateLog = true
                } else {
                    showAddRecipient = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var newEntryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Entries")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .padding(.horizontal, 16)
                .padding(.top, 20)

            if isLoadingLogs && logs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 44)
            } else if logs.isEmpty {
                DailyLogEmptyState(
                    title: "No Daily Logs Yet",
                    message: "Tap + to record today's site progress, labour, materials and observations.",
                    systemImage: "doc.badge.plus"
                )
                .padding(.top, 26)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(logGroups.enumerated()), id: \.element.id) { index, group in
                        DailyLogProjectCard(
                            group: group,
                            isRecent: index == 0,
                            isExpanded: expandedLogProjects.contains(group.id),
                            onToggle: { toggleLogGroup(group.id) },
                            onOpenLog: { selectedLog = $0 }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var dprContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recipients")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                Text("\(activeRecipientCount) active")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x16A34A))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            if isLoadingDpr && recipients.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 38)
            } else if recipients.isEmpty {
                Text("No recipients yet - tap + to add a WhatsApp recipient. Active recipients get the DPR PDF at 7:00 PM IST.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: 0x98A2B3))
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(recipients) { recipient in
                        DprRecipientRow(
                            recipient: recipient,
                            onToggle: { isActive in
                                Task { await toggleRecipient(recipient, isActive: isActive) }
                            },
                            onRemove: {
                                Task { await removeRecipient(recipient) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)

                Button {
                    showSendProjectPicker = true
                } label: {
                    Label("Send today's DPR now", systemImage: "paperplane.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Color(hex: 0x16A34A))
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            Text("Recent DPR History")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .padding(.horizontal, 16)
                .padding(.top, 10)

            if reports.isEmpty {
                Text("No DPR send history yet.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: 0x98A2B3))
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(reportGroups.enumerated()), id: \.element.id) { index, group in
                        DprProjectCard(
                            group: group,
                            isRecent: index == 0,
                            isExpanded: expandedDprProjects.contains(group.id),
                            onToggle: { toggleDprGroup(group.id) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @MainActor
    private func loadAll() async {
        await loadProjects()
        await loadLogs()
        await loadDpr()
    }

    @MainActor
    private func reloadCurrentTab() async {
        if selectedTab == .newEntry {
            await loadLogs()
        } else {
            await loadDpr()
        }
    }

    @MainActor
    private func loadProjects() async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            projects = try await ProjectConvexAPIService.getMyProjects(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadLogs() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        do {
            logs = try await DailyLogAPIService.loadRecentLogs(token: token, projects: projects)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadDpr() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoadingDpr = true
        defer { isLoadingDpr = false }
        do {
            let payload = try await DailyLogAPIService.getMyDpr(token: token, projects: projects)
            recipients = payload.0
            reports = payload.1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleRecipient(_ recipient: DprRecipient, isActive: Bool) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            try await DailyLogAPIService.updateDprRecipient(token: token, id: recipient.id, isActive: isActive)
            await loadDpr()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func removeRecipient(_ recipient: DprRecipient) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            try await DailyLogAPIService.removeDprRecipient(token: token, id: recipient.id)
            await loadDpr()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func sendDpr(for project: ProjectSummary) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            let result = try await DailyLogAPIService.sendDprNow(token: token, projectId: project.id)
            if result.skipped {
                showToast("No active recipients for \(project.displayName)")
            } else {
                showToast("DPR sent: \(result.sentCount) sent, \(result.failedCount) failed")
            }
            await loadDpr()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            toastMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.2)) {
                toastMessage = nil
            }
        }
    }

    private func toggleLogGroup(_ id: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if !expandedLogProjects.insert(id).inserted {
                expandedLogProjects.remove(id)
            }
        }
    }

    private func toggleDprGroup(_ id: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if !expandedDprProjects.insert(id).inserted {
                expandedDprProjects.remove(id)
            }
        }
    }
}

private enum DailyLogTab {
    case newEntry
    case dpr
}

private struct DailyLogSegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : Color(hex: 0x475467))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color(hex: 0x0B61CA))
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

private struct DailyLogProjectGroup: Identifiable {
    let id: String
    let projectName: String
    let logs: [DailyLogEntry]

    var latestLog: DailyLogEntry? { logs.first }

    static func make(from logs: [DailyLogEntry]) -> [DailyLogProjectGroup] {
        Dictionary(grouping: logs) { log in
            log.projectName?.nonBlank ?? "Other"
        }
        .map { name, entries in
            DailyLogProjectGroup(
                id: name,
                projectName: name,
                logs: entries.sorted(by: isLogNewer)
            )
        }
        .sorted {
            guard let lhs = $0.latestLog else { return false }
            guard let rhs = $1.latestLog else { return true }
            return isLogNewer(lhs, rhs)
        }
    }

    private static func isLogNewer(_ lhs: DailyLogEntry, _ rhs: DailyLogEntry) -> Bool {
        if lhs.date != rhs.date {
            return (lhs.date ?? "") > (rhs.date ?? "")
        }
        return (lhs.creationTime ?? 0) > (rhs.creationTime ?? 0)
    }
}

private struct DailyLogProjectCard: View {
    let group: DailyLogProjectGroup
    let isRecent: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpenLog: (DailyLogEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(group.projectName)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color(hex: 0x101828))
                                .lineLimit(2)

                            if isRecent {
                                Text("Recent")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x067647))
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(Color(hex: 0xECFDF3), in: Capsule())
                                    .overlay(Capsule().stroke(Color(hex: 0xABEFC6), lineWidth: 1))
                            }
                        }

                        Text(group.logs.count == 1 ? "1 entry" : "\(group.logs.count) entries")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B61CA))

                        if let latest = group.latestLog {
                            Text(lastActivityLabel(for: latest))
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color(hex: 0x667085))
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVStack(spacing: 10) {
                    ForEach(group.logs) { log in
                        Button {
                            onOpenLog(log)
                        } label: {
                            DailyLogEntryCard(log: log)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }
}

private struct DailyLogEntryCard: View {
    let log: DailyLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: weatherIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(weatherColor)
                    .frame(width: 20)

                Text(displayDate(log.date))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
            }

            Text(log.workSummary?.nonBlank ?? "-")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: 0x475467))
                .lineLimit(2)

            HStack(spacing: 6) {
                if let labourCount = log.labourCount {
                    DailyLogMetaPill(systemImage: "person.2.fill", text: "\(labourCount)")
                }
                if let labourHours = log.labourHours {
                    DailyLogMetaPill(systemImage: "clock.fill", text: "\(trimNumber(labourHours)) hrs")
                }
                if let conditions = log.siteConditions?.nonBlank {
                    DailyLogMetaPill(systemImage: nil, text: conditions.capitalized)
                }
                if let count = log.attachments?.count, count > 0 {
                    DailyLogMetaPill(systemImage: "photo.fill", text: "\(count)")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xF8F9FC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: 0xEEF0F4), lineWidth: 1)
        )
    }

    private var weatherIcon: String {
        switch log.weather?.lowercased() {
        case "sunny": return "sun.max.fill"
        case "cloudy": return "cloud.fill"
        case "rainy": return "cloud.rain.fill"
        case "windy": return "wind"
        case "stormy": return "cloud.bolt.rain.fill"
        default: return "calendar"
        }
    }

    private var weatherColor: Color {
        switch log.weather?.lowercased() {
        case "sunny": return Color(hex: 0xF59E0B)
        case "rainy", "stormy": return Color(hex: 0x0B61CA)
        case "windy", "cloudy": return Color(hex: 0x64748B)
        default: return Color(hex: 0x0B61CA)
        }
    }
}

private struct DailyLogMetaPill: View {
    let systemImage: String?
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color(hex: 0x475467))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color(hex: 0xF2F4F7), in: Capsule())
    }
}

private struct DprRecipientRow: View {
    let recipient: DprRecipient
    let onToggle: (Bool) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipient.name?.nonBlank ?? "Recipient")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                Text([recipient.normalizedPhone?.nonBlank ?? recipient.phone?.nonBlank, recipient.projectName?.nonBlank].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: 0x667085))
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(get: { recipient.isActive }, set: onToggle))
                .labelsHidden()
                .tint(Color(hex: 0x16A34A))

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0xB42318))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: 0xFEF3F2), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
    }
}

private struct DprProjectGroup: Identifiable {
    let id: String
    let projectName: String
    let reports: [DprReport]

    static func make(from reports: [DprReport]) -> [DprProjectGroup] {
        Dictionary(grouping: reports) { report in
            report.projectName?.nonBlank ?? "Other"
        }
        .map { name, entries in
            DprProjectGroup(
                id: name,
                projectName: name,
                reports: entries.sorted { ($0.date ?? "") > ($1.date ?? "") }
            )
        }
        .sorted { ($0.reports.first?.date ?? "") > ($1.reports.first?.date ?? "") }
    }
}

private struct DprProjectCard: View {
    let group: DprProjectGroup
    let isRecent: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(group.projectName)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color(hex: 0x101828))
                                .lineLimit(2)

                            if isRecent {
                                Text("Recent")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x067647))
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(Color(hex: 0xECFDF3), in: Capsule())
                                    .overlay(Capsule().stroke(Color(hex: 0xABEFC6), lineWidth: 1))
                            }
                        }

                        Text(group.reports.count == 1 ? "1 report" : "\(group.reports.count) reports")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B61CA))

                        if let date = group.reports.first?.date {
                            Text("Last sent: \(displayDate(date))")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: 0x667085))
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(group.reports) { report in
                        DprReportRow(report: report)
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }
}

private struct DprReportRow: View {
    let report: DprReport

    var body: some View {
        HStack(spacing: 10) {
            Text(displayDate(report.date))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(report.sentCount ?? 0) sent / \(report.failedCount ?? 0) failed")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle((report.failedCount ?? 0) > 0 ? Color(hex: 0xB54708) : Color(hex: 0x067647))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    (report.failedCount ?? 0) > 0 ? Color(hex: 0xFFFAEB) : Color(hex: 0xECFDF3),
                    in: Capsule()
                )
        }
        .padding(12)
        .background(Color(hex: 0xF8F9FC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xEEF0F4), lineWidth: 1))
    }
}

private struct DailyLogEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color(hex: 0xCBD5E1))
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: 0x667085))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 34)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

private struct CreateDailyLogSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let projects: [ProjectSummary]
    let onCreated: () async -> Void

    @State private var selectedProject: ProjectSummary?
    @State private var date = Date()
    @State private var weather: String?
    @State private var condition: String?
    @State private var workSummary = ""
    @State private var labourCount = ""
    @State private var labourHours = ""
    @State private var materials: [DailyLogMaterialDraft] = []
    @State private var equipment: [DailyLogEquipmentDraft] = []
    @State private var issues = ""
    @State private var safety = ""
    @State private var supervisorName = ""
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var media: [DailyLogUploadedMedia] = []
    @State private var materialCatalog: [DailyLogMaterialCatalogItem] = []
    @State private var isLoadingMaterials = false
    @State private var showProjectPicker = false
    @State private var showMaterialPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let weatherOptions = ["sunny", "cloudy", "rainy", "windy", "stormy"]
    private let conditionOptions = ["good", "fair", "poor"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 4) {
                        Text("New Entry")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0F172A))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        Text("Record today's site progress, labour and observations.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color(hex: 0x667085))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 4)

                    DailyLogPickerField(label: "Project *", value: selectedProject?.displayName ?? "Select project", isPlaceholder: selectedProject == nil) {
                        showProjectPicker = true
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        DailyLogFieldLabel("Date *")
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 48)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
                    }

                    Menu {
                        ForEach(weatherOptions, id: \.self) { option in
                            Button(option.capitalized) { weather = option }
                        }
                    } label: {
                        DailyLogSelectLikeField(label: "Weather", value: weather?.capitalized ?? "Select weather", isPlaceholder: weather == nil)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(conditionOptions, id: \.self) { option in
                            Button(option.capitalized) { condition = option }
                        }
                    } label: {
                        DailyLogSelectLikeField(label: "Site Conditions", value: condition?.capitalized ?? "Select condition", isPlaceholder: condition == nil)
                    }
                    .buttonStyle(.plain)

                    DailyLogTextEditor(label: "Work Done Description *", text: $workSummary, placeholder: "Describe the work done today...")

                    HStack(alignment: .top, spacing: 12) {
                        DailyLogTextField(label: "Labour Count", text: $labourCount, placeholder: "Labourers", keyboard: .numberPad)
                        DailyLogTextField(label: "Labour Hours", text: $labourHours, placeholder: "Hours", keyboard: .decimalPad)
                    }

                    sectionHeader(title: "Materials Used", actionTitle: isLoadingMaterials ? "Loading..." : "+ Add") {
                        Task { await openMaterialPicker() }
                    }
                    VStack(spacing: 8) {
                        ForEach($materials) { $item in
                            DailyLogMaterialRow(item: $item) {
                                materials.removeAll { $0.id == item.id }
                            }
                        }
                    }

                    sectionHeader(title: "Equipment Used", actionTitle: "+ Add") {
                        equipment.append(DailyLogEquipmentDraft())
                    }
                    VStack(spacing: 8) {
                        ForEach($equipment) { $item in
                            DailyLogEquipmentRow(item: $item) {
                                equipment.removeAll { $0.id == item.id }
                            }
                        }
                    }

                    DailyLogTextEditor(label: "Issues Encountered", text: $issues, placeholder: "Weather delays, supply issues...", minHeight: 72)
                    DailyLogTextEditor(label: "Safety Observations", text: $safety, placeholder: "Near-miss incidents, PPE compliance...", minHeight: 72)
                    DailyLogTextField(label: "Supervisor Name", text: $supervisorName, placeholder: "Supervisor name")

                    sectionHeader(title: "Photos & Videos", actionTitle: "+ Add") { }
                    PhotosPicker(selection: $selectedMediaItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(media.isEmpty ? "Add photos or videos" : "\(media.count) selected")
                            Spacer()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Color(hex: 0xEAF2FE), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if !media.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(media) { item in
                                    DailyLogSelectedMediaThumb(item: item) {
                                        media.removeAll { $0.id == item.id }
                                    }
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xDC2626))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            Button {
                Task { await submit() }
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                } else {
                    Text("Save Daily Log")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
            }
            .buttonStyle(.plain)
            .background(Color(hex: 0x16A34A), in: Capsule())
            .disabled(isSaving)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .background(Color.white)
        }
        .background(Color.white)
        .onAppear {
            if supervisorName.isEmpty {
                supervisorName = authStore.currentSession?.user.name?.nonBlank ?? ""
            }
        }
        .onChange(of: selectedMediaItems) { _, newItems in
            Task { await loadMedia(from: newItems) }
        }
        .sheet(isPresented: $showProjectPicker) {
            NativeSearchableSelectionSheet(
                title: "Select project",
                prompt: "Search projects",
                items: projects,
                selectedId: selectedProject?.id,
                searchText: { [$0.displayName, $0.status ?? ""].joined(separator: " ") },
                rowContent: { project, isSelected in
                    DailyLogProjectPickerRow(project: project, isSelected: isSelected)
                },
                onSelect: { project in
                    selectedProject = project
                }
            )
            .appLibraryNativeSheet([.medium, .large])
            .presentationBackground(Color.white)
        }
        .sheet(isPresented: $showMaterialPicker) {
            NativeSearchableSelectionSheet(
                title: "Select material",
                prompt: "Search materials",
                items: materialCatalog,
                selectedId: nil,
                searchText: { [$0.displayName, $0.subtitle].joined(separator: " ") },
                rowContent: { item, _ in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x101828))
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color(hex: 0x667085))
                        }
                    }
                    .padding(.vertical, 4)
                },
                onSelect: { item in
                    materials.append(DailyLogMaterialDraft(name: item.displayName, unit: item.unit?.nonBlank ?? ""))
                }
            )
            .appLibraryNativeSheet([.medium, .large])
            .presentationBackground(Color.white)
        }
    }

    private func sectionHeader(title: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
            Spacer()
            Button(actionTitle, action: action)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color(hex: 0xEAF2FE), in: Capsule())
                .disabled(isLoadingMaterials)
        }
        .padding(.top, 4)
    }

    @MainActor
    private func openMaterialPicker() async {
        if !materialCatalog.isEmpty {
            showMaterialPicker = true
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        isLoadingMaterials = true
        defer { isLoadingMaterials = false }
        do {
            materialCatalog = try await DailyLogAPIService.listMaterials(token: token)
            if materialCatalog.isEmpty {
                errorMessage = "No materials in the catalog"
            } else {
                showMaterialPicker = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMedia(from items: [PhotosPickerItem]) async {
        var loaded: [DailyLogUploadedMedia] = []
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { continue }
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
            let contentType = item.supportedContentTypes.first?.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
            var uploadData = data
            if !isVideo, let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.82) {
                uploadData = jpeg
            }
            loaded.append(
                DailyLogUploadedMedia(
                    data: uploadData,
                    contentType: isVideo ? contentType : "image/jpeg",
                    type: isVideo ? "video" : "image",
                    name: "daily_log_media_\(index + 1).\(isVideo ? "mp4" : "jpg")"
                )
            )
        }
        media = loaded
    }

    @MainActor
    private func submit() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Please login again."
            return
        }
        guard let selectedProject else {
            errorMessage = "Select a project"
            return
        }
        let work = workSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !work.isEmpty else {
            errorMessage = "Work Done Description is required"
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            var attachments: [DailyLogAttachment] = []
            for item in media {
                let uploadURL = try await HRConvexAPIService.generateUploadURL(token: token)
                let storageId = try await HRConvexAPIService.uploadFile(uploadURL: uploadURL, data: item.data, contentType: item.contentType)
                attachments.append(DailyLogAttachment(storageId: storageId, url: nil, type: item.type, name: item.name))
            }

            _ = try await DailyLogAPIService.createDailyLog(
                token: token,
                projectId: selectedProject.id,
                date: AppModuleFormatters.ymd.string(from: date),
                weather: weather,
                siteConditions: condition,
                workSummary: work,
                labourCount: Int(labourCount.trimmingCharacters(in: .whitespacesAndNewlines)),
                labourHours: Double(labourHours.trimmingCharacters(in: .whitespacesAndNewlines)),
                materialsUsed: materials.compactMap(\.payload),
                equipmentUsed: equipment.compactMap(\.payload),
                issuesEncountered: issues.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank,
                safetyObservations: safety.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank,
                supervisorName: supervisorName.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank,
                attachments: attachments
            )
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DprAddRecipientSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let projects: [ProjectSummary]
    let onCreated: () async -> Void

    @State private var selectedProject: ProjectSummary?
    @State private var selectedStaff: ConvexStaffListItem?
    @State private var staff: [ConvexStaffListItem] = []
    @State private var phone = ""
    @State private var showProjectPicker = false
    @State private var showStaffPicker = false
    @State private var isLoadingStaff = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Add DPR Recipient")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    DailyLogPickerField(label: "Project *", value: selectedProject?.displayName ?? "Select project", isPlaceholder: selectedProject == nil) {
                        showProjectPicker = true
                    }

                    DailyLogPickerField(label: "Staff", value: selectedStaff?.displayName ?? (isLoadingStaff ? "Loading staff..." : "Select staff..."), isPlaceholder: selectedStaff == nil) {
                        Task { await openStaffPicker() }
                    }

                    DailyLogTextField(label: "WhatsApp number", text: $phone, placeholder: "9876543210", keyboard: .phonePad)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xDC2626))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            Button {
                Task { await addRecipient() }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                } else {
                    Text("Add Recipient")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
            }
            .buttonStyle(.plain)
            .background(Color(hex: 0x16A34A), in: Capsule())
            .disabled(isSubmitting)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .background(Color.white)
        }
        .background(Color.white)
        .sheet(isPresented: $showProjectPicker) {
            NativeSearchableSelectionSheet(
                title: "Select project",
                prompt: "Search projects",
                items: projects,
                selectedId: selectedProject?.id,
                searchText: { [$0.displayName, $0.status ?? ""].joined(separator: " ") },
                rowContent: { project, isSelected in
                    DailyLogProjectPickerRow(project: project, isSelected: isSelected)
                },
                onSelect: { project in
                    selectedProject = project
                }
            )
            .appLibraryNativeSheet([.medium, .large])
            .presentationBackground(Color.white)
        }
        .sheet(isPresented: $showStaffPicker) {
            NativeSearchableSelectionSheet(
                title: "Select staff",
                prompt: "Search staff",
                items: staff,
                selectedId: selectedStaff?.id,
                searchText: { [$0.displayName, $0.phone ?? "", $0.designation ?? ""].joined(separator: " ") },
                rowContent: { item, isSelected in
                    HStack(spacing: 12) {
                        Text(item.initials)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .frame(width: 34, height: 34)
                            .background(Color(hex: 0xEAF2FE), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x101828))
                            Text([item.designation?.nonBlank, item.phone?.nonBlank].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color(hex: 0x667085))
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(hex: 0x0B61CA))
                        }
                    }
                    .padding(.vertical, 4)
                },
                onSelect: { item in
                    selectedStaff = item
                    if let staffPhone = item.phone?.nonBlank {
                        phone = staffPhone
                    }
                }
            )
            .appLibraryNativeSheet([.medium, .large])
            .presentationBackground(Color.white)
        }
    }

    @MainActor
    private func openStaffPicker() async {
        if !staff.isEmpty {
            showStaffPicker = true
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        isLoadingStaff = true
        defer { isLoadingStaff = false }
        do {
            let page = try await HRConvexAPIService.getStaffPaginated(token: token, numItems: 100, status: "active")
            staff = page.page
            showStaffPicker = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func addRecipient() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Please login again."
            return
        }
        guard let selectedProject else {
            errorMessage = "Select a project"
            return
        }
        let digits = phone.filter(\.isNumber)
        guard !digits.isEmpty else {
            errorMessage = "Enter a number"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await DailyLogAPIService.addDprRecipient(
                token: token,
                projectId: selectedProject.id,
                staffId: selectedStaff?.id,
                name: selectedStaff?.displayName ?? digits,
                phone: digits
            )
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DailyLogDetailSheet: View {
    let log: DailyLogEntry

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text(displayDate(log.date))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                detailField("Project", log.projectName)
                detailField("Weather", log.weather?.capitalized)
                detailField("Site Conditions", log.siteConditions?.capitalized)
                detailField("Work Done", log.workSummary, multiline: true)

                let labour = [
                    log.labourCount.map { "\($0) labourers" },
                    log.labourHours.map { "\(trimNumber($0)) hrs" }
                ].compactMap { $0 }.joined(separator: " · ")
                detailField("Labour", labour.nonBlank)

                if let materials = log.materialsUsed, !materials.isEmpty {
                    detailField(
                        "Materials Used",
                        materials.map { "- \($0.name) - \(trimNumber($0.quantity))\($0.unit.map { " \($0)" } ?? "")" }.joined(separator: "\n"),
                        multiline: true
                    )
                }

                if let equipment = log.equipmentUsed, !equipment.isEmpty {
                    detailField(
                        "Equipment Used",
                        equipment.map { "- \($0.name) - \(trimNumber($0.hours)) hrs" }.joined(separator: "\n"),
                        multiline: true
                    )
                }

                detailField("Issues Encountered", log.issuesEncountered, multiline: true)
                detailField("Safety Observations", log.safetyObservations, multiline: true)
                detailField("Supervisor", log.supervisorName)
                detailField("Created By", log.createdBy)

                Text("Photos & Videos")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .padding(.top, 8)

                if let attachments = log.attachments, !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attachments) { attachment in
                                DailyLogAttachmentThumb(attachment: attachment)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xCBD5E1))
                        Text("No photos or videos")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0x98A2B3))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(Color(hex: 0xF9FAFB), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.white)
    }

    private func detailField(_ label: String, _ value: String?, multiline: Bool = false) -> some View {
        Group {
            if let value = value?.nonBlank {
                VStack(alignment: .leading, spacing: 6) {
                    DailyLogFieldLabel(label)
                    Text(value)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: multiline ? 72 : 46, alignment: multiline ? .topLeading : .center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, multiline ? 12 : 0)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xEAECF0), lineWidth: 1))
                }
            }
        }
    }
}

private struct DailyLogProjectPickerRow: View {
    let project: ProjectSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0x64748B))
                .frame(width: 34, height: 34)
                .background(isSelected ? Color(hex: 0xEAF2FE) : Color(hex: 0xF1F5F9), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                if let status = project.status?.nonBlank {
                    Text(status.capitalized)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DailyLogPickerField: View {
    let label: String
    let value: String
    let isPlaceholder: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DailyLogFieldLabel(label)
            Button(action: action) {
                HStack(spacing: 10) {
                    Text(value)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isPlaceholder ? Color(hex: 0x98A2B3) : Color(hex: 0x101828))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DailyLogSelectLikeField: View {
    let label: String
    let value: String
    let isPlaceholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DailyLogFieldLabel(label)
            HStack(spacing: 10) {
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isPlaceholder ? Color(hex: 0x98A2B3) : Color(hex: 0x101828))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
        }
    }
}

private struct DailyLogTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DailyLogFieldLabel(label)
            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .medium))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
        }
    }
}

private struct DailyLogTextEditor: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DailyLogFieldLabel(label)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: 0xC2C7CF))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $text)
                    .font(.system(size: 15, weight: .medium))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(minHeight: minHeight)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
        }
    }
}

private struct DailyLogMaterialRow: View {
    @Binding var item: DailyLogMaterialDraft
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                if !item.unit.isEmpty {
                    Text(item.unit)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("Qty", text: $item.quantity)
                .font(.system(size: 13, weight: .medium))
                .keyboardType(.decimalPad)
                .padding(.horizontal, 10)
                .frame(width: 90, height: 42)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
            removeButton
        }
        .padding(10)
        .background(Color(hex: 0xF9FAFB), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: 0x667085))
                .frame(width: 28, height: 28)
                .background(Color(hex: 0xF2F4F7), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct DailyLogEquipmentRow: View {
    @Binding var item: DailyLogEquipmentDraft
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Equipment", text: $item.name)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
            TextField("Hours", text: $item.hours)
                .font(.system(size: 13, weight: .medium))
                .keyboardType(.decimalPad)
                .padding(.horizontal, 10)
                .frame(width: 88, height: 42)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: 0xF2F4F7), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DailyLogSelectedMediaThumb: View {
    let item: DailyLogUploadedMedia
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if item.type == "image", let image = UIImage(data: item.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color(hex: 0x101828)
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.75), in: Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }
}

private struct DailyLogAttachmentThumb: View {
    let attachment: DailyLogAttachment
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if attachment.type == "video", let url = resolvedURL {
                openURL(url)
            }
        } label: {
            ZStack {
                if let url = resolvedURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color(hex: 0xF2F4F7)
                        }
                    }
                } else {
                    Color(hex: 0xF2F4F7)
                }
                if attachment.type == "video" {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(0.45), in: Circle())
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var resolvedURL: URL? {
        if let url = attachment.url?.nonBlank, let resolved = URL(string: url) {
            return resolved
        }
        var components = URLComponents(string: "\(AppConfig.baseURL)/api/storage/serve")
        components?.queryItems = [URLQueryItem(name: "storageId", value: attachment.storageId)]
        return components?.url
    }
}

private struct DailyLogFieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: 0x667085))
    }
}

private struct DailyLogMaterialDraft: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var unit: String
    var quantity: String = ""

    var payload: DailyLogMaterial? {
        let qty = Double(quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, qty > 0 else { return nil }
        return DailyLogMaterial(name: name, quantity: qty, unit: unit.nonBlank)
    }
}

private struct DailyLogEquipmentDraft: Identifiable, Hashable {
    let id = UUID()
    var name: String = ""
    var hours: String = ""

    var payload: DailyLogEquipment? {
        let value = Double(hours.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, value > 0 else { return nil }
        return DailyLogEquipment(name: trimmedName, hours: value)
    }
}

private func displayDate(_ iso: String?) -> String {
    guard let iso = iso?.nonBlank else { return "Daily Log" }
    if let date = AppModuleFormatters.ymd.date(from: iso) {
        return AppModuleFormatters.day.string(from: date)
    }
    return iso
}

private func lastActivityLabel(for log: DailyLogEntry) -> String {
    let day = displayDate(log.date)
    guard let creationTime = log.creationTime else { return "Last: \(day)" }
    let time = Date(timeIntervalSince1970: creationTime / 1_000)
        .formatted(date: .omitted, time: .shortened)
    return "Last: \(day) - \(time)"
}

private func trimNumber(_ value: Double) -> String {
    value == Double(Int(value)) ? String(Int(value)) : String(value)
}
