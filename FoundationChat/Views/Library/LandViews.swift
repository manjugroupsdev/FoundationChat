import SwiftUI
import UIKit

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
    @State private var showingDateFilter = false
    @State private var acceptingInspectionIDs: Set<String> = []
    @State private var actionMessage: String?

    private var filteredInspections: [LandInspection] {
        inspections.filter { inspection in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || inspection.title.localizedCaseInsensitiveContains(query)
                || inspection.subtitle.localizedCaseInsensitiveContains(query)
                || (inspection.referenceNo ?? "").localizedCaseInsensitiveContains(query)
                || inspection.inspectionPlace.localizedCaseInsensitiveContains(query)
                || inspection.inspectionAreaLabel.localizedCaseInsensitiveContains(query)
            let status = inspection.inspectionStatusKey
            let matchesStatus: Bool = {
                switch selectedStatus {
                case .all: return true
                case .inProgress: return status == "in_progress"
                case .completed: return status == "completed"
                case .notStarted: return status == "not_started"
                }
            }()
            let matchesDate = !useDateFilter
                || inspection.scheduledDate?.prefix(10) == AppModuleFormatters.ymd.string(from: filterDate)[...]
            return matchesSearch && matchesStatus && matchesDate
        }
    }

    var body: some View {
        ZStack {
            Color(hex: 0xF1F3F8)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    contentPanel
                }
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .sheet(isPresented: $showingDateFilter) {
            LandInspectionDateFilterSheet(date: $filterDate) {
                useDateFilter = true
                showingDateFilter = false
            }
            .appLibraryNativeSheet([.height(470)])
            .presentationBackground(Color.white)
        }
        .sheet(item: $editingInspection) { inspection in
            LandInspectionSheet(inspection: inspection) {
                await load()
            }
            .appLibraryNativeSheet([.height(720), .large])
            .presentationBackground(Color(.systemGroupedBackground))
        }
        .sheet(item: $reschedulingInspection) { inspection in
            LandInspectionRescheduleSheet(inspection: inspection) {
                await load()
            }
            .appLibraryNativeSheet([.medium])
        }
        .alert("Land Inspection", isPresented: Binding(
            get: { (errorMessage != nil && hasLoaded && inspections.isEmpty) || actionMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                actionMessage = nil
            }
        } message: {
            Text(actionMessage ?? errorMessage ?? "")
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x02499D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Inspection")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Manage and track all Inspection")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xD9D6FE))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image("LandInspectionHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 104)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 48)
        }
        .frame(height: 226)
    }

    private var contentPanel: some View {
        VStack(spacing: 0) {
            controls
                .padding(.top, 16)

            if isLoading && inspections.isEmpty {
                AppModuleLoadingRows()
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else if filteredInspections.isEmpty {
                inspectionEmptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredInspections) { inspection in
                        LandInspectionRow(
                            inspection: inspection,
                            isAccepting: acceptingInspectionIDs.contains(inspection.id),
                            onOpen: { handleCardTap(inspection) },
                            onReschedule: { reschedulingInspection = inspection },
                            onAccept: { Task { await accept(inspection) } }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .padding(.bottom, 32)
        .background(Color(hex: 0xF1F3F8))
        .clipShape(.rect(topLeadingRadius: 30, topTrailingRadius: 30))
        .padding(.top, -28)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Search Inspection List", text: $searchText)
                        .font(.system(size: 14, weight: .medium))
                        .textInputAutocapitalization(.never)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                }
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)

                Button {
                    showingDateFilter = true
                } label: {
                    if useDateFilter {
                        VStack(spacing: 0) {
                            Text(AppModuleFormatters.dayNumber.string(from: filterDate))
                                .font(.system(size: 14, weight: .bold))
                            Text(AppModuleFormatters.shortMonth.string(from: filterDate))
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                    } else {
                        Image(systemName: "calendar")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                    }
                }
                .frame(width: 50, height: 50)
                .background(useDateFilter ? Color(hex: 0x0B61CA) : .white, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            }

            if useDateFilter {
                HStack(spacing: 6) {
                    Text("Date · \(AppModuleFormatters.day.string(from: filterDate))")
                        .font(.system(size: 12, weight: .semibold))
                    Button {
                        useDateFilter = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 7)
                .background(Color(hex: 0x0B61CA), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LandInspectionStatusFilter.allCases) { filter in
                        Button {
                            selectedStatus = filter
                        } label: {
                            Text(filter.title)
                                .font(.system(size: 13, weight: selectedStatus == filter ? .semibold : .medium))
                                .foregroundStyle(selectedStatus == filter ? .white : Color(hex: 0x6B7280))
                                .padding(.horizontal, 20)
                                .frame(height: 38)
                                .background(
                                    selectedStatus == filter ? Color(hex: 0x0B61CA) : Color(hex: 0xEEF2F7),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var inspectionEmptyState: some View {
        VStack(spacing: 6) {
            Text(emptyTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
            Text(emptySubtitle)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6B7280))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 52)
    }

    private var emptyTitle: String {
        if !hasLoaded { return "Loading inspections..." }
        return inspections.isEmpty ? "No inspections assigned" : "No matches"
    }

    private var emptySubtitle: String {
        if !hasLoaded { return "Hang on while we fetch your assignments." }
        if inspections.isEmpty {
            return errorMessage ?? "When an admin assigns you to a land property on the web, it will appear here."
        }
        return "Try clearing the date filter, the status chip, or the search box."
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
                token: token
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleCardTap(_ inspection: LandInspection) {
        if inspection.canOpenInspectionForm {
            editingInspection = inspection
        } else {
            actionMessage = "Accept the inspection before filling the form."
        }
    }

    @MainActor
    private func accept(_ inspection: LandInspection) async {
        guard let token = authStore.currentSession?.token else {
            actionMessage = "Not signed in."
            return
        }
        acceptingInspectionIDs.insert(inspection.id)
        defer { acceptingInspectionIDs.remove(inspection.id) }
        do {
            try await LandConvexAPIService.acceptInspection(
                token: token,
                request: AcceptLandInspectionRequest(propertyId: inspection.acceptancePropertyID)
            )
            await load()
        } catch {
            actionMessage = error.localizedDescription
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

private extension LandInspection {
    var inspectionStatusKey: String {
        if reportId?.landNilIfBlank != nil { return "completed" }
        let raw = (derivedInspectionStatus ?? status ?? "")
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        if raw.contains("completed") || raw.contains("approved") { return "completed" }
        if raw.contains("progress") || raw.contains("saved") { return "in_progress" }
        return "not_started"
    }

    var inspectionStatusLabel: String {
        switch inspectionStatusKey {
        case "completed": return "Completed"
        case "in_progress": return "In Progress"
        default: return "Not Started"
        }
    }

    var inspectionPhone: String {
        ownerName?.landNilIfBlank ?? subtitle.landNilIfBlank ?? "—"
    }

    var inspectionPlace: String {
        let area: String? = locality?.landNilIfBlank ?? city?.landNilIfBlank ?? village?.landNilIfBlank
        let dist: String? = district?.landNilIfBlank ?? taluk?.landNilIfBlank
        let joined = [area, dist].compactMap { $0 }.joined(separator: ", ")
        return joined.landNilIfBlank ?? fullAddress?.landNilIfBlank ?? location?.landNilIfBlank ?? "—"
    }

    var inspectionAreaLabel: String {
        guard let totalArea else { return "—" }
        let unit = areaUnit?.landNilIfBlank?.capitalized ?? "Acres"
        return String(format: "%.2f %@", totalArea, unit)
    }

    var inspectionFormattedDate: String {
        guard let raw = scheduledDate?.landNilIfBlank else { return "—" }
        if let date = AppModuleFormatters.ymd.date(from: String(raw.prefix(10))) {
            return AppModuleFormatters.day.string(from: date)
        }
        return raw
    }

    var inspectionAreaDateLabel: String {
        "\(inspectionAreaLabel) • \(inspectionFormattedDate)"
    }

    var isRescheduleRequested: Bool {
        inspectionAcceptanceStatus == "date_change_requested"
    }

    var acceptancePropertyID: String {
        propertyId?.landNilIfBlank ?? id
    }

    var isAcceptedInspection: Bool {
        inspectionAcceptanceStatus == "accepted"
    }

    var canOpenInspectionForm: Bool {
        isAcceptedInspection
            || inspectionAcceptanceStatus?.landNilIfBlank == nil
            || inspectionStatusKey != "not_started"
    }

    var showsOpenArrow: Bool {
        inspectionStatusKey == "completed" || canOpenInspectionForm
    }

    var showsPendingActions: Bool {
        !isRescheduleRequested && !isAcceptedInspection && inspectionStatusKey != "completed"
    }
}

private struct LandInspectionRow: View {
    let inspection: LandInspection
    let isAccepting: Bool
    let onOpen: () -> Void
    let onReschedule: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x0B61CA), Color(hex: 0x3B82F6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(inspection.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)
                    Text(inspection.inspectionPhone)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0x9CA3AF))
                        .lineLimit(1)
                }
                Spacer()
                Text(inspection.inspectionStatusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusStyle.foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(statusStyle.background, in: Capsule())
            }

            Divider()
                .overlay(Color(hex: 0xF2F4F7))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(inspection.inspectionAreaDateLabel, systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x475467))
                        .lineLimit(1)

                    Label(inspection.inspectionPlace, systemImage: "mappin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x065F46))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: 0xDFF7E8), in: Capsule())
                }
                Spacer()

                if inspection.showsOpenArrow {
                    Button(action: onOpen) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .frame(width: 44, height: 44)
                            .background(Color(hex: 0xEAF3FF), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            actionRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 5, y: 1)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    @ViewBuilder
    private var actionRow: some View {
        if inspection.isRescheduleRequested {
            disabledActionButton("Reschedule Requested", systemImage: nil)
        } else if inspection.isAcceptedInspection {
            Button(action: onOpen) {
                actionButtonLabel("Accepted", systemImage: "checkmark", foreground: Color(hex: 0x667085))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(hex: 0xE5E7EB), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.top, 2)
        } else if inspection.showsPendingActions {
            HStack(spacing: 10) {
                Button(action: onReschedule) {
                    actionButtonLabel("Reschedule", systemImage: "calendar.badge.clock", foreground: Color(hex: 0x16A34A))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: 0x16A34A), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onAccept) {
                    actionButtonLabel(isAccepting ? "Accepting..." : "Accept", systemImage: "checkmark", foreground: .white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(hex: 0x08BE00), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isAccepting)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
    }

    private func disabledActionButton(_ title: String, systemImage: String?) -> some View {
        actionButtonLabel(title, systemImage: systemImage, foreground: .white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(hex: 0x08BE00).opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    private func actionButtonLabel(_ title: String, systemImage: String?, foreground: Color) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
            }
            Text(title)
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(foreground)
    }

    private var statusStyle: (foreground: Color, background: Color) {
        switch inspection.inspectionStatusKey {
        case "completed":
            return (Color(hex: 0x065F46), Color(hex: 0xDFF7E8))
        case "in_progress":
            return (Color(hex: 0x92400E), Color(hex: 0xFEF3C7))
        default:
            return (Color(hex: 0x991B1B), Color(hex: 0xFEE2E2))
        }
    }
}

private struct LandInspectionDateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    let onSelect: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("Select Date Filter")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                DatePicker("Inspection Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Color(hex: 0x0B61CA))
                    .padding(.horizontal, 12)

                Spacer(minLength: 0)
            }
            .background(Color.white)
            .navigationTitle("Date Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Select") {
                        onSelect()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                }
            }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
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

                if !isViewOnly {
                    HStack(spacing: 10) {
                        Button("Cancel") { dismiss() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x111827))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
                            )

                        Button(isSaving ? "Saving..." : "Save") { save() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(hex: 0x0B61CA), in: RoundedRectangle(cornerRadius: 14))
                            .disabled(isSaving)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 22)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Site Inspection")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x0F172A))
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 4)
            Text("Information about Land Procurement")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var viewOnlyBanner: some View {
        Text("Approved by VP - View only")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(hex: 0x0B61CA))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(hex: 0xDDEBFF), in: RoundedRectangle(cornerRadius: 10))
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(SiteInspectionTab.allCases.enumerated()), id: \.element.id) { index, tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            Circle()
                                .fill(selectedTab == tab ? Color(hex: 0x0B61CA) : Color(hex: 0xF4F6FA))
                                .frame(width: 30, height: 30)
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(selectedTab == tab ? .white : Color(hex: 0x7A7D86))
                        }
                        Text(tab.title)
                            .font(.system(size: 9, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Color(hex: 0x0B61CA) : Color(hex: 0x667085))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Rectangle()
                            .fill(selectedTab == tab ? Color(hex: 0x0B61CA) : Color.clear)
                            .frame(width: 26, height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                }
                .buttonStyle(.plain)

                if index < SiteInspectionTab.allCases.count - 1 {
                    Rectangle()
                        .fill(Color(hex: 0xE8ECF3))
                        .frame(width: 1, height: 34)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Area", subtitle: "Nearby amenities and distance")
            areaEditor(title: "Schools", entries: $schools)
            areaEditor(title: "Colleges", entries: $colleges)
            areaEditor(title: "Hospitals", entries: $hospitals)
            areaEditor(title: "Mall", entries: $malls)
            areaEditor(title: "Market", entries: $markets)
        }
    }

    private var marketSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Conclusion", subtitle: "Recommendation/conclusion")
            fieldCard("Recommendation / Conclusion", text: $conclusion, placeholder: "Enter recommendation", icon: "target", required: true, axis: .vertical, minHeight: 132)
        }
    }

    private var competitorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .font(.system(size: 16, weight: .bold))
            if entries.wrappedValue.isEmpty {
                Text("No \(title.lowercased()) added.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 14))
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: 0x111827))
            Text(subtitle)
                .font(.system(size: 13))
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
        minHeight: CGFloat = 52,
        compact: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(label)
                if required {
                    Text("*").foregroundStyle(.red)
                }
            }
            .font(.system(size: compact ? 11 : 13, weight: .semibold))
            .foregroundStyle(Color(hex: 0x374151))

            HStack(alignment: axis == .vertical ? .top : .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 24)
                if isViewOnly {
                    Text(text.wrappedValue.landNilIfBlank ?? placeholder)
                        .font(.system(size: compact ? 13 : 15, weight: text.wrappedValue.landNilIfBlank == nil ? .regular : .semibold))
                        .foregroundStyle(text.wrappedValue.landNilIfBlank == nil ? .secondary.opacity(0.65) : Color(hex: 0x111827))
                        .lineLimit(axis == .vertical ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(placeholder, text: text, axis: axis)
                        .font(.system(size: compact ? 13 : 15, weight: .regular))
                        .foregroundStyle(Color(hex: 0x111827))
                        .textInputAutocapitalization(.sentences)
                        .lineLimit(axis == .vertical ? 6 : 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight, alignment: .center)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func menuCard(_ label: String, selection: Binding<String>, options: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x374151))
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 24)
                if isViewOnly {
                    Text(selection.wrappedValue.landNilIfBlank?.capitalized ?? "-")
                        .font(.system(size: 15, weight: .semibold))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func optionCard(title: String, options: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
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
                    .font(.system(size: 14))
                    .padding(.vertical, 8)
                    if option != options.last {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 13)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
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
    @State private var showingDateFilter = false

    private var filteredQueries: [LandQueryLog] {
        queries.filter { query in
            let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = search.isEmpty
                || query.displayTitle.localizedCaseInsensitiveContains(search)
                || query.queryDetail.localizedCaseInsensitiveContains(search)
            let matchesStatus: Bool = {
                switch selectedStatus {
                case .all: return true
                case .pending: return !query.isCompletedQuery
                case .completed: return query.isCompletedQuery
                }
            }()
            let matchesDate = !useDateFilter
                || query.rawDate == AppModuleFormatters.ymd.string(from: filterDate)
            return matchesSearch && matchesStatus && matchesDate
        }
    }

    var body: some View {
        ZStack {
            Color(hex: 0xF1F3F8)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    queriesHeader
                    queriesContentPanel
                }
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .sheet(isPresented: $showingDateFilter) {
            LandInspectionDateFilterSheet(date: $filterDate) {
                useDateFilter = true
                showingDateFilter = false
            }
            .appLibraryNativeSheet([.height(470)])
            .presentationBackground(Color.white)
        }
        .sheet(item: $selectedQuery) { query in
            LandQueryDetailSheet(query: query) {
                await load()
                selectedQuery = nil
            }
            .appLibraryNativeSheet([.height(520), .large])
            .presentationBackground(Color.white)
        }
    }

    private var queriesHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x02499D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Queries")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Manage and track all Queries")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xD9D6FE))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image("LandQueriesHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 104)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 48)
        }
        .frame(height: 226)
    }

    private var queriesContentPanel: some View {
        VStack(spacing: 0) {
            queryControls
                .padding(.top, 16)

            if isLoading && queries.isEmpty {
                AppModuleLoadingRows()
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else if filteredQueries.isEmpty {
                queriesEmptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredQueries) { query in
                        Button {
                            selectedQuery = query
                        } label: {
                            LandQueryRow(query: query)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .padding(.bottom, 32)
        .background(Color(hex: 0xF1F3F8))
        .clipShape(.rect(topLeadingRadius: 24, topTrailingRadius: 24))
        .padding(.top, -28)
    }

    private var queryControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                NativeInlineSearchBar(text: $searchText, placeholder: "Search Queries")
                    .frame(height: 50)

                Button {
                    showingDateFilter = true
                } label: {
                    if useDateFilter {
                        VStack(spacing: 0) {
                            Text(AppModuleFormatters.dayNumber.string(from: filterDate))
                                .font(.system(size: 14, weight: .bold))
                            Text(AppModuleFormatters.shortMonth.string(from: filterDate))
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                    } else {
                        Image(systemName: "calendar")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                    }
                }
                .frame(width: 50, height: 50)
                .background(useDateFilter ? Color(hex: 0x0B61CA) : .white, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            }

            if useDateFilter {
                HStack(spacing: 6) {
                    Text("Date · \(AppModuleFormatters.day.string(from: filterDate))")
                        .font(.system(size: 12, weight: .semibold))
                    Button {
                        useDateFilter = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 7)
                .background(Color(hex: 0x0B61CA), in: Capsule())
            }

            HStack(spacing: 0) {
                ForEach(LandQueryStatusFilter.allCases) { filter in
                    Button {
                        selectedStatus = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedStatus == filter ? .white : Color(hex: 0x101828))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(
                                selectedStatus == filter ? Color(hex: 0x0B61CA) : .clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .frame(height: 36)
            .background(Color.white, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(hex: 0xD7E7FF), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }

    private var queriesEmptyState: some View {
        VStack(spacing: 6) {
            Text(queriesEmptyTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
            Text(queriesEmptySubtitle)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6B7280))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 52)
    }

    private var queriesEmptyTitle: String {
        if !hasLoaded { return "Loading queries..." }
        return queries.isEmpty ? "No queries yet" : "No matches"
    }

    private var queriesEmptySubtitle: String {
        if !hasLoaded { return "Hang on while we fetch your queries." }
        if queries.isEmpty {
            return errorMessage ?? "Document verification queries for your properties will appear here."
        }
        return "Try clearing the date filter, the status chip, or the search box."
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
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 44, height: 44)
                .background(Color(hex: 0xEAF3FF), in: Circle())
                .offset(y: -4)

            VStack(alignment: .leading, spacing: 6) {
                Text(query.queryStatusText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(query.statusForeground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(query.statusBackground, in: Capsule())

                Text(query.displayTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Label {
                    Text(query.queryDetail)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "message")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x9AA3B2))

                Label(query.formattedQueryDate, systemImage: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x9AA3B2))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 44, height: 44)
                .background(Color(hex: 0xEAF3FF), in: Circle())
                .padding(.top, 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 1)
        .padding(.vertical, 8)
    }
}

private extension LandQueryLog {
    var isCompletedQuery: Bool {
        resolved == true || displayStatus.localizedCaseInsensitiveContains("completed")
    }

    var queryStatusText: String {
        isCompletedQuery ? "Completed" : "PENDING"
    }

    var queryDetail: String {
        referenceNo?.landNilIfBlank
            ?? description?.landNilIfBlank
            ?? remarks?.landNilIfBlank
            ?? latestUpdate?.landNilIfBlank
            ?? "—"
    }

    var formattedQueryDate: String {
        guard let rawDate else { return "—" }
        if let date = AppModuleFormatters.ymd.date(from: rawDate) {
            return AppModuleFormatters.day.string(from: date)
        }
        return rawDate
    }

    var statusForeground: Color {
        isCompletedQuery ? Color(hex: 0x065F46) : Color(hex: 0x0B61CA)
    }

    var statusBackground: Color {
        isCompletedQuery ? Color(hex: 0xDFF7E8) : Color(hex: 0xEAF3FF)
    }
}

private struct LandQueryDetailSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let query: LandQueryLog
    let onChanged: () async -> Void

    @State private var remarks = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var requestedDocuments: [String] {
        let parts = query.displayTitle
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [query.displayTitle.landNilIfBlank ?? "Document"] : parts
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Query Details")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                        Text("Documents Needed (Additional)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: 0x101828))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Text("The following documents are requested")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(hex: 0x6B7280))

                    VStack(spacing: 10) {
                        ForEach(requestedDocuments, id: \.self) { document in
                            RequestedDocumentRow(name: document, isCompleted: query.resolved == true)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }

            if query.resolved != true {
                Button {
                    Task { await markCompleted() }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isSubmitting ? "Updating..." : "Completed")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(hex: 0x0B61CA), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isSubmitting)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .background(Color.white)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear {
            remarks = query.remarks?.landNilIfBlank ?? query.latestUpdate?.landNilIfBlank ?? ""
        }
        .alert("Query Update", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func markCompleted() async {
        guard !isSubmitting else { return }
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            return
        }
        guard let propertyId = query.propertyId?.landNilIfBlank,
              let queryIndex = query.queryIndex else {
            errorMessage = "Missing query reference. Please refresh and try again."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await LandConvexAPIService.updateQuery(
                token: token,
                request: LandQueryUpdateRequest(
                    propertyId: propertyId,
                    queryIndex: queryIndex,
                    remarks: remarks.landNilIfBlank,
                    resolved: true
                )
            )
            await onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RequestedDocumentRow: View {
    let name: String
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "doc.text")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isCompleted ? Color(hex: 0x16A34A) : Color(hex: 0x0B61CA))
                .frame(width: 36, height: 36)
                .background(Color(hex: 0xEAF3FF), in: Circle())

            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(isCompleted ? "Done" : "Required")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isCompleted ? Color(hex: 0x16A34A) : Color(hex: 0x0B61CA))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background((isCompleted ? Color(hex: 0xD1FADF) : Color(hex: 0xEAF3FF)), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
    }
}

private struct LandQueryInfoCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x9AA3B2))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct NativeInlineSearchBar: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = placeholder
        searchBar.delegate = context.coordinator
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.backgroundImage = UIImage()
        searchBar.searchTextField.backgroundColor = UIColor.secondarySystemGroupedBackground
        searchBar.searchTextField.layer.cornerRadius = 10
        searchBar.searchTextField.clipsToBounds = true
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            text = ""
            searchBar.text = ""
            searchBar.resignFirstResponder()
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
