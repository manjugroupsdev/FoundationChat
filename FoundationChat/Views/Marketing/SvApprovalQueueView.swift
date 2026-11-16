import SwiftUI

/// GM queue for site visits waiting on their approval: out-of-station,
/// immediate-pickup and direct SVs a telecaller (or the CP form) handed to the
/// GM. Each one is the GM's "SV approval" daily task (sourceReferenceType
/// out_of_station_handoff, assigned to them). Approve completes that task,
/// which on the server creates the real site visit (the same path as the web
/// Fixed tab and the Task Manager); Reject cancels it, closing the handoff.
///
/// Parity with Mconnect `SvApprovalQueueFragment`.
struct SvApprovalQueueView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var items: [DailyTask] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var busyItemId: String?
    @State private var rejectTarget: DailyTask?

    /// Open SV approvals assigned to the signed-in GM, earliest visit first.
    @MainActor
    static func loadPending(authStore: AuthStore) async throws -> [DailyTask] {
        guard let token = authStore.currentSession?.token,
              let me = authStore.currentSession?.user.staffId?.nonBlank
                ?? authStore.currentSession?.user._id.nonBlank
        else { return [] }
        let today = AppModuleFormatters.ymd.string(from: Date())
        let payload = try await TasksConvexAPIService.getTaskManagerTasks(token: token, today: today)
        return payload.tasks
            .filter {
                $0.sourceReferenceType == "out_of_station_handoff"
                    && $0.assignedTo == me
                    && ($0.status == "pending" || $0.status == "in-progress")
                    && !SvApprovalDecisions.isRecentlyDecided($0.id)
            }
            .sorted { ($0.deadline ?? "") < ($1.deadline ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Site visits to approve")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.appPrimaryText)
                Text("Out-of-station, immediate-pickup and direct site visits waiting on you. Approve creates the site visit; reject sends it back.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appSecondaryText)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if isLoading && items.isEmpty {
                skeletonList
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else if items.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(items) { task in
                        SvApprovalCard(
                            task: task,
                            busy: busyItemId == task.id,
                            disabled: busyItemId != nil,
                            onApprove: { Task { await decide(task, status: "completed") } },
                            onReject: { rejectTarget = task }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .refreshable { await load() }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .navigationTitle("SV Approvals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appElevatedSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("SV Approvals")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.appPrimaryText)
            }
        }
        .task { if !hasLoaded { await load() } }
        .alert("Reject this site visit?", isPresented: Binding(
            get: { rejectTarget != nil },
            set: { if !$0 { rejectTarget = nil } }
        )) {
            Button("Keep", role: .cancel) { rejectTarget = nil }
            Button("Reject", role: .destructive) {
                if let target = rejectTarget {
                    rejectTarget = nil
                    Task { await decide(target, status: "cancelled") }
                }
            }
        } message: {
            let who = rejectTarget?.assignedByName?.nonBlank ?? "the telecaller"
            let client = rejectTarget.map(SvApprovalFormatting.clientName) ?? "this client"
            Text("The request from \(who) for \(client) is closed. No site visit is created.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Color.appTertiaryText)
                .padding(.top, 64)
            Text(errorMessage == nil ? "Nothing to Approve" : "Couldn't Load")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appPrimaryText)
                .padding(.top, 16)
            Text(errorMessage ?? "Site visits waiting on your approval will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 32)
                .padding(.top, 8)
            if errorMessage != nil {
                Button("Try again") { Task { await load() } }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var skeletonList: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: 0xE4E7EC))
                    .frame(height: 200)
                    .redacted(reason: .placeholder)
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = items.isEmpty
        defer { isLoading = false; hasLoaded = true }
        do {
            items = try await Self.loadPending(authStore: authStore)
            errorMessage = nil
        } catch {
            if items.isEmpty { errorMessage = FloaterText.notice(for: error)?.text ?? error.localizedDescription }
        }
    }

    @MainActor
    private func decide(_ task: DailyTask, status: String) async {
        guard busyItemId == nil, let token = authStore.currentSession?.token else { return }
        busyItemId = task.id
        defer { busyItemId = nil }
        do {
            try await TasksConvexAPIService.updateDailyTaskStatus(token: token, id: task.id, status: status)
            Floater.shared.success(status == "completed" ? "Site visit approved and created" : "Site visit rejected")
            SvApprovalDecisions.markDecided(task.id)
            items.removeAll { $0.id == task.id }
            await load()
        } catch {
            Floater.shared.show(error: error)
        }
    }
}

private struct SvApprovalCard: View {
    let task: DailyTask
    let busy: Bool
    let disabled: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(SvApprovalFormatting.clientName(task))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appPrimaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(SvApprovalFormatting.routeLabel(task))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xB54708))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.adaptiveTint(0xFFFAEB), in: Capsule())
                    .overlay(Capsule().stroke(Color(hex: 0xFEDF89)))
            }

            fact("Visit date", SvApprovalFormatting.visitDate(task.deadline))
            fact("Requested by", [task.assignedByName?.nonBlank, task.assignedByDesignation?.nonBlank]
                .compactMap { $0 }
                .joined(separator: " · ")
                .nonBlank)
            fact("Requested on", task.creationTime.map(SvApprovalFormatting.stamp))
            fact("Notes", task.description?.nonBlank)

            HStack(spacing: 8) {
                Button(action: onReject) {
                    Text("Reject")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xB42318))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.adaptiveTint(0xFEE4E2), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(disabled)

                Button(action: onApprove) {
                    ButtonLoadingLabel(
                        "Approve",
                        loading: busy,
                        loadingTitle: "Approving",
                        font: .system(size: 14, weight: .semibold)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(hex: 0x169B2F), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appSurface)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func fact(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.appSecondaryText)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
        }
    }
}

/// The task list is cached for 60 s (server read cache + `Cache-Control:
/// max-age=60` on the phone), so a reload right after Approve / Reject can
/// still list the decided visit. Hide decided ones for a few minutes so the GM
/// never sees it come back and taps it twice.
@MainActor
private enum SvApprovalDecisions {
    private static var decidedAt: [String: Date] = [:]
    private static let hideFor: TimeInterval = 5 * 60

    static func markDecided(_ id: String) {
        decidedAt[id] = Date()
    }

    static func isRecentlyDecided(_ id: String) -> Bool {
        let now = Date()
        decidedAt = decidedAt.filter { now.timeIntervalSince($0.value) < hideFor }
        return decidedAt[id] != nil
    }
}

private enum SvApprovalFormatting {
    /// "Out-of-station SV: Ramesh" → "Ramesh".
    static func clientName(_ task: DailyTask) -> String {
        if let name = task.taskName?.nonBlank {
            if let range = name.range(of: ": ") {
                let client = name[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !client.isEmpty { return client }
            }
            return name
        }
        return task.title?.nonBlank ?? "Client"
    }

    static func routeLabel(_ task: DailyTask) -> String {
        switch task.label {
        case "immediate_pickup": return "Immediate pickup"
        case "direct_sv": return "Direct SV"
        case "out_of_station": return "Out of station"
        default:
            guard let title = task.title?.nonBlank else { return "Site visit" }
            return title.hasSuffix(" Approval") ? String(title.dropLast(" Approval".count)) : title
        }
    }

    static func visitDate(_ ymd: String?) -> String? {
        guard let ymd = ymd?.nonBlank else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(ymd.prefix(10))) else { return ymd }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "EEE, d MMM yyyy"
        return out.string(from: date)
    }

    static func stamp(_ ms: Double) -> String {
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "d MMM, h:mm a"
        return out.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}
