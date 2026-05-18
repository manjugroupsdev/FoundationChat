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
    @State private var bookingSub: BookingSub = .client
    @State private var booking = BookingDraft()

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

                    if selectedOutcome == .booking {
                        bookingSection
                    }

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
                        if outcome == .booking {
                            bookingSub = .client
                        }
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

    private var bookingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Booking details", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                Text("Draft")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0369A1))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(hex: 0xE0F2FE), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BookingSub.allCases) { sub in
                        ChipButton(title: sub.title, isSelected: bookingSub == sub) {
                            withAnimation(.easeOut(duration: 0.16)) {
                                bookingSub = sub
                            }
                        }
                    }
                }
            }

            bookingSubBody

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                Text("Saved as visit outcome notes until the dedicated booking-create flow is connected to this CP visit path.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x667085))
            }
            .padding(12)
            .background(Color(hex: 0xF0F6FF), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var bookingSubBody: some View {
        switch bookingSub {
        case .client:
            bookingClientFields
        case .professional:
            bookingProfessionalFields
        case .office:
            bookingOfficeFields
        case .booking:
            bookingDetailsFields
        case .charges:
            bookingChargesFields
        case .payment:
            bookingPaymentFields
        case .staff:
            bookingStaffFields
        }
    }

    private var bookingClientFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Booking · Client Details")
            BookingTextField("Phone", text: $booking.phone, keyboard: .phonePad)
            BookingTextField("Title", text: $booking.title)
            BookingTextField("Name", text: $booking.name)
            BookingTextField("Father/Spouse", text: $booking.fatherOrSpouse)
            BookingTextField("DOB", text: $booking.dob)
            BookingTextField("Anniversary", text: $booking.anniversary)
            BookingTextField("Alt number", text: $booking.altNumber, keyboard: .phonePad)
            BookingTextField("WhatsApp", text: $booking.whatsapp, keyboard: .phonePad)
            BookingTextField("Email", text: $booking.email, keyboard: .emailAddress)
            BookingTextField("Nationality", text: $booking.nationality)
            BookingTextField("Home Address", text: $booking.homeAddress, axis: .vertical)
            BookingTextField("Pincode", text: $booking.pincode, keyboard: .numberPad)
            BookingTextField("State", text: $booking.state)
            BookingTextField("District", text: $booking.district)
            BookingTextField("Location", text: $booking.location)
        }
    }

    private var bookingProfessionalFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Booking · Professional Details")
            BookingTextField("Profession", text: $booking.profession)
            BookingTextField("Designation", text: $booking.designation)
            BookingTextField("Income Per Annum", text: $booking.incomePerAnnum, keyboard: .decimalPad)
        }
    }

    private var bookingOfficeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Booking · Office Details")
            BookingTextField("Office Name", text: $booking.officeName)
            BookingTextField("Office Email", text: $booking.officeEmail, keyboard: .emailAddress)
            BookingTextField("Office Mobile", text: $booking.officeMobile, keyboard: .phonePad)
            BookingTextField("Office Phone", text: $booking.officePhone, keyboard: .phonePad)
            BookingTextField("Office Address", text: $booking.officeAddress, axis: .vertical)
        }
    }

    private var bookingDetailsFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Booking · Booking Details")
            BookingTextField("Booking Type", text: $booking.bookingType)
            BookingTextField("Source Type", text: $booking.sourceType)
            BookingTextField("CEF No", text: $booking.cefNo)
            BookingTextField("Booking Date", text: $booking.bookingDate)
            BookingTextField("Project", text: $booking.project)
            BookingTextField("Plot", text: $booking.plot)
            BookingTextField("Property Type", text: $booking.propertyType)
            BookingTextField("Booking Mode", text: $booking.bookingMode)
            Toggle("Is Against Client Visit", isOn: $booking.isAgainstClientVisit)
                .font(.system(size: 13, weight: .medium))
            Toggle("Duplicate Bookings", isOn: $booking.duplicateBookings)
                .font(.system(size: 13, weight: .medium))
        }
    }

    private var bookingChargesFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Booking · Charges Details")
            BookingTextField("Booking Cost", text: $booking.bookingCost, keyboard: .decimalPad)
            BookingTextField("Guideline Value", text: $booking.guidelineValue, keyboard: .decimalPad)
            BookingTextField("Special Consideration", text: $booking.specialConsideration, axis: .vertical)
            BookingTextField("Discount Approved By", text: $booking.discountApprovedBy)
            BookingTextField("SC Reason", text: $booking.scReason, axis: .vertical)
            BookingTextField("SC Validity (days)", text: $booking.scValidity, keyboard: .numberPad)
            BookingTextField("Promotional Offers", text: $booking.promotionalOffers, axis: .vertical)
            BookingTextField("Promotional Offers T&C", text: $booking.promotionalOffersTnc)
            BookingTextField("Promotional Offers Value", text: $booking.promotionalOffersValue, keyboard: .decimalPad)
            BookingTextField("Offer Validity Period (days)", text: $booking.offerValidityPeriod, keyboard: .numberPad)
        }
    }

    private var bookingPaymentFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Booking · Payment Details")
            BookingTextField("Registration Charges", text: $booking.registrationCharges, keyboard: .decimalPad)
            BookingTextField("GST Amount", text: $booking.gstAmount, keyboard: .decimalPad)
            Toggle("GST If Applicable", isOn: $booking.gstApplicable)
                .font(.system(size: 13, weight: .medium))
            BookingTextField("Document Charges", text: $booking.documentCharges, keyboard: .decimalPad)
            BookingTextField("Other Charges", text: $booking.otherCharges, keyboard: .decimalPad)
            Toggle("Other Charges If Applicable", isOn: $booking.otherChargesApplicable)
                .font(.system(size: 13, weight: .medium))
            BookingTextField("Advance Amount", text: $booking.advanceAmount, keyboard: .decimalPad)
            BookingTextField("Payment Mode", text: $booking.paymentMode)
            Toggle("Flexi Payment", isOn: $booking.flexiPayment)
                .font(.system(size: 13, weight: .medium))
            BookingTextField("Allotment Due Amount", text: $booking.allotmentDueAmount, keyboard: .decimalPad)
            BookingTextField("Allotment Due Date", text: $booking.allotmentDueDate)
            BookingTextField("2nd Payment Mode", text: $booking.secondPaymentMode)
            BookingTextField("2nd Payment Date", text: $booking.secondPaymentDate)
            BookingTextField("3rd Payment Mode", text: $booking.thirdPaymentMode)
            BookingTextField("3rd Payment Date", text: $booking.thirdPaymentDate)
            BookingTextField("4th Payment Mode", text: $booking.fourthPaymentMode)
            BookingTextField("4th Payment Date", text: $booking.fourthPaymentDate)
            BookingTextField("Preferred Registration Date", text: $booking.preferredRegistrationDate)
        }
    }

    private var bookingStaffFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Booking · Staff Details")
            BookingTextField("AVP", text: $booking.avp)
            BookingTextField("General Manager", text: $booking.generalManager)
            BookingTextField("Senior Manager", text: $booking.seniorManager)
            BookingTextField("BDO", text: $booking.bdo)
            BookingTextField("Telecaller", text: $booking.telecaller)
            BookingTextField("Aadhar", text: $booking.aadhar, keyboard: .numberPad)
            BookingTextField("Pancard", text: $booking.pancard)
            BookingTextField("Reference Name 1", text: $booking.referenceName1)
            BookingTextField("Reference Mobile 1", text: $booking.referenceMobile1, keyboard: .phonePad)
            BookingTextField("Reference Profession 1", text: $booking.referenceProfession1)
            BookingTextField("Reference Name 2", text: $booking.referenceName2)
            BookingTextField("Reference Mobile 2", text: $booking.referenceMobile2, keyboard: .phonePad)
            BookingTextField("Reference Profession 2", text: $booking.referenceProfession2)
            BookingTextField("Document to be prepared in", text: $booking.documentLanguage)
            PickerField(
                title: "Save as: \(booking.saveAs.title)",
                options: BookingSaveAs.allCases,
                label: { $0.title },
                selection: Binding(
                    get: { booking.saveAs },
                    set: { booking.saveAs = $0 ?? .draft }
                )
            )
        }
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
        case .booking:
            return booking.serializedNotes
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
        case .siteVisit:
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

