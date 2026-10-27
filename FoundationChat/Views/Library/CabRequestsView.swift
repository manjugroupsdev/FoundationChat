import CoreLocation
import SwiftUI

/// Fleet > Cab Requests, as on the web (and Android): request a company vehicle
/// for official travel; the reporting officer approves; the fleet desk assigns.
///
/// Tabs and actions follow the same IAM keys as the web and the server:
///  - marketing.fleet.cabRequest.create  → My Requests, New request, cancel own
///  - marketing.fleet.cabRequest.approve → Approvals (approve / reject)
///  - marketing.fleet.cabRequest.viewAll → All Requests
///  - marketing.fleet.cabRequest.assign  → assign a vehicle, mark completed
struct CabRequestsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case mine = "My Requests"
        case approvals = "Approvals"
        case all = "All Requests"
        var id: String { rawValue }
    }

    @Environment(AuthStore.self) private var authStore

    var initialTab: Tab?

    @State private var tab: Tab = .mine
    @State private var mine: [CabRequest] = []
    @State private var approvals: [CabRequest] = []
    @State private var all: [CabRequest] = []
    @State private var query = ""
    @State private var statusFilter: String?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    /// Why the last load failed, shown instead of "No cab requests yet".
    @State private var loadError: String?
    @State private var showNewRequest = false
    @State private var confirm: PendingAction?
    @State private var rejecting: CabRequest?
    @State private var rejectReason = ""
    @State private var assigning: CabRequest?

    private enum PendingAction: Identifiable {
        case approve(CabRequest)
        case cancel(CabRequest)
        case complete(CabRequest)

        var id: String {
            switch self {
            case .approve(let r): return "approve-\(r.id)"
            case .cancel(let r): return "cancel-\(r.id)"
            case .complete(let r): return "complete-\(r.id)"
            }
        }
    }

    private static let statuses: [(key: String, label: String)] = [
        ("pending", "Pending"), ("approved", "Approved"), ("rejected", "Rejected"),
        ("assigned", "Assigned"), ("completed", "Completed"), ("cancelled", "Cancelled"),
    ]

    private var canCreate: Bool { authStore.hasPermission("marketing.fleet.cabRequest.create") }
    private var canApprove: Bool { authStore.hasPermission("marketing.fleet.cabRequest.approve") }
    private var canViewAll: Bool { authStore.hasPermission("marketing.fleet.cabRequest.viewAll") }
    private var canAssign: Bool { authStore.hasPermission("marketing.fleet.cabRequest.assign") }
    private var myStaffId: String? { authStore.currentSession?.user.staffId ?? authStore.currentSession?.user._id }

    private var tabs: [Tab] {
        var result: [Tab] = []
        if canCreate { result.append(.mine) }
        if canApprove { result.append(.approvals) }
        if canViewAll { result.append(.all) }
        return result
    }

    private var source: [CabRequest] {
        switch tab {
        case .mine: return mine
        case .approvals: return approvals
        case .all: return all
        }
    }

    private var rows: [CabRequest] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return source.filter { r in
            (statusFilter == nil || r.status == statusFilter) &&
                (q.isEmpty || [r.purpose, r.staffName, r.fromLocation, r.toLocation, r.requestedDate, r.vehicleNumber]
                    .contains { $0?.lowercased().contains(q) == true })
        }
    }

    var body: some View {
        List {
            Section {
                Text("Request a company vehicle for official travel. Your reporting officer will approve.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if (canApprove || canViewAll) && tabs.count > 1 {
                    Picker("View", selection: $tab) {
                        ForEach(tabs) { item in
                            Text(label(for: item)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    Menu {
                        Button("All Status") { statusFilter = nil }
                        ForEach(Self.statuses, id: \.key) { status in
                            Button(status.label) { statusFilter = status.key }
                        }
                    } label: {
                        Label(
                            Self.statuses.first { $0.key == statusFilter }?.label ?? "All Status",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    }
                    Spacer()
                    if statusFilter != nil || !query.isEmpty {
                        Button("Clear filters") {
                            statusFilter = nil
                            query = ""
                        }
                        .font(.footnote)
                    }
                }
            }

            if tabs.isEmpty {
                ContentUnavailableView(
                    "No access",
                    systemImage: "lock",
                    description: Text("You don't have permission to use cab requests.")
                )
            } else if !hasLoaded && isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 96)
                        .listRowSeparator(.hidden)
                }
            } else if source.isEmpty, let loadError {
                ContentUnavailableView(
                    "Couldn't load cab requests",
                    systemImage: "exclamationmark.triangle",
                    description: Text("\(loadError) Pull down to try again.")
                )
            } else if source.isEmpty {
                ContentUnavailableView(
                    "No cab requests yet",
                    systemImage: "car",
                    description: Text(canCreate ? "Tap + to raise a cab request." : "No cab requests found.")
                )
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No requests match your filters",
                    systemImage: "magnifyingglass",
                    description: Text("Try adjusting your search or status filter.")
                )
            } else {
                ForEach(rows) { request in
                    card(request)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Cab Requests")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search by purpose, staff, route...")
        .toolbar {
            if canCreate {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewRequest = true
                    } label: {
                        Label("New request", systemImage: "plus")
                    }
                }
            }
        }
        .refreshable { await load() }
        .task {
            // Same default as the web: All, else Approvals, else My Requests.
            if let initialTab, tabs.contains(initialTab) {
                tab = initialTab
            } else if tabs.contains(.all) {
                tab = .all
            } else if tabs.contains(.approvals) {
                tab = .approvals
            }
            await load()
        }
        .sheet(isPresented: $showNewRequest) {
            NewCabRequestSheet {
                infoMessage = "Cab request submitted successfully"
                Task { await load() }
            }
        }
        .sheet(item: $assigning) { request in
            AssignCabVehicleSheet(request: request) {
                infoMessage = "Vehicle assigned successfully"
                Task { await load() }
            }
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
            titleVisibility: .visible
        ) {
            Button(confirmButton) {
                guard let action = confirm else { return }
                confirm = nil
                Task { await run(action) }
            }
            Button("Keep", role: .cancel) { confirm = nil }
        }
        .alert("Reject cab request", isPresented: Binding(
            get: { rejecting != nil },
            set: { if !$0 { rejecting = nil } }
        )) {
            TextField("Reason for rejection", text: $rejectReason)
            Button("Reject", role: .destructive) {
                guard let request = rejecting else { return }
                let reason = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
                rejecting = nil
                rejectReason = ""
                guard !reason.isEmpty else {
                    errorMessage = "Please provide a rejection reason"
                    return
                }
                Task { await perform("Cab request rejected") { token in
                    try await CabRequestAPIService.reject(token: token, id: request.id, reason: reason)
                } }
            }
            Button("Cancel", role: .cancel) {
                rejecting = nil
                rejectReason = ""
            }
        }
        .alert("Cab Requests", isPresented: Binding(
            get: { errorMessage != nil || infoMessage != nil },
            set: { if !$0 { errorMessage = nil; infoMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil; infoMessage = nil }
        } message: {
            Text(errorMessage ?? infoMessage ?? "")
        }
    }

    private func label(for item: Tab) -> String {
        guard item == .approvals else { return item.rawValue }
        let pending = approvals.filter { $0.status == "pending" }.count
        return pending > 0 ? "\(item.rawValue) (\(pending))" : item.rawValue
    }

    @ViewBuilder
    private func card(_ r: CabRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(r.purpose?.nilIfBlankCab ?? "Cab request")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                CabStatusBadge(status: r.status)
            }
            if tab != .mine, let staff = [r.staffName, r.employeeId].compactMap({ $0?.nilIfBlankCab }).joined(separator: " · ").nilIfBlankCab {
                Text(staff).font(.footnote).foregroundStyle(.primary)
            }
            Label(
                [CabRequestsView.formatDate(r.requestedDate), r.requestedTime].compactMap { $0 }.joined(separator: " · "),
                systemImage: "calendar"
            )
            .font(.footnote).foregroundStyle(.secondary)
            Label("\(r.fromLocation ?? "") → \(r.toLocation ?? "")", systemImage: "mappin.and.ellipse")
                .font(.footnote).foregroundStyle(.secondary)
            if let passengers = r.passengerCount, passengers >= 1 {
                Label("\(Int(passengers)) passenger\(Int(passengers) == 1 ? "" : "s")", systemImage: "person.2")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let vehicle = r.vehicleNumber?.nilIfBlankCab {
                Label(
                    [vehicle, r.driverName, r.driverPhone].compactMap { $0?.nilIfBlankCab }.joined(separator: " · "),
                    systemImage: "car.fill"
                )
                .font(.footnote)
            }
            if r.status == "rejected", let reason = r.rejectionReason?.nilIfBlankCab {
                Text("Reason: \(reason)").font(.footnote).foregroundStyle(.red)
            }
            if let notes = r.notes?.nilIfBlankCab {
                Text(notes).font(.footnote).foregroundStyle(.secondary)
            }
            actions(r)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actions(_ r: CabRequest) -> some View {
        let status = r.status ?? ""
        let mine = r.staffId != nil && r.staffId == myStaffId
        let showApprove = status == "pending" && canApprove && (tab == .approvals || r.reportingToId == myStaffId)
        let showAssign = status == "approved" && canAssign
        let showComplete = status == "assigned" && canAssign
        let showCancel = (status == "pending" || status == "approved") && canCreate && (mine || canViewAll)
        if showApprove || showAssign || showComplete || showCancel {
            HStack(spacing: 8) {
                Spacer()
                if showCancel {
                    Button("Cancel") { confirm = .cancel(r) }.tint(.gray)
                }
                if showApprove {
                    Button("Reject") { rejecting = r }.tint(.red)
                    Button("Approve") { confirm = .approve(r) }.tint(.green)
                }
                if showAssign {
                    Button("Assign vehicle") { assigning = r }.tint(.purple)
                }
                if showComplete {
                    Button("Mark completed") { confirm = .complete(r) }.tint(.green)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.footnote.weight(.semibold))
            .padding(.top, 4)
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .approve: return "Approve cab request?"
        case .cancel: return "Cancel this cab request?"
        case .complete: return "Mark this trip completed?"
        case nil: return ""
        }
    }

    private var confirmButton: String {
        switch confirm {
        case .approve: return "Approve"
        case .cancel: return "Cancel request"
        case .complete: return "Mark completed"
        case nil: return "OK"
        }
    }

    @MainActor
    private func run(_ action: PendingAction) async {
        switch action {
        case .approve(let r):
            await perform("Cab request approved") { try await CabRequestAPIService.approve(token: $0, id: r.id) }
        case .cancel(let r):
            await perform("Cab request cancelled") { try await CabRequestAPIService.cancel(token: $0, id: r.id) }
        case .complete(let r):
            await perform("Marked completed") { try await CabRequestAPIService.complete(token: $0, id: r.id) }
        }
    }

    @MainActor
    private func perform(_ success: String, _ call: (String) async throws -> Void) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            try await call(token)
            infoMessage = success
        } catch {
            errorMessage = error.localizedDescription
        }
        await load()
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token, !tabs.isEmpty else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        var firstError: String?
        if canCreate {
            do { mine = try await CabRequestAPIService.mine(token: token) }
            catch { firstError = firstError ?? error.localizedDescription }
        }
        if canApprove {
            do { approvals = try await CabRequestAPIService.approvals(token: token) }
            catch { firstError = firstError ?? error.localizedDescription }
        }
        if canViewAll {
            do { all = try await CabRequestAPIService.all(token: token) }
            catch { firstError = firstError ?? error.localizedDescription }
        }
        loadError = firstError
        if let firstError { errorMessage = firstError }
    }

    /// `requestedDate` as "dd MMM yyyy", as the web shows it.
    static func formatDate(_ ymd: String?) -> String? {
        guard let ymd, !ymd.isEmpty else { return nil }
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: ymd) else { return ymd }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_IN")
        output.dateFormat = "dd MMM yyyy"
        return output.string(from: date)
    }
}

