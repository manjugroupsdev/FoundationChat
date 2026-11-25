import SwiftUI

/// SV approvals: out-of-station, immediate-pickup and direct site visits a
/// telecaller (or the CP form) handed to a GM. Each is that GM's daily task
/// (sourceReferenceType out_of_station_handoff). Approve completes it, which
/// creates the site visit on the server; Reject cancels it.
///
/// Super admins get tabs: Mine = assigned to me; Team = my team's GMs (task list
/// teamIds); All = every open one (scope "all"). Everyone else gets one list of
/// their own + their team's approvals with no tab row. The server lets the GM, their
/// supervisor, the requester or a super admin reject, but only the assigned GM,
/// an admin or a `marketing.siteVisits.confirm` holder approve; anyone else sees
/// whose turn it is. Parity with Mconnect `SvApprovalQueueFragment`.
struct SvApprovalQueueView: View {
    @Environment(AuthStore.self) private var authStore

    private enum Tab: String, CaseIterable, Identifiable {
        case mine = "Mine", team = "Team", all = "All"
        var id: String { rawValue }
    }

    @State private var queue: SvApprovalQueue?
    @State private var tab: Tab = .mine
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var busyItemId: String?
    @State private var rejectTarget: DailyTask?

    /// Open SV approvals assigned to the signed-in GM (App Library badge).
    /// A fresh read; the queue screen opened right after shares it.
    @MainActor
    static func loadPending(authStore: AuthStore) async throws -> [DailyTask] {
        try await loadQueue(authStore: authStore, reuse: false)?.mine ?? []
    }

    // One task-list read at a time, shared by the badge and this screen: a
    // caller arriving while a read runs awaits it instead of firing a second
    // heavy read (the server refused the duplicate with 429 under load).
    @MainActor private static var inFlightRead: (key: String, task: Task<DailyTaskManagerPayload, Error>)?
    @MainActor private static var lastRead: (key: String, at: Date, payload: DailyTaskManagerPayload)?

    @MainActor
    private static func readTasks(token: String, me: String, reuse: Bool) async throws -> DailyTaskManagerPayload {
        let today = AppModuleFormatters.ymd.string(from: Date())
        let key = "\(me)|\(today)"
        if let running = inFlightRead, running.key == key {
            return try await running.task.value
        }
        if reuse, let last = lastRead, last.key == key, SvApprovalLoadRules.isFresh(fetchedAt: last.at, now: Date()) {
            return last.payload
        }
        // The queue is filtered from the task list on the phone, so read the
        // largest page the server allows (500); the 200 default dropped older
        // approvals on busy days.
        let task = Task { @MainActor in
            try await TasksConvexAPIService.getTaskManagerTasks(
                token: token,
                today: today,
                limit: SvCpFlowRules.svApprovalTaskListLimit
            )
        }
        inFlightRead = (key, task)
        defer { if inFlightRead?.key == key { inFlightRead = nil } }
        let payload = try await task.value
        lastRead = (key, Date(), payload)
        return payload
    }

    /// Mine / Team / All from one task-list call, earliest visit first.
    /// `reuse`: accept a read from moments ago (the App Library badge's).
    @MainActor
    static func loadQueue(authStore: AuthStore, reuse: Bool = false) async throws -> SvApprovalQueue? {
        guard let token = authStore.currentSession?.token,
              let me = authStore.currentSession?.user.staffId?.nonBlank
                ?? authStore.currentSession?.user._id.nonBlank
        else { return nil }
        let payload = try await readTasks(token: token, me: me, reuse: reuse)
        let open = payload.tasks
            .filter {
                $0.sourceReferenceType == "out_of_station_handoff"
                    && ($0.status == "pending" || $0.status == "in-progress")
                    && !SvApprovalDecisions.isRecentlyDecided($0.id)
            }
            .sorted { ($0.deadline ?? "") < ($1.deadline ?? "") }
        let isAll = payload.scope == "all"
        let isSuperAdmin = isAll || authStore.currentSession?.user.role?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "super-admin"
        return SvApprovalQueue(
            me: me,
            mine: open.filter { $0.assignedTo == me },
            team: open.filter { $0.assignedTo != me && payload.teamIds.contains($0.assignedTo ?? "") },
            all: isAll ? open : [],
            isAll: isAll,
            showTeam: isSuperAdmin,
            singleList: !isSuperAdmin,
            canApproveAny: isAll || authStore.hasPermission("marketing.siteVisits.confirm")
        )
    }

    /// Super admins: Mine / Team / All. Everyone else: one list (own + team), no tabs.
    private var tabs: [Tab] {
        guard let queue, !queue.singleList else { return [.mine] }
        return [.mine] + (queue.showTeam ? [.team] : []) + (queue.isAll ? [.all] : [])
    }