private enum BookingSub: String, CaseIterable, Identifiable {
    case client
    case professional
    case office
    case booking
    case charges
    case payment
    case staff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .client: return "Client"
        case .professional: return "Professional"
        case .office: return "Office"
        case .booking: return "Booking"
        case .charges: return "Charges"
        case .payment: return "Payment"
        case .staff: return "Staff"
        }
    }
}

private enum BookingSaveAs: String, CaseIterable, Identifiable, Hashable {
    case draft
    case confirmed

    var id: String { rawValue }
    var title: String { self == .draft ? "Draft" : "Confirmed" }
}

private struct BookingDraft {
    var phone = ""
    var title = ""
    var name = ""
    var fatherOrSpouse = ""
    var dob = ""
    var anniversary = ""
    var altNumber = ""
    var whatsapp = ""
    var email = ""
    var nationality = ""
    var homeAddress = ""
    var pincode = ""
    var state = ""
    var district = ""
    var location = ""

    var profession = ""
    var designation = ""
    var incomePerAnnum = ""

    var officeName = ""
    var officeEmail = ""
    var officeMobile = ""
    var officePhone = ""
    var officeAddress = ""

    var bookingType = ""
    var sourceType = ""
    var cefNo = ""
    var bookingDate = ""
    var project = ""
    var plot = ""
    var propertyType = ""
    var bookingMode = ""
    var isAgainstClientVisit = true
    var duplicateBookings = true