/// The web's outline badge colours per status.
private struct CabStatusBadge: View {
    let status: String?

    var body: some View {
        let colors: (Color, Color, Color) = {
            switch status {
            case "pending": return (Color(hex: 0xFFFBEB), Color(hex: 0xB45309), Color(hex: 0xFDE68A))
            case "approved": return (Color(hex: 0xEFF6FF), Color(hex: 0x1D4ED8), Color(hex: 0xBFDBFE))
            case "rejected": return (Color(hex: 0xFEF2F2), Color(hex: 0xB91C1C), Color(hex: 0xFECACA))
            case "assigned": return (Color(hex: 0xFAF5FF), Color(hex: 0x7E22CE), Color(hex: 0xE9D5FF))
            case "completed": return (Color(hex: 0xF0FDF4), Color(hex: 0x15803D), Color(hex: 0xBBF7D0))
            default: return (Color(hex: 0xF3F4F6), Color(hex: 0x6B7280), Color(hex: 0xE5E7EB))
            }
        }()
        Text((status ?? "—").capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(colors.1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colors.0, in: Capsule())
            .overlay(Capsule().stroke(colors.2, lineWidth: 1))
    }
}

/// "New Cab Request", the web dialog's fields.
private struct NewCabRequestSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    @State private var purpose = ""
    @State private var fromLocation = ""
    @State private var toLocation = ""
    @State private var date = Date()
    @State private var hasDate = false
    @State private var time = Date()
    @State private var hasTime = false
    @State private var passengers = ""
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var pickingFor: LocationTarget?

