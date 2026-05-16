import SwiftUI

// MARK: - CompleteCpVisitSheet

struct CompleteCpVisitSheet: View {
    let cpVisitId: String
    let initialOutcome: String?
    let onCompleted: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedOutcome: CpVisitOutcome?
    @State private var selectedPostponeReasons: Set<String> = []
    @State private var notes = ""
    @State private var budgetConcern = ""
    @State private var timingNotes = ""
    @State private var projectDetails = ""
    @State private var otherPostponeNotes = ""

    @State private var projects: [MarketingProject] = []
    @State private var salesStaff: [ConvexStaffListItem] = []
    @State private var selectedProject: MarketingProject?
    @State private var selectedIncharge: ConvexStaffListItem?
    @State private var selectedHod: ConvexStaffListItem?
    @State private var selectedAvp: ConvexStaffListItem?
    @State private var selectedGm: ConvexStaffListItem?
    @State private var selectedSeniorManager: ConvexStaffListItem?
    @State private var siteVisitDate = Date()
    @State private var siteVisitTime = Date()
    @State private var travelMode: TravelMode = .cab
    @State private var pickupAddress = ""
    @State private var visitorCount = ""
    @State private var visitors: [CpVisitorDraft] = []
    @State private var foodPreferences = ""

    @State private var isLoadingProjects = false
    @State private var isLoadingStaff = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let postponeReasons = ["Budget", "Timing", "Project", "Other"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Capsule()
                        .fill(Color(hex: 0xE4E7EC))
                        .frame(width: 40, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 2)

                    Text("Outcome Information")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text("Information about Client Details")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0x667085))

                    outcomeChips
                        .padding(.top, 2)

                    if selectedOutcome == .siteVisit {
                        siteVisitSection
                    }

                    if selectedOutcome == .postponed {
                        postponeSection
                    }

                    if selectedOutcome == .notInterested {
                        labeledEditor("Why is the client not interested?", text: $notes, minLines: 3)
                    }

                    if selectedOutcome == .wait {
                        labeledEditor("Add notes", text: $notes, minLines: 3)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        } else {
                            Text("Submit")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color(hex: 0x0B61CA), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 6)
                    .disabled(isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .task {
                selectedOutcome = CpVisitOutcome(rawValue: initialOutcome ?? "")
                await loadInitialData()
            }
        }
    }

    private var outcomeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CpVisitOutcome.allCases) { outcome in
                    ChipButton(
                        title: outcome.title,
                        isSelected: selectedOutcome == outcome
                    ) {
                        selectedOutcome = outcome
                        if outcome != .postponed {
                            selectedPostponeReasons = []
                        }
                    }
                }
            }
        }
    }

    private var siteVisitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Site visit details")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            sectionLabel("Schedule")
            if isLoadingProjects {
                FieldShell {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading projects…")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            } else {
                PickerField(
                    title: selectedProject?.name ?? "Select project",
                    options: projects,
                    label: { $0.name ?? "Unnamed project" },
                    selection: $selectedProject
                )
            }

            HStack(spacing: 10) {
                DatePicker("", selection: $siteVisitDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 46)
                    .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
                DatePicker("", selection: $siteVisitTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 46)
                    .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
            }

            sectionLabel("Pickup")
            Menu {
                ForEach(TravelMode.allCases) { mode in
                    Button(mode.title) { travelMode = mode }
                }
            } label: {
                fieldText("Client travel: \(travelMode.title)")
            }
            .buttonStyle(.plain)
            fieldEditor("Pickup address if different", text: $pickupAddress, minLines: 2)

            FieldShell {
                Text("BDO: keep original")
                    .font(.system(size: 13, weight: .medium))
            }

            sectionLabel("Sales ownership")
            if isLoadingStaff {
                FieldShell {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading staff…").font(.system(size: 13, weight: .medium))
                    }
                }
            } else {
                staffPicker("Select SiteIncharge", selection: $selectedIncharge)
                staffPicker("Select HOD", selection: $selectedHod)
                staffPicker("Select AVP", selection: $selectedAvp)
                staffPicker("Select GM", selection: $selectedGm)
                staffPicker("Select Senior Manager", selection: $selectedSeniorManager)
            }

            sectionLabel("Visitors")
            TextField("No. of visitors", text: $visitorCount)
                .keyboardType(.numberPad)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: visitorCount) { _, value in
                    syncVisitorRows(count: Int(value.filter(\.isNumber)) ?? 0)
                }

            ForEach($visitors) { $visitor in
                VisitorDraftRow(visitor: $visitor)
            }

            fieldEditor("Food preferences", text: $foodPreferences)
        }
        .padding(.top, 4)
    }

    private var postponeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Postpone Reasons")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(postponeReasons, id: \.self) { reason in
                        ChipButton(title: reason, isSelected: selectedPostponeReasons.contains(reason)) {
                            if selectedPostponeReasons.contains(reason) {
                                selectedPostponeReasons.remove(reason)
                            } else {
                                selectedPostponeReasons.insert(reason)
                            }
                        }
                    }
                }
            }
            labeledEditor("Please specify the budget concern", text: $budgetConcern, minLines: 2)
            labeledEditor("What's the timing?", text: $timingNotes, minLines: 1)
            labeledEditor("Tell the Project Details", text: $projectDetails, minLines: 2)
            labeledEditor("Tell Other Details", text: $otherPostponeNotes, minLines: 2)
        }
        .padding(.top, 4)
    }

    private func staffPicker(_ title: String, selection: Binding<ConvexStaffListItem?>) -> some View {
        PickerField(
            title: selection.wrappedValue.map { "\(title.replacingOccurrences(of: "Select ", with: "")): \($0.displayName)" } ?? title,
            options: salesStaff,
            label: { staff in
                [staff.displayName, staff.designation, staff.department]
                    .compactMap { $0?.nilIfBlank }
                    .joined(separator: " · ")
            },
            selection: selection
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(hex: 0x667085))
            .padding(.top, 4)
    }

    private func labeledEditor(_ title: String, text: Binding<String>, minLines: Int = 2) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))
            fieldEditor("Type here...", text: text, minLines: minLines)
        }
        .padding(.top, 4)
    }

    private func fieldEditor(_ placeholder: String, text: Binding<String>, minLines: Int = 1) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(minLines...max(minLines, 4))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
    }

    private func fieldText(_ text: String) -> some View {
        FieldShell {
            HStack {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
            }
        }
    }

    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadProjects() }
            group.addTask { await loadSalesStaff() }
        }
    }

    private func loadProjects() async {
        guard projects.isEmpty, let token = authStore.currentSession?.token else { return }
        isLoadingProjects = true
        defer { isLoadingProjects = false }
        projects = (try? await MarketingConvexAPIService.getMarketingProjects(token: token)) ?? []
    }

    private func loadSalesStaff() async {
        guard salesStaff.isEmpty, let token = authStore.currentSession?.token else { return }
        isLoadingStaff = true
        defer { isLoadingStaff = false }
        let staff = (try? await HRConvexAPIService.listAllStaff(token: token)) ?? []
        salesStaff = staff.filter {
            let dept = ($0.department ?? "").lowercased()
            return dept.contains("sales") || dept.contains("telesales")
        }
    }

    private func syncVisitorRows(count rawCount: Int) {
        let count = min(max(rawCount, 0), 12)
        if visitors.count < count {
            visitors.append(contentsOf: (visitors.count..<count).map { _ in CpVisitorDraft() })
        } else if visitors.count > count {
            visitors.removeLast(visitors.count - count)
        }
    }

    private func submit() async {
        errorMessage = nil
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in"
            return
        }
        guard let selectedOutcome else {
            errorMessage = "Please pick an outcome"
            return
        }
        if selectedOutcome == .postponed && selectedPostponeReasons.isEmpty {
            errorMessage = "Pick at least one postpone reason"
            return
        }
        if selectedOutcome == .siteVisit && selectedProject == nil {
            errorMessage = "Please select a project"
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await MarketingConvexAPIService.markClientMet(
                token: token,
                request: MarkClientMetRequest(id: cpVisitId, clientMet: true)
            )

            if selectedOutcome == .siteVisit {
                guard let selectedProject else { return }
                _ = try await MarketingConvexAPIService.convertCpVisitToSiteVisit(
                    token: token,
                    request: ConvertCpVisitToSiteVisitRequest(
                        id: cpVisitId,
                        projectId: selectedProject.id,
                        scheduledDate: dateString(siteVisitDate),
                        scheduledTime: timeString(siteVisitTime),
                        inchargeStaffId: selectedIncharge?.id,
                        hodStaffId: selectedHod?.id,
                        avpStaffId: selectedAvp?.id,
                        gmStaffId: selectedGm?.id,
                        seniorManagerStaffId: selectedSeniorManager?.id,
                        expectedAttendeeCount: Int(visitorCount.trimmingCharacters(in: .whitespacesAndNewlines)),
                        attendees: visitorPayload.nilIfEmpty,
                        pickupAddress: pickupAddress.nilIfBlank,
                        travelMode: travelMode.rawValue,
                        foodPreferences: foodPreferences.nilIfBlank,
                        notes: "Created from iOS CP visit"
                    )
                )
            } else {
                try await MarketingConvexAPIService.setCpVisitOutcome(
                    token: token,
                    request: SetCpVisitOutcomeRequest(
                        id: cpVisitId,
                        outcome: selectedOutcome.rawValue,
                        postponeReasons: selectedOutcome == .postponed ? Array(selectedPostponeReasons) : nil,
                        notes: buildOutcomeNotes(for: selectedOutcome)
                    )
                )
            }

            onCompleted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildOutcomeNotes(for outcome: CpVisitOutcome) -> String? {
        switch outcome {
        case .postponed:
            return [
                budgetConcern.nilIfBlank.map { "Budget concern: \($0)" },
                timingNotes.nilIfBlank.map { "Timing: \($0)" },
                projectDetails.nilIfBlank.map { "Project details: \($0)" },
                otherPostponeNotes.nilIfBlank.map { "Other: \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
            .nilIfBlank
        case .notInterested, .wait:
            return notes.nilIfBlank
        case .booking, .siteVisit:
            return nil
        }
    }

    private var visitorPayload: [SiteVisitAttendeeRequest] {
        visitors.map {
            SiteVisitAttendeeRequest(
                name: $0.name.nilIfBlank,
                relation: $0.relation.nilIfBlank,
                age: $0.age.nilIfBlank,
                isVeg: $0.isVeg
            )
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private enum CpVisitOutcome: String, CaseIterable, Identifiable {
    case booking = "converted_to_booking"
    case siteVisit = "converted_to_site_visit"
    case postponed
    case notInterested = "not_interested"
    case wait = "interested"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .booking: return "Booking"
        case .siteVisit: return "Site Visit"
        case .postponed: return "Postpone"
        case .notInterested: return "Not Interested"
        case .wait: return "Wait"
        }
    }

    var icon: String {
        switch self {
        case .booking: return "checkmark.seal.fill"
        case .siteVisit: return "building.2.fill"
        case .postponed: return "calendar.badge.clock"
        case .notInterested: return "xmark.circle.fill"
        case .wait: return "clock.badge"
        }
    }
}

private enum TravelMode: String, CaseIterable, Identifiable {
    case cab
    case ownVehicle = "own_vehicle"

    var id: String { rawValue }
    var title: String { self == .cab ? "Cab required" : "Own vehicle" }
}

private struct CpVisitorDraft: Identifiable, Hashable {
    let id = UUID()
    var name = ""
    var relation = ""
    var age = ""
    var isVeg = true
}

private struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : Color(hex: 0x1D2939))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0xF5F6FA), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct FieldShell<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PickerField<Item: Identifiable & Hashable>: View {
    let title: String
    let options: [Item]
    let label: (Item) -> String
    @Binding var selection: Item?

    var body: some View {
        Menu {
            Button("Clear") { selection = nil }
            ForEach(options) { item in
                Button(label(item)) { selection = item }
            }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct VisitorDraftRow: View {
    @Binding var visitor: CpVisitorDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Visitor")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x667085))
            TextField("Visitor name", text: $visitor.name)
                .cpFieldStyle()
            TextField("Relation", text: $visitor.relation)
                .cpFieldStyle()
            TextField("Age", text: $visitor.age)
                .keyboardType(.numberPad)
                .cpFieldStyle()
            Button {
                visitor.isVeg.toggle()
            } label: {
                Text(visitor.isVeg ? "Food: Veg" : "Food: Non-veg")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x1D2939))
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Color(hex: 0xF5F6FA), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(hex: 0xFAFBFC), in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array {
    var nilIfEmpty: [Element]? {
        isEmpty ? nil : self
    }
}

private extension View {
    func cpFieldStyle() -> some View {
        self
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
    }
}