    private func items(_ t: Tab) -> [DailyTask] {
        guard let queue else { return [] }
        if queue.singleList {
            return (queue.mine + queue.team).sorted { ($0.deadline ?? "") < ($1.deadline ?? "") }
        }
        switch t {
        case .mine: return queue.mine
        case .team: return queue.team
        case .all: return queue.all
        }
    }

    var body: some View {
        ScrollView {
            if tabs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs) { t in
                            Button { tab = t } label: {
                                Text("\(t.rawValue)  \(items(t).count)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(tab == t ? Color.white : Color.appPrimaryText)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(
                                        Capsule().fill(tab == t ? Color(hex: 0x0B61CA) : Color.appSurface)
                                    )
                                    .overlay(Capsule().stroke(tab == t ? Color.clear : Color(hex: 0xE4E7EC)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 12)
            }

            if isLoading && queue == nil {
                skeletonList
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            } else if items(tab).isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(items(tab)) { task in
                        SvApprovalCard(
                            task: task,
                            showGm: task.assignedTo != queue?.me,
                            canDecide: queue?.canDecide(task) ?? false,
                            canApprove: queue?.canApprove(task) ?? false,
                            busy: busyItemId == task.id,
                            disabled: busyItemId != nil,
                            onApprove: { Task { await decide(task, status: "completed") } },
                            onReject: { rejectTarget = task }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .refreshable { await load(reuse: false) }
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
        // First open shares the task list the App Library badge just read.
        .task { if queue == nil { await load(reuse: true) } }
        // Same as the web handoff dialog: a rejection needs a reason. Shared
        // ActionReasonSheet, as on the CP outcome sheet's Reject SV.
        .sheet(item: $rejectTarget) { target in
            ActionReasonSheet(
                title: "Reject site visit",
                subtitle: "Add a reason for rejecting \(SvApprovalFormatting.clientName(target))'s site visit.",
                fieldLabel: "Rejection reason",
                placeholder: "Why is this site visit being rejected?",
                submitTitle: "Reject",
                submitKind: .danger,
                missingReasonError: "Please share a reason for the rejection",
                savingTitle: "Rejecting",
                isSaving: busyItemId == target.id,
                onSubmit: { reason in
                    if await decide(target, status: "cancelled", reason: reason) {
                        rejectTarget = nil
                    }
                }
            )
            .appLibraryNativeSheet([.medium, .large])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.appTertiaryText)
                .padding(.top, 72)
            Text(errorMessage == nil ? "No site visits to approve" : "Couldn't load")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.appPrimaryText)
                .padding(.top, 14)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 6)
                Button("Try again") { Task { await load(reuse: false) } }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var skeletonList: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        RoundedRectangle(cornerRadius: 6).frame(width: 150, height: 16)
                        Spacer()
                        Capsule().frame(width: 90, height: 20)
                    }
                    RoundedRectangle(cornerRadius: 5).frame(width: 130, height: 12)
                    RoundedRectangle(cornerRadius: 5).frame(width: 190, height: 12)
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 12).frame(height: 44)
                        RoundedRectangle(cornerRadius: 12).frame(height: 44)
                    }
                    .padding(.top, 4)
                }
                .foregroundStyle(Color(hex: 0xE4E7EC))
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.appSurface))
            }
        }
    }

    @MainActor
    private func load(reuse: Bool) async {
        isLoading = queue == nil
        defer { isLoading = false }
        var attempt = 0
        while true {
            do {
                try await apply(Self.loadQueue(authStore: authStore, reuse: reuse && attempt == 0))
                return
            } catch HRConvexAPIError.httpStatus(let status, _) where SvApprovalLoadRules.isServerBusy(httpStatus: status) {
                // Server busy: the same read works a moment later. Keep the
                // skeleton (or the list) up and ask again quietly; show
                // "Couldn't load" only once the automatic retries run out.
                guard let wait = SvApprovalLoadRules.retryDelaySeconds(attempt: attempt), !Task.isCancelled else {
                    if queue == nil { errorMessage = "The server is busy right now. Try again in a moment." }
                    return
                }
                attempt += 1
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
            } catch {
                if queue == nil { errorMessage = FloaterText.notice(for: error)?.text ?? error.localizedDescription }
                return
            }
        }
    }

    @MainActor
    private func apply(_ next: SvApprovalQueue?) {
        let first = queue == nil
        queue = next
        errorMessage = nil
        if first, let next {
            tab = !next.mine.isEmpty ? .mine
                : (next.showTeam && !next.team.isEmpty) ? .team
                : (next.isAll && !next.all.isEmpty) ? .all
                : .mine
        }
        if !tabs.contains(tab) { tab = .mine }
    }

    @MainActor
    /// Returns true when the server accepted the decision.
    @discardableResult
    private func decide(_ task: DailyTask, status: String, reason: String? = nil) async -> Bool {
        guard busyItemId == nil, let token = authStore.currentSession?.token else { return false }
        let rejectReason = RequiredReason.normalized(reason)
        if status == "cancelled" && rejectReason == nil {
            Floater.shared.error("Please share a reason for the rejection")
            return false
        }
        busyItemId = task.id
        defer { busyItemId = nil }
        do {
            try await TasksConvexAPIService.updateDailyTaskStatus(
                token: token, id: task.id, status: status,
                reason: status == "cancelled" ? rejectReason : nil
            )
            Floater.shared.success(status == "completed" ? "Site visit approved" : "Site visit rejected")
            SvApprovalDecisions.markDecided(task.id)
            queue = queue?.without(task.id)
            return true
        } catch {
            Floater.shared.show(error: error)
            return false
        }
    }
}