    var bookingCost = ""
    var guidelineValue = ""
    var specialConsideration = ""
    var discountApprovedBy = ""
    var scReason = ""
    var scValidity = ""
    var promotionalOffers = ""
    var promotionalOffersTnc = ""
    var promotionalOffersValue = ""
    var offerValidityPeriod = ""

    var registrationCharges = ""
    var gstAmount = ""
    var gstApplicable = true
    var documentCharges = ""
    var otherCharges = ""
    var otherChargesApplicable = true
    var advanceAmount = ""
    var paymentMode = ""
    var flexiPayment = true
    var allotmentDueAmount = ""
    var allotmentDueDate = ""
    var secondPaymentMode = ""
    var secondPaymentDate = ""
    var thirdPaymentMode = ""
    var thirdPaymentDate = ""
    var fourthPaymentMode = ""
    var fourthPaymentDate = ""
    var preferredRegistrationDate = ""

    var avp = ""
    var generalManager = ""
    var seniorManager = ""
    var bdo = ""
    var telecaller = ""
    var aadhar = ""
    var pancard = ""
    var referenceName1 = ""
    var referenceMobile1 = ""
    var referenceProfession1 = ""
    var referenceName2 = ""
    var referenceMobile2 = ""
    var referenceProfession2 = ""
    var documentLanguage = ""
    var saveAs: BookingSaveAs = .draft

