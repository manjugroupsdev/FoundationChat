import SwiftUI

struct AdminFleetPortalView: View {
    @Environment(AuthStore.self) private var authStore

    private var scope: FleetDispatchScope {
        authStore.currentSession?.user.isExternalFleetPrincipal == true ? .agency : .mms
    }

    var body: some View {
        FleetPortalExperienceView(scope: scope)
    }
}

private enum AdminFleetTripFilter: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case assigned = "Assigned"
    case completed = "Completed"

    var id: String { rawValue }
}

private struct AdminFleetTripsView: View {
    @Environment(AuthStore.self) private var authStore

    let scope: FleetDispatchScope

    @State private var filter: AdminFleetTripFilter = .pending
    @State private var pendingTrips: [FleetDispatchTrip] = []
    @State private var assignedTrips: [FleetDispatchTrip] = []
    @State private var vehicles: [FleetDispatchVehicle] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var allocationTrip: FleetDispatchTrip?

    private var filteredTrips: [FleetDispatchTrip] {
        switch filter {
        case .pending:
            return pendingTrips
        case .assigned:
            return assignedTrips.filter { !$0.isCompleted }
        case .completed:
            return assignedTrips.filter(\.isCompleted)
        }
    }

    private var activeVehicleCount: Int { vehicles.filter(\.isActive).count }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                summary

                Picker("Trip status", selection: $filter) {
                    ForEach(AdminFleetTripFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if isLoading && !hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
                } else if filteredTrips.isEmpty {
                    ContentUnavailableView(
                        "No \(filter.rawValue) Trips",
                        systemImage: "car.side",
                        description: Text("Trips in this status will appear here.")
                    )
                    .padding(.top, 46)
                } else {
                    ForEach(filteredTrips) { trip in
                        AdminFleetTripCard(
                            trip: trip,
                            status: filter,
                            onAllocate: { allocationTrip = trip }
                        )
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Fleet Trips")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh fleet trips")
            }
        }
        .refreshable { await load() }
        .task {
            guard !hasLoaded else { return }
            await load()
        }
        .sheet(item: $allocationTrip) { trip in
            FleetAllocationSheet(
                token: authStore.currentSession?.token ?? "",
                scope: scope,
                trip: trip,
                vehicles: vehicles.filter(\.isActive)
            ) {
                filter = .assigned
                await load()
            }
            .appFormActivity()
            .presentationDetents([.large])
        }
        .alert("Fleet Trips", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            FleetMetric(title: "Pending Trips", value: pendingTrips.count, icon: "clock.fill", tint: Color(hex: 0xEA580C))
            FleetMetric(title: "Active Vehicles", value: activeVehicleCount, icon: "car.fill", tint: Color(hex: 0x0B61CA))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            async let pending = FleetDispatchAPIService.listPending(token: token, scope: scope)
            async let assigned = FleetDispatchAPIService.listAssigned(token: token, scope: scope)
            async let fleetVehicles = FleetDispatchAPIService.listVehicles(token: token, scope: scope)
            let result = try await (pending, assigned, fleetVehicles)
            pendingTrips = result.0
            assignedTrips = result.1
            vehicles = result.2
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FleetMetric: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 22, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AdminFleetTripCard: View {
    let trip: FleetDispatchTrip
    let status: AdminFleetTripFilter
    let onAllocate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color(hex: 0x0B61CA), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(tripTime, systemImage: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x4B5563))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(status.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(statusColor.opacity(0.11), in: Capsule())
                }

                Text(address)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x374151))
                    .lineLimit(2)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { tags }
                    VStack(alignment: .leading, spacing: 6) { tags }
                }

                if status == .pending {
                    HStack {
                        Spacer()
                        Button("Allocate", systemImage: "car.badge.gearshape", action: onAllocate)
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.roundedRectangle(radius: 8))
                            .controlSize(.small)
                            .tint(Color(hex: 0x0B61CA))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var tags: some View {
        FleetTag(icon: "person.2.fill", text: "\(trip.expectedAttendeeCount ?? 0)")
        FleetTag(icon: "car.fill", text: humanizedVehicleType)
    }

    private var tripTime: String {
        let date = trip.scheduledDate?.nonBlank ?? "Date pending"
        let time = trip.scheduledTime?.nonBlank ?? trip.pickupTime?.nonBlank
        return time.map { "\(date) · \($0)" } ?? date
    }

    private var address: String {
        trip.pickupAddress?.nonBlank
            ?? trip.project?.name?.nonBlank.map { "Project: \($0)" }
            ?? "Address pending"
    }

    private var humanizedVehicleType: String {
        (trip.vehiclePreference?.nonBlank ?? "Vehicle")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var statusColor: Color {
        switch status {
        case .pending: Color(hex: 0xEA580C)
        case .assigned: Color(hex: 0x1D4ED8)
        case .completed: Color(hex: 0x047857)
        }
    }
}

private struct FleetTag: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(hex: 0x1E3A8A))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color(hex: 0xEAF2FE), in: Capsule())
    }
}

