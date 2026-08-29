import Foundation
import SwiftUI

struct StaffSecurityView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var mode: SecurityMode = .deviceReset
    @State private var staff: [ConvexStaffListItem] = []
    @State private var logins: [ActiveStaffLogin] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loadMoreFailed = false
    @State private var loadMoreRetryTask: Task<Void, Never>?
    @State private var loadMoreRetryRound = 0
    @State private var staffCursor: String?
    @State private var staffPaginationDone = false
    @State private var errorMessage: String?
    @State private var selectedStaff: ConvexStaffListItem?
    @State private var selectedLogin: ActiveStaffLogin?
    @State private var pendingLogout: ActiveStaffLogin?

    private var isSuperAdmin: Bool {
        authStore.currentSession?.user.role?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "super-admin"
    }

    private func holds(_ permission: String) -> Bool {
        isSuperAdmin || authStore.iamPermissions.contains(permission)
    }

    private var availableModes: [SecurityMode] {
        SecurityMode.allCases.filter { candidate in
            switch candidate {
            case .deviceReset: return holds("staff.resetDeviceBinding")
            case .staffLogin: return holds("settings.staffLogin.view")
            case .passwordReset: return holds("staff.password")
            }
        }
    }

    private var visibleStaff: [ConvexStaffListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return staff }
        return staff.filter { row in
            [row.name, row.employeeId, row.phone, row.designation, row.department]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    private var visibleLogins: [ActiveStaffLogin] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return logins }
        return logins.filter { row in
            [row.name, row.employeeId, row.phone, row.designation, row.department]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    var body: some View {
        Group {
            if availableModes.isEmpty {
                ContentUnavailableView(
                    "Security access required",
                    systemImage: "lock.shield",
                    description: Text("Ask an administrator to grant the relevant IAM permission.")
                )
            } else {
                List {
                    Section {
                        Picker("Security mode", selection: $mode) {
                            ForEach(availableModes) { item in
                                Text(item.shortTitle).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(mode.helpText)
                    }

                    if isLoading && currentRowsAreEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    } else if mode == .staffLogin {
                        loginRows
                    } else {
                        staffRows
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Security")
        .searchable(text: $searchText, prompt: "Search staff")
        .refreshable {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if mode != .staffLogin, !query.isEmpty {
                await searchStaff(query)
            } else {
                await reload()
            }
        }
        .task {
            guard let first = availableModes.first else { return }
            if !availableModes.contains(mode) { mode = first }
            await reload()
        }
        .task(id: searchText) {
            guard mode != .staffLogin else { return }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                await reload()
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await searchStaff(query)
        }
        .onChange(of: mode) { _, _ in
            searchText = ""
            Task { await reload() }
        }
        .onDisappear { loadMoreRetryTask?.cancel() }
        .sheet(item: $selectedStaff) { row in
            StaffSecurityDetailSheet(
                staff: row,
                showDeviceActions: holds("staff.resetDeviceBinding"),
                showPasswordActions: holds("staff.password")
            )
        }
        .sheet(item: $selectedLogin) { row in
            StaffLoginDevicesSheet(
                login: row,
                canLogout: holds("settings.staffLogin.create"),
                onChanged: { Task { await reload() } }
            )
        }
        .confirmationDialog(
            "Log out everywhere?",
            isPresented: Binding(
                get: { pendingLogout != nil },
                set: { if !$0 { pendingLogout = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Log out web and mobile", role: .destructive) {
                guard let row = pendingLogout, let staffId = row.staffId else { return }
                pendingLogout = nil
                Task { await logoutEverywhere(staffId: staffId) }
            }
            Button("Cancel", role: .cancel) { pendingLogout = nil }
        } message: {
            Text("This ends every active session for \(pendingLogout?.name ?? "this staff member").")
        }
        .alert("Security", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var staffRows: some View {
        if visibleStaff.isEmpty && !isLoading {
            ContentUnavailableView.search(text: searchText)
        } else {
            Section("Staff") {
                ForEach(visibleStaff) { row in
                    Button { selectedStaff = row } label: {
                        HStack(spacing: 12) {
                            StaffSecurityAvatar(name: row.displayName)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.displayName).font(.headline).foregroundStyle(.primary)
                                Text([row.employeeId, row.designation, row.department]
                                    .compactMap { $0?.securityNonBlank }
                                    .joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if row.id == visibleStaff.last?.id {
                            Task { await loadNextStaffPage() }
                        }
                    }
                }

            }
        }

        if !staffPaginationDone {
            Section {
                HStack {
                    Spacer()
                    if loadMoreFailed {
                        Button("Reconnecting automatically. Retry now") {
                            loadMoreRetryTask?.cancel()
                            loadMoreRetryRound = 0
                            Task { await loadNextStaffPage() }
                        }
                    } else {
                        ProgressView()
                    }
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .id(staffCursor)
                .onAppear { Task { await loadNextStaffPage() } }
            }
        }
    }

    @ViewBuilder
    private var loginRows: some View {
        if visibleLogins.isEmpty && !isLoading {
            ContentUnavailableView(
                searchText.isEmpty ? "No active sessions" : "No matches",
                systemImage: "rectangle.badge.xmark",
                description: Text(searchText.isEmpty ? "Signed-in staff will appear here." : "Try another search.")
            )
        } else {
            Section("Active sessions") {
                ForEach(visibleLogins) { row in
                    Button { selectedLogin = row } label: {
                      VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            StaffSecurityAvatar(name: row.name ?? "Staff")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name?.securityNonBlank ?? "Unnamed staff").font(.headline)
                                Text([row.employeeId, row.designation, row.department]
                                    .compactMap { $0?.securityNonBlank }
                                    .joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        SecuritySessionLine(title: "Web", session: row.webSession)
                        SecuritySessionLine(title: "Mobile", session: row.mobileSession)

                        HStack {
                            Label("\(row.deviceCount) device\(row.deviceCount == 1 ? "" : "s")", systemImage: "rectangle.stack")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label("View devices", systemImage: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                      }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private var currentRowsAreEmpty: Bool {
        mode == .staffLogin ? logins.isEmpty : staff.isEmpty
    }

    @MainActor
    private func reload() async {
        guard let token = authStore.currentSession?.token, !isLoading else { return }
        isLoading = true
        loadMoreFailed = false
        defer { isLoading = false }
        do {
            if mode == .staffLogin {
                staffCursor = nil
                staffPaginationDone = true
                logins = try await StaffSecurityAPIService.activeLogins(token: token)
                    .filter { $0.staffId?.securityNonBlank != nil }
                    .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            } else {
                let page = try await getStaffPageWithRetry(token: token, cursor: nil)
                staff = sortedUniqueStaff(page.page)
                staffCursor = page.continueCursor?.securityNonBlank
                staffPaginationDone = page.isDone || staffCursor == nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadNextStaffPage() async {
        guard mode != .staffLogin,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let token = authStore.currentSession?.token,
              !isLoading,
              !isLoadingMore,
              !staffPaginationDone,
              let cursor = staffCursor else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            let page = try await getStaffPageWithRetry(token: token, cursor: cursor)
            staff = sortedUniqueStaff(staff + page.page)
            let nextCursor = page.continueCursor?.securityNonBlank
            staffCursor = nextCursor
            staffPaginationDone = page.isDone || nextCursor == nil || nextCursor == cursor
            loadMoreRetryTask?.cancel()
            loadMoreRetryRound = 0
        } catch {
            loadMoreFailed = true
            errorMessage = error.localizedDescription
            scheduleLoadMoreRetry()
        }
    }

    @MainActor
    private func scheduleLoadMoreRetry() {
        loadMoreRetryTask?.cancel()
        let delays = [4, 10, 20, 30]
        let seconds = delays[min(loadMoreRetryRound, delays.count - 1)]
        loadMoreRetryRound += 1
        loadMoreRetryTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await loadNextStaffPage()
        }
    }

    /// Preserve the opaque cursor while retrying a brief URL/DNS outage. The
    /// request is a safe GET, and the manual footer remains the final fallback.
    private func getStaffPageWithRetry(
        token: String,
        cursor: String?
    ) async throws -> ConvexStaffPaginatedPage {
        var attempt = 0
        while true {
            do {
                return try await HRConvexAPIService.getStaffPaginated(
                    token: token,
                    numItems: 25,
                    cursor: cursor,
                    lite: true
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                guard error is URLError, attempt < 3 else { throw error }
                try await Task.sleep(for: .milliseconds(attempt == 1 ? 300 : 900))
            }
        }
    }

    @MainActor
    private func searchStaff(_ query: String) async {
        guard let token = authStore.currentSession?.token, !isLoading else { return }
        isLoading = true
        loadMoreFailed = false
        defer { isLoading = false }
        do {
            let rows = try await HRConvexAPIService.searchStaff(
                token: token,
                query: query,
                lite: true
            )
            guard query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            staff = sortedUniqueStaff(rows)
            staffCursor = nil
            staffPaginationDone = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sortedUniqueStaff(_ rows: [ConvexStaffListItem]) -> [ConvexStaffListItem] {
        Dictionary(grouping: rows, by: \._id)
            .compactMap { $0.value.first }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    @MainActor
    private func logoutEverywhere(staffId: String) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            try await StaffSecurityAPIService.logoutEverywhere(token: token, staffId: staffId)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StaffLoginDevicesSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let login: ActiveStaffLogin
    let canLogout: Bool
    let onChanged: () -> Void

    @State private var sessions: [ActiveStaffSession] = []
    @State private var isLoading = true
    @State private var busyDeviceKey: String?
    @State private var errorMessage: String?
    @State private var confirmLogoutAll = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if sessions.isEmpty {
                        ContentUnavailableView("No active devices", systemImage: "rectangle.badge.xmark")
                    } else {
                        ForEach(sessions) { session in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Label(
                                        session.deviceType == "mobile" ? "Mobile" : "Web",
                                        systemImage: session.deviceType == "mobile" ? "iphone" : "desktopcomputer"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    Text(deviceLabel(session)).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if session.isCurrent {
                                        Text("This device")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(.orange.opacity(0.14), in: Capsule())
                                    }
                                }
                                if let createdAt = session.createdAt {
                                    Text("Signed in \(SecurityDateFormatter.string(fromEpoch: createdAt))" +
                                         (session.ip.securityNonBlank.map { " · \($0)" } ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if canLogout {
                                    Button(role: .destructive) {
                                        Task { await logout(session) }
                                    } label: {
                                        HStack {
                                            Spacer()
                                            if busyDeviceKey == session.deviceKey { ProgressView() }
                                            Text("Logout this device")
                                            Spacer()
                                        }
                                    }
                                    .disabled(busyDeviceKey != nil)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("\(login.name ?? "Staff") is signed in on these devices")
                }

                if canLogout && !sessions.isEmpty {
                    Section {
                        Button("Logout all devices", role: .destructive) { confirmLogoutAll = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Logged-in devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .task { await load() }
            .confirmationDialog("Logout all devices?", isPresented: $confirmLogoutAll) {
                Button("Logout web and mobile", role: .destructive) { Task { await logoutAll() } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Security", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func deviceLabel(_ session: ActiveStaffSession) -> String {
        if session.deviceType == "mobile" {
            let model = session.model.securityNonBlank ?? session.device.securityNonBlank
            let platform = session.os.securityNonBlank ?? "iOS/Android"
            return model.map { "\($0) · \(platform)" } ?? "Mobile app on \(platform)"
        }
        let browser = session.browser.securityNonBlank ?? "Web browser"
        return session.os.securityNonBlank.map { "\(browser) on \($0)" } ?? browser
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token, let staffId = login.staffId else { return }
        isLoading = true
        defer { isLoading = false }
        do { sessions = try await StaffSecurityAPIService.activeSessions(token: token, staffId: staffId) }
        catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func logout(_ session: ActiveStaffSession) async {
        guard let token = authStore.currentSession?.token, let staffId = login.staffId else { return }
        busyDeviceKey = session.deviceKey
        defer { busyDeviceKey = nil }
        do {
            try await StaffSecurityAPIService.logoutDevice(token: token, staffId: staffId, sessionIds: session.sessionIds)
            await load()
            onChanged()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func logoutAll() async {
        guard let token = authStore.currentSession?.token, let staffId = login.staffId else { return }
        do {
            try await StaffSecurityAPIService.logoutEverywhere(token: token, staffId: staffId)
            onChanged()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private enum SecurityMode: String, CaseIterable, Identifiable {
    case deviceReset
    case staffLogin
    case passwordReset

    var id: String { rawValue }
    var shortTitle: String {
        switch self {
        case .deviceReset: return "Device"
        case .staffLogin: return "Logins"
        case .passwordReset: return "Password"
        }
    }
    var helpText: String {
        switch self {
        case .deviceReset: return "Clear a mobile device lock or end the current mobile session."
        case .staffLogin: return "Review active web and mobile sessions and sign a staff member out everywhere."
        case .passwordReset: return "Set a new password and manage password-expiry exemption."
        }
    }
}

private struct StaffSecurityAvatar: View {
    let name: String
    var body: some View {
        Circle()
            .fill(Color.blue.opacity(0.13))
            .overlay {
                Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 42, height: 42)
    }
}

private struct SecuritySessionLine: View {
    let title: String
    let session: StaffLoginSession?

    var body: some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 52, alignment: .leading)
            Text(session?.createdAt == nil ? "Not logged in" : "Logged in")
                .font(.caption.weight(.semibold))
                .foregroundStyle(session?.createdAt == nil ? .secondary : .green)
            if let createdAt = session?.createdAt {
                Text("since \(SecurityDateFormatter.string(fromEpoch: createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.subheadline)
    }
}

private struct StaffSecurityDetailSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let staff: ConvexStaffListItem
    let showDeviceActions: Bool
    let showPasswordActions: Bool

    @State private var binding: StaffBoundDevice?
    @State private var passwordStatus: StaffPasswordStatus?
    @State private var newPassword = ""
    @State private var mustChangePassword = true
    @State private var isLoading = false
    @State private var isActing = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var confirmation: DetailConfirmation?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Employee", value: staff.displayName)
                    if let employeeId = staff.employeeId?.securityNonBlank {
                        LabeledContent("Employee ID", value: employeeId)
                    }
                    if let detail = [staff.designation, staff.department]
                        .compactMap({ $0?.securityNonBlank }).joined(separator: " · ").securityNonBlank {
                        LabeledContent("Role", value: detail)
                    }
                }

                if showDeviceActions { deviceSection }
                if showPasswordActions { passwordSection }

                if let message {
                    Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Staff Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .overlay { if isLoading { ProgressView() } }
            .task { await load() }
            .confirmationDialog(
                confirmation?.title ?? "Confirm",
                isPresented: Binding(
                    get: { confirmation != nil },
                    set: { if !$0 { confirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(confirmation?.buttonTitle ?? "Continue", role: .destructive) {
                    guard let action = confirmation else { return }
                    confirmation = nil
                    Task { await run(action) }
                }
                Button("Cancel", role: .cancel) { confirmation = nil }
            }
            .alert("Security", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    @ViewBuilder
    private var deviceSection: some View {
        Section("Mobile device") {
            if binding?.bound == true {
                LabeledContent("Status", value: "Bound")
                if let model = binding?.deviceModel?.securityNonBlank { LabeledContent("Device", value: model) }
                if let platform = binding?.platform?.securityNonBlank { LabeledContent("Platform", value: platform) }
                if let battery = binding?.batteryPct { LabeledContent("Battery", value: "\(Int(battery.rounded()))%") }
                if let seen = binding?.lastSeenAt { LabeledContent("Last seen", value: SecurityDateFormatter.string(fromEpoch: seen)) }
            } else {
                Label("No mobile device is bound", systemImage: "iphone.slash")
                    .foregroundStyle(.secondary)
            }

            Button("Clear device lock", role: .destructive) { confirmation = .resetDevice }
                .disabled(binding?.bound != true || isActing)
            Button("Log out mobile session", role: .destructive) { confirmation = .mobileLogout }
                .disabled(isActing)
        }
    }

    @ViewBuilder
    private var passwordSection: some View {
        Section("Password") {
            LabeledContent("Status", value: passwordStatus?.hasPassword == true ? "Password set" : "No password set")
            if let updated = passwordStatus?.passwordUpdatedAt {
                LabeledContent("Last changed", value: SecurityDateFormatter.string(fromEpoch: updated))
            }
            if passwordStatus?.passwordExpiryExempt == true {
                Label("Exempt from password expiry", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            }

            SecureField("New password", text: $newPassword)
                .textContentType(.newPassword)
            Toggle("Require change at next login", isOn: $mustChangePassword)
            Button("Set new password") { Task { await savePassword() } }
                .disabled(newPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActing)
            Button(passwordStatus?.passwordExpiryExempt == true ? "Re-enable password expiry" : "Exempt from password expiry") {
                Task { await toggleExpiryExemption() }
            }
            .disabled(isActing)
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if showDeviceActions {
                binding = try await StaffSecurityAPIService.deviceBinding(token: token, staffId: staff._id)
            }
            if showPasswordActions {
                passwordStatus = try await StaffSecurityAPIService.passwordStatus(token: token, staffId: staff._id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func run(_ action: DetailConfirmation) async {
        guard let token = authStore.currentSession?.token else { return }
        isActing = true
        defer { isActing = false }
        do {
            switch action {
            case .resetDevice:
                try await StaffSecurityAPIService.resetDevice(token: token, staffId: staff._id)
                message = "Device lock cleared."
            case .mobileLogout:
                try await StaffSecurityAPIService.forceMobileLogout(token: token, staffId: staff._id)
                message = "Mobile session ended."
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func savePassword() async {
        guard let token = authStore.currentSession?.token else { return }
        let password = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await StaffSecurityAPIService.setPassword(
                token: token,
                staffId: staff._id,
                newPassword: password,
                mustChangePassword: mustChangePassword
            )
            newPassword = ""
            message = "Password updated."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleExpiryExemption() async {
        guard let token = authStore.currentSession?.token else { return }
        let exempt = !(passwordStatus?.passwordExpiryExempt ?? false)
        isActing = true
        defer { isActing = false }
        do {
            try await StaffSecurityAPIService.setPasswordExpiryExempt(
                token: token,
                staffId: staff._id,
                exempt: exempt
            )
            message = exempt ? "Password expiry exemption enabled." : "Password expiry restored."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum DetailConfirmation: String, Identifiable {
    case resetDevice
    case mobileLogout
    var id: String { rawValue }
    var title: String {
        switch self {
        case .resetDevice: return "Clear this device lock?"
        case .mobileLogout: return "Log out this mobile session?"
        }
    }
    var buttonTitle: String {
        switch self {
        case .resetDevice: return "Clear lock"
        case .mobileLogout: return "Log out mobile"
        }
    }
}

private enum SecurityDateFormatter {
    static func string(fromEpoch epoch: Double) -> String {
        let seconds = epoch > 10_000_000_000 ? epoch / 1_000 : epoch
        return Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .shortened)
    }
}

private extension String {
    var securityNonBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