    var serializedNotes: String? {
        var sections: [String] = []

        func section(_ title: String, _ rows: [(String, String?)]) {
            let body = rows.compactMap { label, value -> String? in
                guard let value = value?.nilIfBlank else { return nil }
                return "\(label): \(value)"
            }
            guard !body.isEmpty else { return }
            sections.append((["[\(title)]"] + body).joined(separator: "\n"))
        }

        section("Booking · Client Details", [
            ("Phone", phone), ("Title", title), ("Name", name),
            ("Father/Spouse", fatherOrSpouse), ("DOB", dob),
            ("Anniversary", anniversary), ("Alt number", altNumber),
            ("WhatsApp", whatsapp), ("Email", email), ("Nationality", nationality),
            ("Home Address", homeAddress), ("Pincode", pincode),
            ("State", state), ("District", district), ("Location", location)
        ])
        section("Booking · Professional Details", [
            ("Profession", profession), ("Designation", designation),
            ("Income Per Annum", incomePerAnnum)
        ])
        section("Booking · Office Details", [
            ("Office Name", officeName), ("Office Email", officeEmail),
            ("Office Mobile", officeMobile), ("Office Phone", officePhone),
            ("Office Address", officeAddress)
        ])
        section("Booking · Booking Details", [
            ("Booking Type", bookingType), ("Source Type", sourceType),
            ("CEF No", cefNo), ("Booking Date", bookingDate),
            ("Project", project), ("Plot", plot), ("Property Type", propertyType),
            ("Booking Mode", bookingMode),
            ("Is Against Client Visit", isAgainstClientVisit ? "Yes" : "No (Online Sales)"),
            ("Duplicate Bookings", duplicateBookings ? "Yes" : "No")
        ])
        section("Booking · Charges Details", [
            ("Booking Cost", bookingCost), ("Guideline Value", guidelineValue),
            ("Special Consideration", specialConsideration),
            ("Discount Approved By", discountApprovedBy), ("SC Reason", scReason),
            ("SC Validity (days)", scValidity), ("Promotional Offers", promotionalOffers),
            ("Promotional Offers T&C", promotionalOffersTnc),
            ("Promotional Offers Value", promotionalOffersValue),
            ("Offer Validity Period (days)", offerValidityPeriod)
        ])
        section("Booking · Payment Details", [
            ("Registration Charges", registrationCharges), ("GST Amount", gstAmount),
            ("GST If Applicable", gstApplicable ? "Yes" : "No"),
            ("Document Charges", documentCharges), ("Other Charges", otherCharges),
            ("Other Charges If Applicable", otherChargesApplicable ? "Yes" : "No"),
            ("Advance Amount", advanceAmount), ("Payment Mode", paymentMode),
            ("Flexi Payment", flexiPayment ? "Yes" : "No"),
            ("Allotment Due Amount", allotmentDueAmount),
            ("Allotment Due Date", allotmentDueDate),
            ("2nd Payment Mode", secondPaymentMode), ("2nd Payment Date", secondPaymentDate),
            ("3rd Payment Mode", thirdPaymentMode), ("3rd Payment Date", thirdPaymentDate),
            ("4th Payment Mode", fourthPaymentMode), ("4th Payment Date", fourthPaymentDate),
            ("Preferred Registration Date", preferredRegistrationDate)
        ])
        section("Booking · Staff Details", [
            ("AVP", avp), ("General Manager", generalManager),
            ("Senior Manager", seniorManager), ("BDO", bdo), ("Telecaller", telecaller),
            ("Aadhar", aadhar), ("Pancard", pancard),
            ("Reference Name 1", referenceName1), ("Reference Mobile 1", referenceMobile1),
            ("Reference Profession 1", referenceProfession1),
            ("Reference Name 2", referenceName2), ("Reference Mobile 2", referenceMobile2),
            ("Reference Profession 2", referenceProfession2),
            ("Document to be prepared in", documentLanguage), ("Save as", saveAs.title)
        ])

        return sections.joined(separator: "\n\n").nilIfBlank
    }
}

private struct CpVisitorDraft: Identifiable, Hashable {
    let id = UUID()
    var name = ""
    var relation = ""
    var age = ""
    var isVeg = true
}

private struct BookingTextField: View {
    let title: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let axis: Axis

    init(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        axis: Axis = .horizontal
    ) {
        self.title = title
        self._text = text
        self.keyboard = keyboard
        self.axis = axis
    }

    var body: some View {
        TextField(title, text: $text, axis: axis)
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .lineLimit(axis == .vertical ? 2...4 : 1...1)
            .cpFieldStyle()
    }
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