    private enum LocationTarget: Identifiable {
        case from, to
        var id: Int { self == .from ? 0 : 1 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Site visit, client meeting...", text: $purpose)
                } header: {
                    Text("Purpose *")
                } footer: {
                    Text("Fill in the trip details. Your reporting officer will be notified to approve.")
                }
                Section("From location (pickup) *") {
                    TextField("Pickup address", text: $fromLocation, axis: .vertical)
                    Button { pickingFor = .from } label: { Label("Pick on map", systemImage: "mappin.and.ellipse") }
                }
                Section("To location (drop) *") {
                    TextField("Drop address", text: $toLocation, axis: .vertical)
                    Button { pickingFor = .to } label: { Label("Pick on map", systemImage: "mappin.and.ellipse") }
                }
                Section("When") {
                    Toggle("Date *", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                    Toggle("Time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Details") {
                    TextField("Passengers", text: $passengers)
                        .keyboardType(.numberPad)
                    TextField("Any additional info...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New Cab Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Submitting..." : "Submit request") { Task { await submit() } }
                        .disabled(isSubmitting)
                }
            }
            .sheet(item: $pickingFor) { target in
                CpMapPinPicker(initialCoordinate: nil, initialAddress: nil) { result in
                    switch target {
                    case .from: fromLocation = result.address
                    case .to: toLocation = result.address
                    }
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        let p = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let from = fromLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !from.isEmpty, !to.isEmpty, hasDate else {
            errorMessage = "Purpose, from/to location and date are required"
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        let count = Int(passengers.trimmingCharacters(in: .whitespaces)).flatMap { $0 >= 1 ? $0 : nil }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await CabRequestAPIService.create(
                token: token,
                request: NewCabRequest(
                    purpose: p,
                    fromLocation: from,
                    toLocation: to,
                    requestedDate: dayFormatter.string(from: date),
                    requestedTime: hasTime ? timeFormatter.string(from: time) : nil,
                    passengerCount: count,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Pick an active vehicle (driver prefilled from it), as on the web.
private struct AssignCabVehicleSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let request: CabRequest
    let onAssigned: () -> Void

    @State private var vehicles: [CabRequestVehicle] = []
    @State private var selected: CabRequestVehicle?
    @State private var driverName = ""
    @State private var driverPhone = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(request.purpose ?? "Cab request").font(.subheadline.weight(.semibold))
                    Text([CabRequestsView.formatDate(request.requestedDate), request.requestedTime]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Vehicle") {
                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Text(selected?.vehicleNumber ?? (isLoading ? "Loading vehicles..." : "Select a vehicle"))
                            Spacer()
                            Image(systemName: "chevron.down").foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isLoading || vehicles.isEmpty)
                }
                Section("Driver") {
                    TextField("Driver name (optional)", text: $driverName)
                    TextField("Driver phone (optional)", text: $driverPhone)
                        .keyboardType(.phonePad)
                        .onChange(of: driverPhone) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(10))
                            if digits != value { driverPhone = digits }
                        }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Assign Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Assigning..." : "Assign") { Task { await save() } }
                        .disabled(selected == nil || isSaving)
                }
            }
            .task { await loadVehicles() }
            .sheet(isPresented: $showPicker) {
                NativeSearchableSelectionSheet(
                    title: "Select vehicle",
                    prompt: "Search vehicle or driver",
                    items: vehicles,
                    selectedId: selected?.id,
                    searchText: { [$0.vehicleNumber, $0.defaultDriverName, $0.make, $0.model].compactMap(\.self).joined(separator: " ") },
                    rowContent: { vehicle, isSelected in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(vehicle.vehicleNumber ?? "Vehicle")
                                if let driver = vehicle.defaultDriverName {
                                    Text(driver).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isSelected { Image(systemName: "checkmark") }
                        }
                    },
                    onSelect: { vehicle in
                        selected = vehicle
                        driverName = vehicle.defaultDriverName ?? ""
                        driverPhone = String((vehicle.defaultDriverPhone ?? "").filter(\.isNumber).suffix(10))
                        showPicker = false
                    }
                )
            }
        }
    }

    @MainActor
    private func loadVehicles() async {
        guard let token = authStore.currentSession?.token else { return }
        defer { isLoading = false }
        do {
            vehicles = try await CabRequestAPIService.activeVehicles(token: token)
            if vehicles.isEmpty { errorMessage = "No active vehicles" }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        guard let token = authStore.currentSession?.token, let vehicle = selected else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let name = driverName.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = driverPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            try await CabRequestAPIService.assign(
                token: token,
                id: request.id,
                vehicleId: vehicle.id,
                driverName: name.isEmpty ? nil : name,
                driverPhone: phone.isEmpty ? nil : phone
            )
            onAssigned()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfBlankCab: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