struct SvApprovalQueue: Equatable {
    let me: String
    var mine: [DailyTask]
    var team: [DailyTask]
    var all: [DailyTask]
    let isAll: Bool
    let showTeam: Bool
    /// Not a super admin: own + team approvals in one list, no tab row.
    var singleList: Bool = false

    /// Admin, super-admin scope or `marketing.siteVisits.confirm`: may approve
    /// a handoff assigned to another GM.
    var canApproveAny: Bool = false

    /// Same rule as the server (canChangeDailyTaskStatus for handoff tasks).
    /// Covers Reject; Approve is narrower, see `canApprove`.
    func canDecide(_ task: DailyTask) -> Bool {
        task.assignedTo == me || task.supervisorId == me || task.assignedBy == me || isAll
    }

    /// The server lets only the handoff's assigned GM, an admin or a holder of
    /// `marketing.siteVisits.confirm` approve (dailyTasks.updateStatus).
    func canApprove(_ task: DailyTask) -> Bool {
        SvCpFlowRules.canApproveSvHandoff(assignedTo: task.assignedTo, me: me, canApproveAny: canApproveAny)
    }

    func without(_ id: String) -> SvApprovalQueue {
        var copy = self
        copy.mine.removeAll { $0.id == id }
        copy.team.removeAll { $0.id == id }
        copy.all.removeAll { $0.id == id }
        return copy
    }
}

private struct SvApprovalCard: View {
    let task: DailyTask
    let showGm: Bool
    let canDecide: Bool
    let canApprove: Bool
    let busy: Bool
    let disabled: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(SvApprovalFormatting.clientName(task))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appPrimaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                let colors = SvApprovalFormatting.routeColors(task)
                Text(SvApprovalFormatting.routeLabel(task))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: colors.fg))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.adaptiveTint(colors.bg), in: Capsule())
            }

            line("calendar", SvApprovalFormatting.visitDate(task.deadline) ?? "No date", primary: true)
            if let requester = [task.assignedByName?.nonBlank, task.assignedByDesignation?.nonBlank]
                .compactMap({ $0 }).joined(separator: " · ").nonBlank {
                line("person", requester)
            }
            if showGm, let gm = task.assignedToName?.nonBlank {
                line("building.2", "GM \(gm)")
            }
            if let notes = task.description?.nonBlank {
                Text(notes)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 10)
            }

            if canDecide {
                HStack(spacing: 10) {
                    Button(action: onReject) {
                        Text("Reject")
                    }
                    .buttonStyle(.mconnect(.dangerOutline))
                    .disabled(disabled)

                    if canApprove {
                        Button(action: onApprove) {
                            ButtonLoadingLabel(
                                "Approve",
                                loading: busy,
                                loadingTitle: "Approving",
                                font: .system(size: 16, weight: .semibold)
                            )
                        }
                        .buttonStyle(.mconnect(.success))
                        .disabled(disabled)
                    }
                }
                .padding(.top, 14)
                if !canApprove {
                    Text("Only \(task.assignedToName?.nonBlank ?? "the assigned GM") can approve")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appSecondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            } else {
                Text("Waiting for \(task.assignedToName?.nonBlank ?? "the GM") to approve")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 14)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.appSurface)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
    }

    private func line(_ icon: String, _ value: String, primary: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.appTertiaryText)
                .frame(width: 16)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(primary ? Color.appPrimaryText : Color.appSecondaryText)
                .lineLimit(1)
        }
        .padding(.top, 8)
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

    /// Text and fill per route.
    static func routeColors(_ task: DailyTask) -> (fg: UInt, bg: UInt) {
        switch task.label {
        case "immediate_pickup": return (0xB42318, 0xFEF3F2)
        case "direct_sv": return (0x175CD3, 0xEFF8FF)
        default: return (0xB54708, 0xFFFAEB)
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
