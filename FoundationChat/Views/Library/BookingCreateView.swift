import SwiftUI

struct BookingCreateView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let initialProject: MarketingProject?
    let initialUnit: InventoryUnit?

    @State private var selectedProject: MarketingProject?
    @State private var selectedUnit: InventoryUnit?
    @State private var selectedLead: TelecallerLeadSearchData?
    @State private var leadMatches: [TelecallerLeadSearchData] = []
    @State private var lastLeadLookupPhone: String?

    @State private var clientName = ""
    @State private var mobileNumber = ""
    @State private var bookingDate = Date()
    @State private var bookingCost = ""
    @State private var advanceAmount = ""
    @State private var isSubmitting = false
    @State private var isSearchingLead = false
    @State private var linkedLeadMessage: String?
    @State private var errorMessage: String?
    @State private var successMessage: String?

    @State private var projects: [MarketingProject] = []
    @State private var availableUnits: [InventoryUnit] = []
    @State private var showProjectPicker = false
    @State private var showUnitPicker = false
    @State private var showLeadPicker = false

    init(initialProject: MarketingProject? = nil, initialUnit: InventoryUnit? = nil) {
        self.initialProject = initialProject
        self.initialUnit = initialUnit
        _selectedProject = State(initialValue: initialProject)
        _selectedUnit = State(initialValue: initialUnit)
    }

    private var canCreateBooking: Bool {
        authStore.hasPermission("marketing.bookings.create")
    }

    private var balance: Double? {
        guard let cost = Double(bookingCost), let advance = Double(advanceAmount) else { return nil }
        return cost - advance
    }

    var body: some View {
        Form {
            if !canCreateBooking {
                Section {
                    Label("You don't have permission to create bookings.", systemImage: "lock.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Project & Unit") {
                Button {
                    Task { await loadProjectsThenShowPicker() }
                } label: {
                    pickerRow("Project", value: selectedProject?.name ?? "Select project")
                }
                .buttonStyle(.plain)

                Button {
                    Task { await loadUnitsThenShowPicker() }
                } label: {
                    pickerRow("Unit", value: selectedUnit?.unitNumber.map { "Unit \($0)" } ?? "Select unit")
                }
                .buttonStyle(.plain)
            }

            Section("Client") {
                TextField("Client name", text: $clientName)
                    .textContentType(.name)
                TextField("Mobile number", text: $mobileNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .onChange(of: mobileNumber) { _, value in
                        let phone = AppModuleFormatters.normalizePhone(value)
                        Task { await lookupLeadIfNeeded(phone: phone) }
                    }

                if isSearchingLead {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Searching lead…")
                            .foregroundStyle(.secondary)
                    }
                } else if let linkedLeadMessage {
                    Button {
                        if leadMatches.count > 1 {
                            showLeadPicker = true
                        }
                    } label: {
                        HStack {
                            Text(linkedLeadMessage)
                                .font(AppModuleFont.rowBody)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if leadMatches.count > 1 {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Booking") {
                DatePicker("Booking date", selection: $bookingDate, displayedComponents: .date)
                TextField("Booking cost", text: $bookingCost)
                    .keyboardType(.decimalPad)
                TextField("Advance amount", text: $advanceAmount)
                    .keyboardType(.decimalPad)
                if let balance {
                    LabeledContent("Balance", value: AppModuleFormatters.rupees(balance))
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Create Booking")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canCreateBooking || isSubmitting)
            }
        }
        .navigationTitle("New Booking")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProjectPicker) {
            NavigationStack {
                List(projects) { project in
                    Button {
                        selectedProject = project
                        selectedUnit = nil
                        showProjectPicker = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name ?? "Unnamed")
                            Text(AppModuleFormatters.prettyScope(project.scope))
                                .font(AppModuleFont.rowMeta)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Select Project")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showUnitPicker) {
            NavigationStack {
                List(availableUnits) { unit in
                    Button {
                        guard unit.status == "available" else {
                            errorMessage = "Unit is no longer available"
                            return
                        }
                        selectedUnit = unit
                        showUnitPicker = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(unit.unitNumber ?? "Unit")
                            Text(unitSummary(unit))
                                .font(AppModuleFont.rowMeta)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Select Unit")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLeadPicker) {
            NavigationStack {
                List(leadMatches) { lead in
                    Button {
                        applyLead(lead)
                        showLeadPicker = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lead.displayName)
                            Text(lead.mobileNumber ?? "No phone")
                                .font(AppModuleFont.rowMeta)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Select Linked Lead")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        .alert("Booking", isPresented: Binding(
            get: { errorMessage != nil || successMessage != nil },
            set: { if !$0 { errorMessage = nil; successMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                let shouldDismiss = successMessage != nil
                errorMessage = nil
                successMessage = nil
                if shouldDismiss { dismiss() }
            }
        } message: {
            Text(errorMessage ?? successMessage ?? "")
        }
    }

    private func pickerRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AppModuleFont.rowBody)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(AppModuleFont.rowBody)
                .foregroundStyle(value.hasPrefix("Select") ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    @MainActor
    private func loadProjectsThenShowPicker() async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            projects = try await MarketingConvexAPIService.getMarketingProjects(token: token)
            if projects.isEmpty {
                errorMessage = "No projects available"
            } else {
                showProjectPicker = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadUnitsThenShowPicker() async {
        guard let token = authStore.currentSession?.token else { return }
        guard let project = selectedProject else {
            errorMessage = "Pick a project first"
            return
        }
        do {
            let units = try await MarketingConvexAPIService.listInventoryUnits(
                token: token,
                projectId: project.id,
                status: "available"
            )
            availableUnits = units.filter { $0.status == "available" }
            if availableUnits.isEmpty {
                errorMessage = "No available units in this project"
            } else {
                showUnitPicker = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func lookupLeadIfNeeded(phone: String) async {
        guard phone.count == 10 else {
            selectedLead = nil
            leadMatches = []
            lastLeadLookupPhone = nil
            linkedLeadMessage = nil
            return
        }
        guard phone != lastLeadLookupPhone else { return }
        guard let token = authStore.currentSession?.token else { return }
        lastLeadLookupPhone = phone
        isSearchingLead = true
        defer { isSearchingLead = false }
        do {
            let matches = try await MarketingConvexAPIService.searchTelecallerLeadsByPhone(token: token, phone: phone)
            guard AppModuleFormatters.normalizePhone(mobileNumber) == phone else { return }
            leadMatches = matches
            if matches.isEmpty {
                selectedLead = nil
                linkedLeadMessage = "No linked lead found"
            } else {
                applyLead(matches[0])
                if matches.count > 1 {
                    linkedLeadMessage = "\(linkedLeadMessage ?? "") · tap to change"
                }
            }
        } catch {
            linkedLeadMessage = "Lead search failed"
        }
    }

    @MainActor
    private func applyLead(_ lead: TelecallerLeadSearchData) {
        selectedLead = lead
        if clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clientName = lead.displayName
        }
        linkedLeadMessage = "Linked lead: \(lead.displayName)"
    }

    @MainActor
    private func submit() async {
        let name = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mobile = AppModuleFormatters.normalizePhone(mobileNumber)
        guard !name.isEmpty else { errorMessage = "Client name is required"; return }
        guard mobile.count == 10 else { errorMessage = "Valid mobile number is required"; return }
        guard let project = selectedProject else { errorMessage = "Pick a project"; return }
        if let unit = selectedUnit, unit.status != "available" {
            errorMessage = "Selected unit is not available. Pick a different unit."
            return
        }
        guard let token = authStore.currentSession?.token else { return }

        let cost = Double(bookingCost)
        let advance = Double(advanceAmount)
        let request = CreateBookingRequest(
            clientName: name,
            mobileNumber: mobile,
            bookingDate: AppModuleFormatters.ymd.string(from: bookingDate),
            leadId: selectedLead?.id,
            projectId: project.id,
            plotId: selectedUnit?.id,
            plotNo: selectedUnit?.unitNumber,
            bookingType: nil,
            bookingMode: nil,
            bookingCost: cost,
            advanceAmount: advance,
            balanceAmount: cost.flatMap { c in advance.map { c - $0 } },
            email: nil,
            homeAddress: nil
        )

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await MarketingConvexAPIService.createBooking(token: token, request: request)
            successMessage = "Booking created"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unitSummary(_ unit: InventoryUnit) -> String {
        var parts: [String] = []
        if let type = unit.unitType { parts.append(type) }
        if let facing = unit.facing { parts.append("facing \(facing)") }
        if let area = unit.area { parts.append("\(Int(area)) sqft") }
        return parts.joined(separator: " · ")
    }
}