struct FleetAllocationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let token: String
    let scope: FleetDispatchScope
    let trip: FleetDispatchTrip
    let vehicles: [FleetDispatchVehicle]
    let onAllocated: () async -> Void

    @State private var selectedVehicleId = ""
    @State private var driverName = ""
    @State private var driverPhone = ""
    @State private var pickupTime = Date()
    @State private var pricingMode = "km"
    @State private var amount = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var selectedVehicle: FleetDispatchVehicle? {
        vehicles.first { $0.id == selectedVehicleId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    Picker("Vehicle", selection: $selectedVehicleId) {
                        ForEach(vehicles) { vehicle in
                            Text(vehicleLabel(vehicle)).tag(vehicle.id)
                        }
                    }

                    TextField("Driver name", text: $driverName)
                        .textContentType(.name)
                    TextField("Driver phone", text: $driverPhone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    DatePicker("Pickup time", selection: $pickupTime, displayedComponents: .hourAndMinute)
                }

                if scope == .agency {
                    Section("Pricing") {
                        Picker("Pricing", selection: $pricingMode) {
                            Text("Per km").tag("km")
                            Text("Package").tag("package")
                        }
                        .pickerStyle(.segmented)

                        TextField(pricingMode == "km" ? "Per km amount" : "Package amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Allocate Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Allocate") { Task { await submit() } }
                        .disabled(!canSubmit || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .onAppear {
                if selectedVehicleId.isEmpty, let first = vehicles.first {
                    select(first)
                }
            }
            .onChange(of: selectedVehicleId) { _, newValue in
                if let vehicle = vehicles.first(where: { $0.id == newValue }) {
                    select(vehicle, preservingEnteredValues: true)
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard !selectedVehicleId.isEmpty,
              !driverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !driverPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if scope == .mms { return true }
        return (Double(amount) ?? -1) >= 0
    }

    private func vehicleLabel(_ vehicle: FleetDispatchVehicle) -> String {
        [vehicle.type?.nonBlank, vehicle.vehicleNumber?.nonBlank ?? "Vehicle"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func select(_ vehicle: FleetDispatchVehicle, preservingEnteredValues: Bool = false) {
        selectedVehicleId = vehicle.id
        if !preservingEnteredValues || driverName.isEmpty {
            driverName = vehicle.defaultDriverName ?? ""
        }
        if !preservingEnteredValues || driverPhone.isEmpty {
            driverPhone = vehicle.defaultDriverPhone ?? ""
        }
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let pickup = pickupTime.formatted(date: .omitted, time: .shortened)
            try await FleetDispatchAPIService.allocate(
                token: token,
                scope: scope,
                tripId: trip.id,
                draft: FleetAllocationDraft(
                    vehicleId: selectedVehicleId,
                    pickupTime: pickup,
                    pricingMode: pricingMode,
                    driverName: driverName.trimmingCharacters(in: .whitespacesAndNewlines),
                    driverPhone: driverPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: scope == .agency ? (Double(amount) ?? 0) : 0
                )
            )
            await onAllocated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AdminFleetVehiclesView: View {
    @Environment(AuthStore.self) private var authStore

    let scope: FleetDispatchScope

    @State private var vehicles: [FleetDispatchVehicle] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var showCreate = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && !hasLoaded {
                ProgressView()
            } else if vehicles.isEmpty {
                ContentUnavailableView("No Vehicles", systemImage: "car.side", description: Text("Fleet vehicles will appear here."))
            } else {
                List(vehicles) { vehicle in
                    AdminFleetVehicleRow(vehicle: vehicle)
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Vehicles")
        .toolbar {
            if scope == .agency {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create vehicle")
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            await load()
        }
        .sheet(isPresented: $showCreate) {
            FleetVehicleForm(token: authStore.currentSession?.token ?? "") {
                await load()
            }
            .appFormActivity()
            .presentationDetents([.medium, .large])
        }
        .alert("Vehicles", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            vehicles = try await FleetDispatchAPIService.listVehicles(token: token, scope: scope)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AdminFleetVehicleRow: View {
    let vehicle: FleetDispatchVehicle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "car.fill")
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 40, height: 40)
                .background(Color(hex: 0xEAF2FE), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.vehicleNumber?.nonBlank ?? "Vehicle")
                    .font(.headline)
                    .lineLimit(1)
                Text([vehicle.type?.nonBlank, vehicle.capacity.map { "\($0) seats" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let driver = vehicle.defaultDriverName?.nonBlank {
                    Label([driver, vehicle.defaultDriverPhone?.nonBlank].compactMap { $0 }.joined(separator: " · "), systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Circle()
                .fill(vehicle.isActive ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .accessibilityLabel(vehicle.isActive ? "Active" : "Inactive")
        }
        .padding(.vertical, 4)
    }
}

private struct FleetVehicleForm: View {
    @Environment(\.dismiss) private var dismiss

    let token: String
    let onCreated: () async -> Void

    @State private var number = ""
    @State private var type = ""
    @State private var capacity = ""
    @State private var driverName = ""
    @State private var driverPhone = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    TextField("Registration number", text: $number)
                        .textInputAutocapitalization(.characters)
                    TextField("Type", text: $type)
                    TextField("Capacity", text: $capacity)
                        .keyboardType(.numberPad)
                }
                Section("Default driver") {
                    TextField("Name", text: $driverName)
                    TextField("Phone", text: $driverPhone)
                        .keyboardType(.phonePad)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Create Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await submit() } }
                        .disabled(number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await FleetDispatchAPIService.createAgencyVehicle(
                token: token,
                vehicleNumber: number.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type.nonBlank,
                capacity: Int(capacity),
                defaultDriverName: driverName.nonBlank,
                defaultDriverPhone: driverPhone.nonBlank
            )
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AdminFleetDriversView: View {
    @Environment(AuthStore.self) private var authStore

    let scope: FleetDispatchScope

    @State private var drivers: [FleetDispatchDriver] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var editingDriver: FleetDispatchDriver?
    @State private var showCreate = false
    @State private var errorMessage: String?

    private var filteredDrivers: [FleetDispatchDriver] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return drivers }
        return drivers.filter {
            $0.name.lowercased().contains(query)
                || ($0.phone ?? "").contains(query)
                || ($0.address ?? "").lowercased().contains(query)
        }
    }

    var body: some View {
        Group {
            if isLoading && !hasLoaded {
                ProgressView()
            } else if filteredDrivers.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filteredDrivers) { driver in
                    Button {
                        editingDriver = driver
                    } label: {
                        AdminFleetDriverRow(driver: driver)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Drivers")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search drivers"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create driver")
            }
        }
        .task {
            guard !hasLoaded else { return }
            await load()
        }
        .sheet(isPresented: $showCreate) {
            FleetDriverForm(token: authStore.currentSession?.token ?? "", scope: scope, driver: nil) {
                await load()
            }
            .appFormActivity()
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingDriver) { driver in
            FleetDriverForm(token: authStore.currentSession?.token ?? "", scope: scope, driver: driver) {
                await load()
            }
            .appFormActivity()
            .presentationDetents([.medium, .large])
        }
        .alert("Drivers", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            drivers = try await FleetDispatchAPIService.listDrivers(token: token, scope: scope)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AdminFleetDriverRow: View {
    let driver: FleetDispatchDriver

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .foregroundStyle(driver.isActive ? Color(hex: 0x047857) : Color(hex: 0x991B1B))
                .frame(width: 40, height: 40)
                .background((driver.isActive ? Color.green : Color.red).opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(driver.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let phone = driver.phone?.nonBlank {
                    Label(phone, systemImage: "phone.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let address = driver.address?.nonBlank {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(driver.isActive ? "Active" : "Inactive")
                .font(.caption.weight(.semibold))
                .foregroundStyle(driver.isActive ? Color(hex: 0x047857) : Color(hex: 0x991B1B))
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct FleetDriverForm: View {
    @Environment(\.dismiss) private var dismiss

    let token: String
    let scope: FleetDispatchScope
    let driver: FleetDispatchDriver?
    let onSaved: () async -> Void

    @State private var name: String
    @State private var phone: String
    @State private var address: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        token: String,
        scope: FleetDispatchScope,
        driver: FleetDispatchDriver?,
        onSaved: @escaping () async -> Void
    ) {
        self.token = token
        self.scope = scope
        self.driver = driver
        self.onSaved = onSaved
        _name = State(initialValue: driver?.name ?? "")
        _phone = State(initialValue: driver?.phone ?? "")
        _address = State(initialValue: driver?.address ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Driver") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let driver {
                    Section {
                        Button(driver.isActive ? "Deactivate Driver" : "Activate Driver", role: driver.isActive ? .destructive : nil) {
                            Task { await toggleStatus(driver) }
                        }
                        .disabled(isSaving)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(driver == nil ? "Create Driver" : "Edit Driver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let driver {
                try await FleetDispatchAPIService.updateDriver(
                    token: token,
                    scope: scope,
                    id: driver.id,
                    name: name.nonBlank,
                    phone: phone.nonBlank,
                    address: address.nonBlank
                )
            } else {
                try await FleetDispatchAPIService.createDriver(
                    token: token,
                    scope: scope,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                    address: address.nonBlank
                )
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleStatus(_ driver: FleetDispatchDriver) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await FleetDispatchAPIService.setDriverStatus(
                token: token,
                scope: scope,
                id: driver.id,
                status: driver.isActive ? "inactive" : "active"
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AdminFleetAccountView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var showLogoutConfirmation = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(authStore.currentSession?.user.name?.nonBlank ?? "Fleet Account")
                            .font(.headline)
                        Text(authStore.currentSession?.user.designation?.nonBlank ?? "Fleet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Contact") {
                if let phone = authStore.currentSession?.user.phone?.nonBlank {
                    LabeledContent("Phone", value: phone)
                }
                if let email = authStore.currentSession?.user.email?.nonBlank {
                    LabeledContent("Email", value: email)
                }
            }

            Section {
                Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    showLogoutConfirmation = true
                }
            }
        }
        .navigationTitle("Account")
        .confirmationDialog("Log out of M-Chat?", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                Task { await authStore.logout() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
