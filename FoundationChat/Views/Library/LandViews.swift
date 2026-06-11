import SwiftUI

struct LandInspectionView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var inspections: [LandInspection] = []
    @State private var searchText = ""
    @State private var selectedStatus: LandInspectionStatusFilter = .all
    @State private var filterDate = Date()
    @State private var useDateFilter = false
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var editingInspection: LandInspection?
    @State private var reschedulingInspection: LandInspection?

    private var filteredInspections: [LandInspection] {
        inspections.filter { inspection in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || inspection.title.localizedCaseInsensitiveContains(query)
                || inspection.subtitle.localizedCaseInsensitiveContains(query)
                || (inspection.referenceNo ?? "").localizedCaseInsensitiveContains(query)
            let status = (inspection.derivedInspectionStatus ?? inspection.status ?? "").lowercased()
            let matchesStatus: Bool = {
                switch selectedStatus {
                case .all: return true
                case .inProgress: return status.contains("progress") || status.contains("saved")
                case .completed: return status.contains("completed") || status.contains("approved")
                case .notStarted: return status.isEmpty || status.contains("not_started") || status.contains("pending")
                }
            }()
            let matchesDate = !useDateFilter
                || inspection.scheduledDate?.prefix(10) == AppModuleFormatters.ymd.string(from: filterDate)[...]
            return matchesSearch && matchesStatus && matchesDate
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                controls

                if isLoading && inspections.isEmpty {
                    AppModuleLoadingRows()
                } else if filteredInspections.isEmpty {
                    ContentUnavailableView(
                        inspections.isEmpty ? "No Inspections" : "No Matches",
                        systemImage: "map",
                        description: Text(errorMessage ?? "Inspection/property list will appear here.")
                    )
                    .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredInspections) { inspection in
                            LandInspectionRow(inspection: inspection)
                                .contentShape(Rectangle())
                                .onTapGesture { editingInspection = inspection }
                                .contextMenu {
                                    Button {
                                        editingInspection = inspection
                                    } label: {
                                        Label("Inspect", systemImage: "square.and.pencil")
                                    }
                                    Button {
                                        reschedulingInspection = inspection
                                    } label: {
                                        Label("Reschedule", systemImage: "calendar")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Land Inspection")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .sheet(item: $editingInspection) { inspection in
            LandInspectionSheet(inspection: inspection) {
                await load()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $reschedulingInspection) { inspection in
            LandInspectionRescheduleSheet(inspection: inspection) {
                await load()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Land Inspection", isPresented: Binding(
            get: { errorMessage != nil && hasLoaded && inspections.isEmpty },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search inspections", text: $searchText)
                    .textInputAutocapitalization(.never)
                Button {
                    useDateFilter.toggle()
                } label: {
                    Image(systemName: useDateFilter ? "calendar.badge.checkmark" : "calendar")
                }
                .buttonStyle(.bordered)
                .tint(Color(hex: 0x0B61CA))
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))

            if useDateFilter {
                HStack {
                    DatePicker("Date", selection: $filterDate, displayedComponents: .date)
                    Button("Clear") { useDateFilter = false }
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            }

            Picker("Status", selection: $selectedStatus) {
                ForEach(LandInspectionStatusFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
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
            inspections = try await LandConvexAPIService.listInspections(
                token: token,
                fromDate: useDateFilter ? AppModuleFormatters.ymd.string(from: filterDate) : nil,
                toDate: useDateFilter ? AppModuleFormatters.ymd.string(from: filterDate) : nil
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum LandInspectionStatusFilter: String, CaseIterable, Identifiable {
    case all
    case inProgress
    case completed
    case notStarted

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .notStarted: return "Not Started"
        }
    }
}

private struct LandInspectionRow: View {
    let inspection: LandInspection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(inspection.title)
                        .font(AppModuleFont.rowTitle)
                    if !inspection.subtitle.isEmpty {
                        Text(inspection.subtitle)
                            .font(AppModuleFont.rowMeta)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                AppModuleBadge(text: inspection.displayStatus, tint: statusColor)
            }

            HStack(spacing: 12) {
                if let date = inspection.scheduledDate?.landNilIfBlank {
                    Label(String(date.prefix(10)), systemImage: "calendar")
                }
                if let area = inspection.totalArea {
                    Label("\(area, specifier: "%.0f") \(inspection.areaUnit ?? "")", systemImage: "square")
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(AppModuleFont.rowMeta)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusColor: Color {
        switch (inspection.derivedInspectionStatus ?? inspection.status ?? "").lowercased() {
        case let value where value.contains("completed") || value.contains("approved"):
            return .green
        case let value where value.contains("progress") || value.contains("saved"):
            return .orange
        case let value where value.contains("rejected") || value.contains("cancelled"):
            return .red
        default:
            return Color(hex: 0x0B61CA)
        }
    }
}

private enum SiteInspectionTab: String, CaseIterable, Identifiable {
    case basic
    case area
    case market
    case conclusions
    case competitors

    var id: String { rawValue }
    var title: String {
        switch self {
        case .basic: return "Basic"
        case .area: return "Area"
        case .market: return "Market"
        case .conclusions: return "Conclusions"
        case .competitors: return "Competitors"
        }
    }

    var icon: String {
        switch self {
        case .basic: return "person.text.rectangle"
        case .area: return "checkmark.circle"
        case .market: return "chart.bar"
        case .conclusions: return "target"
        case .competitors: return "chart.line.uptrend.xyaxis"
        }
    }
}

private struct LandInspectionSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let inspection: LandInspection
    let onSaved: () async -> Void

    @State private var selectedTab: SiteInspectionTab = .basic
    @State private var ownerName: String
    @State private var surveyNo: String
    @State private var siteLocation: String
    @State private var exactLocation = ""
    @State private var landmark = ""
    @State private var mapLink = ""
    @State private var population = ""
    @State private var selectedRoadTypes: Set<String> = []
    @State private var accessWidth = ""
    @State private var accessWidthUnit = "Feet"
    @State private var electricity = ""
    @State private var eConnection = ""
    @State private var telecom = ""
    @State private var railway = ""
    @State private var bus = ""
    @State private var schools: [LandAreaEntry] = []
    @State private var colleges: [LandAreaEntry] = []
    @State private var hospitals: [LandAreaEntry] = []
    @State private var malls: [LandAreaEntry] = []
    @State private var markets: [LandAreaEntry] = []
    @State private var presentDemand = ""
    @State private var futureDemand = ""
    @State private var targetClients: Set<String> = []
    @State private var landlordPrice = ""
    @State private var recommendedPrice = ""
    @State private var sellingPrice = ""
    @State private var priceUnit = "sqft"
    @State private var conclusion = ""
    @State private var competitors: [LandCompetitorEntry] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let roadTypes = ["Tar", "Mud", "Concrete", "Gravel"]
    private let targetOptions = ["Investors", "End users", "Developers", "Farmers", "NRIs"]
    private let demandOptions = ["Low", "Medium", "High"]
    private var isViewOnly: Bool { inspection.isVPApproved }

    init(inspection: LandInspection, onSaved: @escaping () async -> Void) {
        self.inspection = inspection
        self.onSaved = onSaved
        _ownerName = State(initialValue: inspection.ownerName ?? "")
        _surveyNo = State(initialValue: inspection.surveyNo ?? "")
        _siteLocation = State(initialValue: inspection.fullAddress ?? inspection.location ?? "")
        _exactLocation = State(initialValue: inspection.exactLocation ?? "")
        _landmark = State(initialValue: inspection.landmark ?? "")
        _mapLink = State(initialValue: inspection.latLong ?? "")
        _population = State(initialValue: inspection.population ?? "")
        _selectedRoadTypes = State(initialValue: Set((inspection.roadType ?? []).map { $0.lowercased() }))
        _accessWidth = State(initialValue: inspection.accessibilityWidth ?? "")
        _accessWidthUnit = State(initialValue: inspection.accessibilityWidthUnit ?? "Feet")
        _electricity = State(initialValue: inspection.electricity ?? "")
        _eConnection = State(initialValue: inspection.eConnectionToLand ?? "")
        _telecom = State(initialValue: inspection.telecom ?? "")
        _railway = State(initialValue: inspection.railwayStationDistance ?? "")
        _bus = State(initialValue: inspection.busStopDistance ?? "")
        _schools = State(initialValue: inspection.schoolEntries ?? [])
        _colleges = State(initialValue: inspection.collegeEntries ?? [])
        _hospitals = State(initialValue: inspection.hospitalEntries ?? [])
        _malls = State(initialValue: inspection.mallEntries ?? [])
        _markets = State(initialValue: inspection.marketEntries ?? [])
        _presentDemand = State(initialValue: inspection.presentDemand?.first ?? "")
        _futureDemand = State(initialValue: inspection.futureDemand?.first ?? "")
        _targetClients = State(initialValue: Set(inspection.targetClients ?? []))
        _landlordPrice = State(initialValue: inspection.landlordPrice.map { String($0) } ?? "")
        _recommendedPrice = State(initialValue: inspection.recommendationPrice.map { String($0) } ?? "")
        _sellingPrice = State(initialValue: inspection.priceCanSell.map { String($0) } ?? "")
        _priceUnit = State(initialValue: inspection.priceCanSellUnit ?? inspection.recommendationPriceUnit ?? inspection.landlordPriceUnit ?? "sqft")
        _conclusion = State(initialValue: inspection.conclusion ?? inspection.inspectionDetails ?? "")
        _competitors = State(initialValue: inspection.competitors ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 52, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)

                    header
                    if isViewOnly {
                        viewOnlyBanner
                    }
                    tabStrip

                    switch selectedTab {
                    case .basic: basicSection
                    case .area: areaSection
                    case .market: marketSection
                    case .conclusions: conclusionSection
                    case .competitors: competitorsSection
                    }

                    if let errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(errorMessage)
                        }
                        .font(AppModuleFont.rowMetaSemibold)
                        .foregroundStyle(.red)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isViewOnly ? "Done" : "Cancel") { dismiss() }
                }
                if !isViewOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Saving..." : "Save") { save() }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving)
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Site Inspection")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(hex: 0x111827))
            Text("Information about Land Procurement")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var viewOnlyBanner: some View {
        Text("Approved by VP - View only")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color(hex: 0x0B61CA))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(hex: 0xDDEBFF), in: RoundedRectangle(cornerRadius: 18))
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(SiteInspectionTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(selectedTab == tab ? Color(hex: 0x0B61CA) : Color.clear)
                                    .frame(width: 48, height: 48)
                                Image(systemName: tab.icon)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                            }
                            Text(tab.title)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? Color(hex: 0x0B61CA) : .secondary)
                            Rectangle()
                                .fill(selectedTab == tab ? Color(hex: 0x0B61CA) : Color.clear)
                                .frame(width: 42, height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Basic Details", subtitle: "Fill all the details about the site")
            fieldCard("Land Owner Name", text: $ownerName, placeholder: "Enter Details", icon: "person.text.rectangle", required: true)
            fieldCard("Survey No", text: $surveyNo, placeholder: "Enter Details", icon: "doc.text")
            fieldCard("Site Location", text: $siteLocation, placeholder: "Enter Location", icon: "checkmark.circle", required: true, axis: .vertical)
            fieldCard("Exact Location", text: $exactLocation, placeholder: "Enter Exact Location", icon: "mappin.circle", required: true, axis: .vertical)
            fieldCard("Land Mark", text: $landmark, placeholder: "Enter Landmark", icon: "point.3.connected.trianglepath.dotted", required: true)
            fieldCard("Google Map Link", text: $mapLink, placeholder: "Paste Map Link", icon: "link", required: true)
            fieldCard("Populations", text: $population, placeholder: "Enter Population", icon: "person.2", required: true)

            optionCard(title: "Road Type", options: roadTypes, selection: $selectedRoadTypes)

            sectionTitle("Accessibility", subtitle: "Road, power and connectivity details")
            HStack(spacing: 10) {
                fieldCard("Access Width", text: $accessWidth, placeholder: "Width", icon: "ruler", compact: true)
                menuCard("Unit", selection: $accessWidthUnit, options: ["Feet", "Meter"], icon: "arrow.left.and.right")
            }
            fieldCard("Electricity Cable Above Land", text: $electricity, placeholder: "Enter Details", icon: "bolt")
            fieldCard("E-Connection To Land", text: $eConnection, placeholder: "Enter Details", icon: "powerplug")
            fieldCard("Telecom", text: $telecom, placeholder: "Enter Details", icon: "phone.connection")
            fieldCard("Railway Station Distance", text: $railway, placeholder: "Enter Distance", icon: "tram")
            fieldCard("Bus Stop Distance", text: $bus, placeholder: "Enter Distance", icon: "bus")
        }
    }

    private var areaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Area", subtitle: "Nearby amenities and distance")
            areaEditor(title: "Schools", entries: $schools)
            areaEditor(title: "Colleges", entries: $colleges)
            areaEditor(title: "Hospitals", entries: $hospitals)
            areaEditor(title: "Mall", entries: $malls)
            areaEditor(title: "Market", entries: $markets)
        }
    }

    private var marketSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Market", subtitle: "Demand, target clients and price inputs")
            menuCard("Present Demand", selection: $presentDemand, options: demandOptions.map { $0.lowercased() }, icon: "chart.line.uptrend.xyaxis")
            menuCard("Future Demand", selection: $futureDemand, options: demandOptions.map { $0.lowercased() }, icon: "chart.bar")
            optionCard(title: "Target Clients", options: targetOptions, selection: $targetClients)
            HStack(spacing: 10) {
                fieldCard("Landlord Price", text: $landlordPrice, placeholder: "Amount", icon: "indianrupeesign.circle", compact: true)
                menuCard("Unit", selection: $priceUnit, options: ["sqft", "cent", "acre"], icon: "square")
            }
            fieldCard("Recommended Price", text: $recommendedPrice, placeholder: "Amount", icon: "indianrupeesign.circle")
            fieldCard("Selling Price", text: $sellingPrice, placeholder: "Amount", icon: "indianrupeesign.circle")
        }
    }

    private var conclusionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Conclusion", subtitle: "Recommendation/conclusion")
            fieldCard("Recommendation / Conclusion", text: $conclusion, placeholder: "Enter recommendation", icon: "target", required: true, axis: .vertical, minHeight: 132)
        }
    }

    private var competitorsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Competitors", subtitle: "Competitor project entries")
            if competitors.isEmpty {
                Text("No competitor entries yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            }
            ForEach($competitors) { $competitor in
                CompetitorEditor(competitor: $competitor, isViewOnly: isViewOnly) {
                    competitors.removeAll { $0.id == competitor.id }
                }
            }
            if !isViewOnly {
                Button {
                    competitors.append(LandCompetitorEntry())
                } label: {
                    Label("Add Competitor", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x0B61CA))
            }
        }
    }

    private func areaEditor(title: String, entries: Binding<[LandAreaEntry]>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
            if entries.wrappedValue.isEmpty {
                Text("No \(title.lowercased()) added.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            }
            ForEach(entries) { $entry in
                HStack(spacing: 10) {
                    fieldCard("\(title) Name", text: $entry.name, placeholder: "Name", icon: "mappin.and.ellipse", compact: true)
                    fieldCard("Distance", text: $entry.distance, placeholder: "Distance", icon: "arrow.left.and.right", compact: true)
                }
            }
            if !isViewOnly {
                Button {
                    entries.wrappedValue.append(LandAreaEntry())
                } label: {
                    Label("Add \(title)", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color(hex: 0x0B61CA))
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(hex: 0x111827))
            Text(subtitle)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }

    private func fieldCard(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        icon: String,
        required: Bool = false,
        axis: Axis = .horizontal,
        minHeight: CGFloat = 76,
        compact: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                Text(label)
                if required {
                    Text("*").foregroundStyle(.red)
                }
            }
            .font(.system(size: compact ? 12 : 15, weight: .semibold))
            .foregroundStyle(Color(hex: 0x374151))

            HStack(alignment: axis == .vertical ? .top : .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 18 : 22, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 24)
                if isViewOnly {
                    Text(text.wrappedValue.landNilIfBlank ?? placeholder)
                        .font(.system(size: compact ? 15 : 20, weight: text.wrappedValue.landNilIfBlank == nil ? .regular : .semibold))
                        .foregroundStyle(text.wrappedValue.landNilIfBlank == nil ? .secondary.opacity(0.65) : Color(hex: 0x111827))
                        .lineLimit(axis == .vertical ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(placeholder, text: text, axis: axis)
                        .font(.system(size: compact ? 15 : 20, weight: .regular))
                        .foregroundStyle(Color(hex: 0x111827))
                        .textInputAutocapitalization(.sentences)
                        .lineLimit(axis == .vertical ? 6 : 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: minHeight, alignment: .center)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func menuCard(_ label: String, selection: Binding<String>, options: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x374151))
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 24)
                if isViewOnly {
                    Text(selection.wrappedValue.landNilIfBlank?.capitalized ?? "-")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x111827))
                    Spacer()
                } else {
                    Picker(label, selection: selection) {
                        Text("Select").tag("")
                        ForEach(options, id: \.self) { option in
                            Text(option.capitalized).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 76)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func optionCard(title: String, options: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x111827))
            VStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Toggle(option, isOn: Binding(
                        get: {
                            selection.wrappedValue.contains(option)
                                || selection.wrappedValue.contains(option.lowercased())
                        },
                        set: { isOn in
                            if isOn { selection.wrappedValue.insert(option.lowercased()) }
                            else {
                                selection.wrappedValue.remove(option)
                                selection.wrappedValue.remove(option.lowercased())
                            }
                        }
                    ))
                    .disabled(isViewOnly)
                    .padding(.vertical, 10)
                    if option != options.last {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func save() {
        guard !isViewOnly else { return }
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            return
        }
        guard !ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Owner is required."
            selectedTab = .basic
            return
        }
        guard !siteLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Site location is required."
            selectedTab = .basic
            return
        }
        guard !conclusion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Recommendation/conclusion is required."
            selectedTab = .conclusions
            return
        }
        let request = SaveLandInspectionRequest(
            id: inspection.reportId ?? inspection.id,
            propertyId: inspection.id,
            propertyName: inspection.title,
            ownerName: ownerName.landNilIfBlank,
            location: siteLocation.landNilIfBlank,
            scheduledDate: inspection.scheduledDate.map { String($0.prefix(10)) } ?? AppModuleFormatters.ymd.string(from: Date()),
            inspectionDetails: conclusion,
            competitorDetails: competitors.compactMap(\.projectName.landNilIfBlank).joined(separator: ", ").landNilIfBlank,
            amenityDetails: [schools, colleges, hospitals, malls, markets].flatMap { $0 }.compactMap(\.name.landNilIfBlank).joined(separator: ", ").landNilIfBlank,
            targetDetails: Array(targetClients).joined(separator: ", ").landNilIfBlank,
            notes: nil,
            customerName: ownerName.landNilIfBlank,
            surveyNo: surveyNo.landNilIfBlank,
            siteLocation: siteLocation.landNilIfBlank,
            exactLocation: exactLocation.landNilIfBlank,
            landmark: landmark.landNilIfBlank,
            latLong: mapLink.landNilIfBlank,
            population: population.landNilIfBlank,
            roadType: Array(selectedRoadTypes).nilIfEmpty,
            accessibilityWidth: accessWidth.landNilIfBlank,
            accessibilityWidthUnit: accessWidthUnit.landNilIfBlank,
            electricity: electricity.landNilIfBlank,
            eConnectionToLand: eConnection.landNilIfBlank,
            telecom: telecom.landNilIfBlank,
            railwayStationDistance: railway.landNilIfBlank,
            busStopDistance: bus.landNilIfBlank,
            schoolExists: schools.nonBlankAreaEntries != nil ? true : nil,
            schoolEntries: schools.nonBlankAreaEntries,
            collegeExists: colleges.nonBlankAreaEntries != nil ? true : nil,
            collegeEntries: colleges.nonBlankAreaEntries,
            hospitalExists: hospitals.nonBlankAreaEntries != nil ? true : nil,
            hospitalEntries: hospitals.nonBlankAreaEntries,
            mallExists: malls.nonBlankAreaEntries != nil ? true : nil,
            mallEntries: malls.nonBlankAreaEntries,
            marketExists: markets.nonBlankAreaEntries != nil ? true : nil,
            marketEntries: markets.nonBlankAreaEntries,
            presentDemand: presentDemand.landNilIfBlank.map { [$0] },
            futureDemand: futureDemand.landNilIfBlank.map { [$0] },
            targetClients: Array(targetClients).nilIfEmpty,
            landlordPrice: Double(landlordPrice),
            landlordPriceUnit: priceUnit,
            recommendationPrice: Double(recommendedPrice),
            recommendationPriceUnit: priceUnit,
            priceCanSell: Double(sellingPrice),
            priceCanSellUnit: priceUnit,
            conclusion: conclusion.landNilIfBlank,
            competitors: competitors.nonBlankCompetitors
        )

        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                _ = try await LandConvexAPIService.saveInspection(token: token, request: request)
                await onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct CompetitorEditor: View {
    @Binding var competitor: LandCompetitorEntry
    let isViewOnly: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Competitor")
                    .font(AppModuleFont.rowMetaSemibold)
                Spacer()
                if !isViewOnly {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            TextField("Promoter name", text: $competitor.promoterName)
            TextField("Project name", text: $competitor.projectName)
            TextField("Location", text: $competitor.location)
            TextField("Map link / lat long", text: $competitor.latLong)
            TextField("Extent units", text: $competitor.extentUnits)
            Picker("Approval", selection: $competitor.approvalType) {
                Text("None").tag("")
                Text("CMDA").tag("cmda")
                Text("DTCP").tag("dtcp")
                Text("Panchayat").tag("panchayat")
            }
            TextField("Amenities", text: $competitor.amenities, axis: .vertical)
            TextField("Current stage", text: $competitor.currentStage)
            TextField("Distance from project", text: $competitor.distanceFromProject)
            TextField("Distance from bus stand", text: $competitor.distanceFromBusStand)
            TextField("Distance from railway", text: $competitor.distanceFromRailway)
            HStack {
                TextField("Actual price", value: $competitor.actualPrice, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Final price", value: $competitor.finalPrice, format: .number)
                    .keyboardType(.decimalPad)
            }
        }
        .disabled(isViewOnly)
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct LandInspectionRescheduleSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let inspection: LandInspection
    let onSaved: () async -> Void

    @State private var date: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(inspection: LandInspection, onSaved: @escaping () async -> Void) {
        self.inspection = inspection
        self.onSaved = onSaved
        _date = State(initialValue: AppModuleFormatters.ymd.date(from: inspection.scheduledDate ?? "") ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(inspection.title) {
                    DatePicker("New date", selection: $date, displayedComponents: .date)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            return
        }
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await LandConvexAPIService.rescheduleInspection(
                    token: token,
                    request: RescheduleLandInspectionRequest(
                        id: inspection.id,
                        scheduledDate: AppModuleFormatters.ymd.string(from: date)
                    )
                )
                await onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct LandQueriesView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var queries: [LandQueryLog] = []
    @State private var selectedQuery: LandQueryLog?
    @State private var searchText = ""
    @State private var selectedStatus: LandQueryStatusFilter = .all
    @State private var filterDate = Date()
    @State private var useDateFilter = false
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var filteredQueries: [LandQueryLog] {
        queries.filter { query in
            let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = search.isEmpty
                || query.displayTitle.localizedCaseInsensitiveContains(search)
                || (query.description ?? "").localizedCaseInsensitiveContains(search)
                || (query.referenceNo ?? "").localizedCaseInsensitiveContains(search)
            let matchesStatus: Bool = {
                switch selectedStatus {
                case .all: return true
                case .pending: return query.resolved != true && !query.displayStatus.localizedCaseInsensitiveContains("completed")
                case .completed: return query.resolved == true || query.displayStatus.localizedCaseInsensitiveContains("completed")
                }
            }()
            let matchesDate = !useDateFilter
                || query.rawDate == AppModuleFormatters.ymd.string(from: filterDate)
            return matchesSearch && matchesStatus && matchesDate
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                queryControls
                if isLoading && queries.isEmpty {
                    AppModuleLoadingRows()
                } else if filteredQueries.isEmpty {
                    ContentUnavailableView(
                        queries.isEmpty ? "No Queries" : "No Matches",
                        systemImage: "questionmark.bubble",
                        description: Text(errorMessage ?? "Query logs will appear here.")
                    )
                    .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredQueries) { query in
                            Button {
                                selectedQuery = query
                            } label: {
                                LandQueryRow(query: query)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Queries")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .sheet(item: $selectedQuery) { query in
            LandQueryDetailSheet(query: query)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var queryControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search queries", text: $searchText)
                    .textInputAutocapitalization(.never)
                Button {
                    useDateFilter.toggle()
                } label: {
                    Image(systemName: useDateFilter ? "calendar.badge.checkmark" : "calendar")
                }
                .buttonStyle(.bordered)
                .tint(Color(hex: 0x0B61CA))
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))

            if useDateFilter {
                HStack {
                    DatePicker("Date", selection: $filterDate, displayedComponents: .date)
                    Button("Clear") { useDateFilter = false }
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            }

            Picker("Status", selection: $selectedStatus) {
                ForEach(LandQueryStatusFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
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
            queries = try await LandConvexAPIService.listQueries(token: token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum LandQueryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case completed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .pending: return "Pending"
        case .completed: return "Completed"
        }
    }
}

private struct LandQueryRow: View {
    let query: LandQueryLog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(query.displayTitle)
                        .font(AppModuleFont.rowTitle)
                    Text(query.referenceNo?.landNilIfBlank ?? query.propertyName?.landNilIfBlank ?? "-")
                        .font(AppModuleFont.rowMeta)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                AppModuleBadge(text: query.displayStatus, tint: statusColor)
            }
            if let latest = query.remarks?.landNilIfBlank ?? query.latestUpdate?.landNilIfBlank ?? query.description?.landNilIfBlank {
                Text(latest)
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let date = query.rawDate {
                Label(date, systemImage: "calendar")
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusColor: Color {
        query.displayStatus.localizedCaseInsensitiveContains("completed") ? .green : Color(hex: 0x0B61CA)
    }
}

private struct LandQueryDetailSheet: View {
    let query: LandQueryLog

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Query", value: query.queryNo?.landNilIfBlank ?? query.displayTitle)
                    LabeledContent("Status", value: query.displayStatus)
                    LabeledContent("Priority", value: query.priority?.landNilIfBlank ?? "-")
                    LabeledContent("Property", value: query.propertyName?.landNilIfBlank ?? query.referenceNo?.landNilIfBlank ?? "-")
                }

                if let description = query.description?.landNilIfBlank {
                    Section("Details") { Text(description) }
                }

                Section("Updates") {
                    let updates = query.updates ?? []
                    if updates.isEmpty {
                        Text(query.remarks?.landNilIfBlank ?? query.latestUpdate?.landNilIfBlank ?? "No updates yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(updates) { update in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(update.byName?.landNilIfBlank ?? "Update")
                                        .font(AppModuleFont.rowMetaSemibold)
                                    Spacer()
                                    Text(update.status?.landNilIfBlank ?? "")
                                        .font(AppModuleFont.rowMeta)
                                        .foregroundStyle(.secondary)
                                }
                                Text(update.message?.landNilIfBlank ?? "-")
                                    .font(AppModuleFont.rowBody)
                                if let createdAt = update.createdAt?.landNilIfBlank {
                                    Text(createdAt)
                                        .font(AppModuleFont.rowMeta)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Query Updates")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension Array where Element == LandAreaEntry {
    var nonBlankAreaEntries: [LandAreaEntry]? {
        let rows = filter { $0.name.landNilIfBlank != nil || $0.distance.landNilIfBlank != nil }
            .map { LandAreaEntry(name: $0.name, distance: $0.distance) }
        return rows.isEmpty ? nil : rows
    }
}

private extension Array where Element == LandCompetitorEntry {
    var nonBlankCompetitors: [LandCompetitorEntry]? {
        let rows = filter {
            [
                $0.promoterName, $0.projectName, $0.location, $0.latLong, $0.extentUnits,
                $0.approvalType, $0.amenities, $0.currentStage, $0.distanceFromProject,
                $0.distanceFromBusStand, $0.distanceFromRailway
            ].contains { $0.landNilIfBlank != nil } || $0.actualPrice != nil || $0.finalPrice != nil
        }
        return rows.isEmpty ? nil : rows
    }
}

private extension Array where Element == String {
    var nilIfEmpty: [String]? { isEmpty ? nil : self }
}
