import SwiftUI

struct InventoryProjectsListView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var projects: [MarketingProject] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Projects")
                        .font(AppModuleFont.rowTitle)
                    Spacer()
                    Text(hasLoaded ? "\(projects.count)" : "")
                        .font(AppModuleFont.rowMetaSemibold)
                        .foregroundStyle(.secondary)
                }
            }

            if isLoading && projects.isEmpty {
                ProgressView("Loading projects…")
            } else if projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "building.2",
                    description: Text(errorMessage ?? "No projects available.")
                )
            } else {
                ForEach(projects) { project in
                    NavigationLink {
                        ProjectInventoryView(project: project)
                    } label: {
                        InventoryProjectRow(project: project)
                    }
                }
            }
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            projects = try await MarketingConvexAPIService.getMarketingProjects(token: token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct InventoryProjectRow: View {
    let project: MarketingProject

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(project.name ?? "Unnamed project")
                .font(AppModuleFont.rowTitle)
            Text(meta)
                .font(AppModuleFont.rowMeta)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
    }

    private var meta: String {
        var parts: [String] = []
        if let scope = project.scope { parts.append("Scope: \(AppModuleFormatters.prettyScope(scope))") }
        if let status = project.status { parts.append("Status: \(status)") }
        if let location = project.location { parts.append(location) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

struct ProjectInventoryView: View {
    @Environment(AuthStore.self) private var authStore
    let project: MarketingProject

    @State private var unitTypeFilter: String?
    @State private var facingFilter: String?
    @State private var statusFilter: String?
    @State private var units: [InventoryUnit] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var actionUnitId: String?
    @State private var detailUnit: InventoryUnit?

    private var canCreateBooking: Bool {
        authStore.hasPermission("marketing.bookings.create")
    }

    private var allowedUnitTypes: [(String?, String)] {
        let all: [(String?, String)] = [(nil, "All"), ("plot", "Plot"), ("villa", "Villa"), ("flat", "Flat")]
        return all.filter { option in
            guard let type = option.0, let scope = project.scope else { return true }
            switch scope {
            case "mixed": return true
            case "plots_only": return type == "plot"
            case "villas": return type == "villa"
            case "flats": return type == "flat"
            default: return true
            }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name ?? "Project")
                        .font(AppModuleFont.screenTitle)
                    if let scope = project.scope {
                        Text("Scope: \(AppModuleFormatters.prettyScope(scope))")
                            .font(AppModuleFont.rowMeta)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink {
                    InventoryLayoutMapView(project: project)
                } label: {
                    Label("Open Layout Map", systemImage: "map")
                }
            }

            Section("Filters") {
                filterScroll(options: allowedUnitTypes, selected: $unitTypeFilter)
                filterScroll(
                    options: [(nil, "All"), ("N", "N"), ("E", "E"), ("S", "S"), ("W", "W"), ("NE", "NE"), ("NW", "NW"), ("SE", "SE"), ("SW", "SW")],
                    selected: $facingFilter
                )
                filterScroll(
                    options: [(nil, "All"), ("available", "Available"), ("held", "Held"), ("booked", "Booked"), ("sold", "Sold")],
                    selected: $statusFilter
                )
            }

            Section {
                HStack {
                    Text("Units")
                    Spacer()
                    Text(isLoading ? "" : "\(units.count) unit\(units.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                if isLoading && units.isEmpty {
                    ProgressView("Loading units…")
                } else if units.isEmpty {
                    ContentUnavailableView(
                        "No Units",
                        systemImage: "square.grid.3x3",
                        description: Text(errorMessage ?? "No units match the current filter.")
                    )
                } else {
                    ForEach(units) { unit in
                        if canCreateBooking && unit.status == "available" {
                            NavigationLink {
                                BookingCreateView(
                                    initialProject: project,
                                    initialUnit: unit
                                )
                            } label: {
                                InventoryUnitRow(unit: unit)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                unitActions(for: unit)
                            }
                            .contextMenu {
                                unitActions(for: unit)
                            }
                        } else {
                            InventoryUnitRow(unit: unit)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    unitActions(for: unit)
                                }
                                .contextMenu {
                                    unitActions(for: unit)
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle(project.name ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: unitTypeFilter) { _, _ in Task { await load() } }
        .onChange(of: facingFilter) { _, _ in Task { await load() } }
        .onChange(of: statusFilter) { _, _ in Task { await load() } }
        .sheet(item: $detailUnit) { unit in
            NavigationStack {
                InventoryUnitDetailView(unit: unit)
            }
        }
        .alert("Inventory", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("OK", role: .cancel) { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
    }

    @ViewBuilder
    private func unitActions(for unit: InventoryUnit) -> some View {
        Button {
            Task { await loadDetail(for: unit) }
        } label: {
            Label("Details", systemImage: "info.circle")
        }

        if unit.status == "available" {
            Button {
                Task { await updateHoldState(for: unit, hold: true) }
            } label: {
                Label(actionUnitId == unit.id ? "Holding..." : "Hold", systemImage: "pause.circle")
            }
            .disabled(actionUnitId != nil)
            .tint(.orange)
        }

        if unit.status == "held" {
            Button {
                Task { await updateHoldState(for: unit, hold: false) }
            } label: {
                Label(actionUnitId == unit.id ? "Releasing..." : "Release", systemImage: "arrow.uturn.backward.circle")
            }
            .disabled(actionUnitId != nil)
            .tint(.blue)
        }
    }

    private func filterScroll(options: [(String?, String)], selected: Binding<String?>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.1) { value, label in
                    Button {
                        selected.wrappedValue = value
                    } label: {
                        Text(label)
                            .font(AppModuleFont.rowMetaSemibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected.wrappedValue == value ? .white : .primary)
                            .background(
                                selected.wrappedValue == value ? Color(hex: 0x0B61CA) : Color(.systemGray5),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            units = try await MarketingConvexAPIService.listInventoryUnits(
                token: token,
                projectId: project.id,
                unitType: unitTypeFilter,
                facing: facingFilter,
                status: statusFilter
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadDetail(for unit: InventoryUnit) async {
        guard let token = authStore.currentSession?.token else { return }
        actionUnitId = unit.id
        defer { actionUnitId = nil }
        do {
            detailUnit = try await MarketingConvexAPIService.getInventoryUnit(token: token, id: unit.id)
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    @MainActor
    private func updateHoldState(for unit: InventoryUnit, hold: Bool) async {
        guard let token = authStore.currentSession?.token else { return }
        actionUnitId = unit.id
        defer { actionUnitId = nil }
        do {
            _ = hold
                ? try await MarketingConvexAPIService.holdInventoryUnit(token: token, id: unit.id)
                : try await MarketingConvexAPIService.releaseInventoryUnit(token: token, id: unit.id)
            await load()
            actionMessage = hold ? "Unit held" : "Unit released"
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

private struct InventoryUnitRow: View {
    let unit: InventoryUnit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(unit.unitNumber ?? "—")  ·  \(unit.unitType ?? "unit")")
                    .font(AppModuleFont.rowTitle)
                Text(meta)
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            AppModuleBadge(text: unit.status, tint: statusColor)
        }
        .padding(.vertical, 5)
    }

    private var meta: String {
        var parts: [String] = []
        if let facing = unit.facing { parts.append("Facing \(facing)") }
        if let area = unit.area { parts.append("\(area.formatted(.number.precision(.fractionLength(0...2)))) sqft") }
        if let dimensions = unit.dimensions { parts.append(dimensions) }
        if let floor = unit.floor { parts.append("Floor \(floor)") }
        if let price = unit.priceSnapshot { parts.append(AppModuleFormatters.rupees(price)) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch unit.status {
        case "available": return Color(hex: 0x067647)
        case "held": return Color(hex: 0xB54708)
        case "booked": return Color(hex: 0x1849A9)
        case "sold": return Color(hex: 0xB42318)
        default: return Color(hex: 0x475467)
        }
    }
}

private struct InventoryUnitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let unit: InventoryUnit

    var body: some View {
        List {
            Section("Unit") {
                detailRow("Unit No", unit.unitNumber)
                detailRow("Type", unit.unitType)
                detailRow("Status", unit.status.capitalized)
                detailRow("Facing", unit.facing)
                detailRow("Block", unit.block)
                if let floor = unit.floor {
                    detailRow("Floor", String(floor))
                }
            }

            Section("Dimensions") {
                if let area = unit.area {
                    detailRow("Area", "\(area.formatted(.number.precision(.fractionLength(0...2)))) sqft")
                }
                detailRow("Dimensions", unit.dimensions)
                if let price = unit.priceSnapshot {
                    detailRow("Price", AppModuleFormatters.rupees(price))
                }
            }

            Section("Booking") {
                detailRow("Customer", unit.customerName)
                detailRow("Reserved Booking", unit.reservedByBookingId)
                detailRow("Sold Booking", unit.soldByBookingId)
            }

            if unit.layoutId != nil || unit.layoutCoordinates != nil {
                Section("Layout") {
                    detailRow("Layout ID", unit.layoutId)
                    if let coordinates = unit.layoutCoordinates {
                        detailRow("Shape", coordinates.shape)
                        if let x = coordinates.x, let y = coordinates.y {
                            detailRow("Position", "\(x.formatted()) × \(y.formatted())")
                        }
                        if let width = coordinates.width, let height = coordinates.height {
                            detailRow("Size", "\(width.formatted()) × \(height.formatted())")
                        }
                    }
                }
            }
        }
        .navigationTitle(unit.unitNumber ?? "Unit Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String?) -> some View {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LabeledContent(title, value: trimmed?.isEmpty == false ? trimmed! : "—")
    }
}

struct InventoryLayoutMapView: View {
    @Environment(AuthStore.self) private var authStore
    let project: MarketingProject

    @State private var units: [InventoryUnit] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var rectUnits: [InventoryUnit] {
        units.filter {
            $0.layoutCoordinates?.shape == "rect"
                && $0.layoutCoordinates?.x != nil
                && $0.layoutCoordinates?.y != nil
                && $0.layoutCoordinates?.width != nil
                && $0.layoutCoordinates?.height != nil
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(rectUnits.count) rect unit\(rectUnits.count == 1 ? "" : "s")")
                    .font(AppModuleFont.rowTitle)
                Spacer()
            }
            .padding(.horizontal)

            if isLoading {
                ProgressView("Loading layout…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rectUnits.isEmpty {
                ContentUnavailableView(
                    "No Layout",
                    systemImage: "map",
                    description: Text(errorMessage ?? "No layout coordinates published yet.")
                )
            } else {
                UnitMapCanvas(units: rectUnits)
                    .frame(minHeight: 420)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(project.name ?? "Project") · Layout")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            units = try await MarketingConvexAPIService.getInventoryLayout(token: token, projectId: project.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UnitMapCanvas: View {
    let units: [InventoryUnit]

    var body: some View {
        Canvas { context, size in
            let rects = units.compactMap { unit -> (InventoryUnit, CGRect)? in
                guard let c = unit.layoutCoordinates,
                      let x = c.x, let y = c.y, let width = c.width, let height = c.height
                else { return nil }
                return (unit, CGRect(x: x, y: y, width: width, height: height))
            }
            guard let bounds = rects.map(\.1).reduce(nil, { current, rect in
                current?.union(rect) ?? rect
            }) else { return }

            let padding: CGFloat = 16
            let scale = min(
                (size.width - padding * 2) / max(bounds.width, 1),
                (size.height - padding * 2) / max(bounds.height, 1)
            )
            let offsetX = padding - bounds.minX * scale
            let offsetY = padding - bounds.minY * scale

            for (unit, source) in rects {
                let rect = CGRect(
                    x: source.minX * scale + offsetX,
                    y: source.minY * scale + offsetY,
                    width: source.width * scale,
                    height: source.height * scale
                )
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(path, with: .color(fillColor(for: unit.status)))
                context.stroke(path, with: .color(Color(hex: 0x475467)), lineWidth: 1.5)
                if let label = unit.unitNumber {
                    context.draw(
                        Text(label).font(AppModuleFont.rowMetaSemibold).foregroundStyle(Color(hex: 0x101828)),
                        at: CGPoint(x: rect.midX, y: rect.midY)
                    )
                }
            }
        }
        .padding(4)
    }

    private func fillColor(for status: String) -> Color {
        switch status {
        case "available": return Color(hex: 0xD1FADF)
        case "held": return Color(hex: 0xFEDF89)
        case "booked": return Color(hex: 0xB2DDFF)
        case "sold": return Color(hex: 0xFECDCA)
        default: return Color(hex: 0xF2F4F7)
        }
    }
}
