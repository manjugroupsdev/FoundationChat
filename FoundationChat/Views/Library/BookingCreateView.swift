import SwiftUI

struct BookingCreateView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let initialProject: MarketingProject?
    let initialUnit: InventoryUnit?

    @State private var booking = DirectBookingDraft()
    @State private var selectedTab: DirectBookingTab = .client
    @State private var selectedProject: MarketingProject?
    @State private var selectedUnit: InventoryUnit?
    @State private var selectedLead: TelecallerLeadSearchData?
    @State private var leadMatches: [TelecallerLeadSearchData] = []
    @State private var projects: [MarketingProject] = []
    @State private var availableUnits: [InventoryUnit] = []
    @State private var staff: [ConvexStaffListItem] = []
    @State private var showProjectPicker = false
    @State private var showUnitPicker = false
    @State private var showLeadPicker = false
    @State private var isSubmitting = false
    @State private var isSearchingLead = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var draftMessage: String?
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var hasRestoredDraft = false

    init(initialProject: MarketingProject? = nil, initialUnit: InventoryUnit? = nil) {
        self.initialProject = initialProject
        self.initialUnit = initialUnit
        _selectedProject = State(initialValue: initialProject)
        _selectedUnit = State(initialValue: initialUnit)
    }

    private var canCreateBooking: Bool {
        authStore.hasPermission("marketing.bookings.create")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                tabStrip

                if !canCreateBooking {
                    Label("You don't have permission to create bookings.", systemImage: "lock.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                tabBody

                if let draftMessage {
                    Label(draftMessage, systemImage: "doc.text.clock")
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x667085))
                }

                footerAction
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("New Booking")
        .task {
            restoreDraftIfNeeded()
            await loadInitialData()
        }
        .onDisappear {
            draftSaveTask?.cancel()
        }
        .onChange(of: booking) { _, _ in scheduleDraftAutosave() }
        .sheet(isPresented: $showProjectPicker) { projectPickerSheet }
        .sheet(isPresented: $showUnitPicker) { unitPickerSheet }
        .sheet(isPresented: $showLeadPicker) { leadPickerSheet }
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

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Booking")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                Text("Booking form")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x94A3B8))
            }
            Spacer()
            Button("Back") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            Button("Clear") { clearForm() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(Color(hex: 0x2DAE12))
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DirectBookingTab.allCases) { tab in
                    if selectedTab == tab {
                        Button(tab.title) { selectedTab = tab }
                            .font(.system(size: 13, weight: .semibold))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .tint(Color(hex: 0x2DAE12))
                    } else {
                        Button(tab.title) { selectedTab = tab }
                            .font(.system(size: 13, weight: .semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .tint(Color(hex: 0x2DAE12))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footerAction: some View {
        if selectedTab != DirectBookingTab.allCases.last {
            Button {
                goToNextTab()
            } label: {
                Text("Next")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(hex: 0x2DAE12))
            .padding(.top, 4)
        } else {
            HStack(spacing: 12) {
                Button("Clear") {
                    clearForm()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color(hex: 0x2DAE12))

                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(booking.saveAs == .confirmed ? "Create Confirmed" : "Save Draft")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(hex: 0x2DAE12))
                .disabled(!canCreateBooking || isSubmitting)
            }
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch selectedTab {
        case .client:
            clientDetails
        case .professional:
            professionalDetails
        case .office:
            officeDetails
        case .booking:
            bookingDetails
        case .charges:
            chargesDetails
        case .payment:
            paymentDetails
        case .staff:
            staffDetails
        }
    }

    private var clientDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingTextField("Client Phone Number *", text: $booking.phone, placeholder: "Enter Mobile Number", icon: "phone", keyboard: .phonePad)
                .onChange(of: booking.phone) { _, value in
                    Task { await lookupLeadIfNeeded(phone: AppModuleFormatters.normalizePhone(value)) }
                }
            leadLookupStatus
            DirectBookingPicker("Title", value: $booking.title, placeholder: "Select Title", icon: "person", options: ["Mr", "Mrs", "Ms", "Dr", "Prof"])
            DirectBookingTextField("Client Name *", text: $booking.name, placeholder: "Enter Client Name", icon: "person")
            DirectBookingTextField("Father/Spouse Name", text: $booking.fatherSpouseName, placeholder: "Enter Name", icon: "person")
            DirectBookingDateField("Date of Birth", text: $booking.dateOfBirth)
            DirectBookingDateField("Anniversary Date", text: $booking.anniversaryDate)
            DirectBookingTextField("Alternate Numbers", text: $booking.alternateNumbers, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            DirectBookingTextField("WhatsApp Number", text: $booking.whatsappNumber, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            DirectBookingTextField("Email", text: $booking.email, placeholder: "Enter Email Id", icon: "envelope", keyboard: .emailAddress)
            DirectBookingPicker("Nationality", value: $booking.nationality, placeholder: "Select Nationality", icon: "globe", options: ["Indian", "NRI", "Foreign National"])
            DirectBookingTextField("Home Address", text: $booking.homeAddress, placeholder: "Enter Address", icon: "mappin", axis: .vertical)
            DirectBookingTextField("Pincode", text: $booking.pincode, placeholder: "Enter Pincode", icon: "mappin", keyboard: .numberPad)
            DirectBookingTextField("State", text: $booking.state, placeholder: "Enter State", icon: "mappin")
            DirectBookingTextField("District", text: $booking.district, placeholder: "Enter District", icon: "mappin")
            DirectBookingTextField("Location", text: $booking.location, placeholder: "Enter Location", icon: "mappin")
        }
    }

    private var professionalDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingPicker("Profession", value: $booking.profession, placeholder: "Select Profession", icon: "briefcase", options: ["Business", "Salaried", "Self-Employed", "Other"])
            DirectBookingTextField("Designation", text: $booking.designation, placeholder: "Enter Designation", icon: "person")
            DirectBookingTextField("Income Per Annum", text: $booking.incomePerAnnum, placeholder: "Enter Income", icon: "indianrupeesign", keyboard: .decimalPad)
        }
    }

    private var officeDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingTextField("Office Name", text: $booking.officeName, placeholder: "Enter Name", icon: "building.2")
            DirectBookingTextField("Office Email", text: $booking.officeEmail, placeholder: "Enter Email", icon: "envelope", keyboard: .emailAddress)
            DirectBookingTextField("Office Mobile", text: $booking.officeMobile, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            DirectBookingTextField("Office Phone", text: $booking.officePhone, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            DirectBookingTextField("Office Address", text: $booking.officeAddress, placeholder: "Enter Address", icon: "mappin", axis: .vertical)
        }
    }

    private var bookingDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingPickerShell(title: "Booking Ref No", value: "Auto", icon: "number")
            DirectBookingPicker("Booking Type", value: $booking.bookingType, placeholder: "Select Type", icon: "briefcase", options: ["NEW", "CONVERSION", "EXCHANGE", "INTERNAL EXCHANGE"])
            DirectBookingPicker("Source Type", value: $booking.sourceType, placeholder: "Select Type", icon: "briefcase", options: ["walk_in", "cp_visit", "site_visit"])
            DirectBookingTextField("CEF No", text: $booking.cefNo, placeholder: "Enter Number", icon: "doc")
            DirectBookingDateField("Booking Date *", text: $booking.bookingDate, defaultsToToday: true)
            DirectBookingPickerButton(title: "Project", value: selectedProject?.name ?? booking.projectName, placeholder: "Select Project", icon: "briefcase") {
                Task { await loadProjectsThenShowPicker() }
            }
            DirectBookingPickerButton(title: "Plot available Only", value: selectedUnit?.unitNumber ?? booking.plotNo, placeholder: "Select Project First", icon: "square") {
                Task { await loadUnitsThenShowPicker() }
            }
            DirectBookingPicker("Property Type", value: $booking.propertyType, placeholder: "Select Type", icon: "building.2", options: ["Plot", "Apartment", "Villa", "Commercial"])
            DirectBookingPicker("Booking Mode", value: $booking.bookingMode, placeholder: "Select Mode", icon: "creditcard", options: ["Cash", "Cheque", "NEFT", "Online", "Loan"])
            androidCheckRow("Is Against Client Visit", isOn: $booking.isAgainstSV, onText: "Yes", offText: "No (Online Sales)")
            androidCheckRow("Duplicate Bookings", isOn: $booking.isDuplicateBooking, onText: "Yes")
        }
    }

    private var chargesDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingTextField("Booking Cost", text: $booking.bookingCost, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("Guideline Value", text: $booking.guidelineValue, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("Special Consideration", text: $booking.specialConsideration, placeholder: "Enter Details", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("Discount Approved By", text: $booking.discountApprovedBy, placeholder: "Enter Details", icon: "person")
            DirectBookingTextField("SC Reason", text: $booking.specialConsiderationReason, placeholder: "Enter Details", icon: "doc", axis: .vertical)
            DirectBookingTextField("SC Validity", text: $booking.specialConsiderationValidity, placeholder: "Enter Days", icon: "calendar", keyboard: .numberPad)
            DirectBookingTextField("Promotional Offers", text: $booking.promotionalOffers, placeholder: "Enter Details", icon: "tag", axis: .vertical)
            DirectBookingPicker("Promotional Offers T&C", value: $booking.promotionalOffersTnC, placeholder: "Select Offers", icon: "doc", options: ["Default T&C", "Festive T&C", "Custom T&C"])
            DirectBookingTextField("Promotional Offer Value", text: $booking.promotionalOfferValue, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("Offer Validity Period", text: $booking.offerValidityPeriod, placeholder: "Enter Days", icon: "calendar", keyboard: .numberPad)
        }
    }

    private var paymentDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingTextField("Registration Charges", text: $booking.registrationCharges, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("Gst Amount", text: $booking.gstAmount, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            androidCheckRow("If Applicable", isOn: $booking.gstApplicable, onText: "Yes")
            DirectBookingTextField("Document Charges", text: $booking.documentCharges, placeholder: "Enter Cost", icon: "doc", keyboard: .decimalPad)
            DirectBookingTextField("Patta Charges", text: $booking.pattaCharges, placeholder: "Enter Cost", icon: "doc", keyboard: .decimalPad)
            DirectBookingTextField("Other Charges", text: $booking.otherCharges, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            androidCheckRow("If Applicable", isOn: $booking.otherChargesApplicable, onText: "Yes")
            DirectBookingTextField("Advance Amount", text: $booking.advanceAmount, placeholder: "Enter Details", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingPicker("Payment Mode", value: $booking.paymentMode, placeholder: "Select Mode", icon: "creditcard", options: ["Cash", "Cheque", "NEFT", "Online", "Loan"])
            androidCheckRow("Flexi Payment", isOn: $booking.freePayment, onText: "Yes")
            DirectBookingTextField("Allotment Due Amount", text: $booking.allotmentDueAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingDateField("Allotment Due Date", text: $booking.allotmentDueDate)
            DirectBookingTextField("2nd Payment Amount", text: $booking.secondPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingDateField("2nd Payment Date", text: $booking.secondPaymentDate)
            DirectBookingTextField("3rd Payment Amount", text: $booking.thirdPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingDateField("3rd Payment Date", text: $booking.thirdPaymentDate)
            DirectBookingTextField("4th Payment Amount", text: $booking.fourthPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingDateField("4th Payment Date", text: $booking.fourthPaymentDate)
            DirectBookingDateField("Preferred Registration Date", text: $booking.preferredRegistrationDate)
        }
    }

    private var staffDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            staffPicker("AVP", selection: $booking.originalAvpStaffId)
            staffPicker("General Manager", selection: $booking.originalGmStaffId)
            staffPicker("Senior Manager", selection: $booking.originalSeniorManagerStaffId)
            staffPicker("BDO", selection: $booking.originalBdoStaffId)
            staffPicker("Telecaller", selection: $booking.originalTelecallerStaffId)
            DirectBookingTextField("Aadhar Details", text: $booking.aadhaar, placeholder: "Enter Details", icon: "doc", keyboard: .numberPad)
            DirectBookingTextField("Pancard Details", text: $booking.pan, placeholder: "Enter Details", icon: "doc")
            DirectBookingTextField("Reference Name 1", text: $booking.referenceName1, placeholder: "Enter Name", icon: "person")
            DirectBookingTextField("Reference Mobile 1", text: $booking.referenceMobile1, placeholder: "Enter No", icon: "phone", keyboard: .phonePad)
            DirectBookingTextField("Reference Profession 1", text: $booking.referenceProfession1, placeholder: "Enter Details", icon: "briefcase")
            DirectBookingTextField("Reference Name 2", text: $booking.referenceName2, placeholder: "Enter Name", icon: "person")
            DirectBookingTextField("Reference Mobile 2", text: $booking.referenceMobile2, placeholder: "Enter No", icon: "phone", keyboard: .phonePad)
            DirectBookingTextField("Reference Profession 2", text: $booking.referenceProfession2, placeholder: "Enter Details", icon: "briefcase")
            DirectBookingPicker("Document to be prepared in", value: $booking.docPreparedIn, placeholder: "Select", icon: "doc", options: ["English", "Tamil", "Hindi"])
            Picker("Save as", selection: $booking.saveAs) {
                Text("Draft").tag(DirectBookingSaveAs.draft)
                Text("Confirmed").tag(DirectBookingSaveAs.confirmed)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var leadLookupStatus: some View {
        if isSearchingLead {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching lead...")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(hex: 0x667085))
        } else if let selectedLead {
            Button {
                if leadMatches.count > 1 { showLeadPicker = true }
            } label: {
                Label("Linked lead: \(selectedLead.displayName)", systemImage: "person.badge.checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(Color(hex: 0x2DAE12))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(hex: 0x101828))
            .padding(.top, 10)
    }

    private func androidCheckRow(_ title: String, isOn: Binding<Bool>, onText: String, offText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))
            HStack(spacing: 12) {
                Button {
                    isOn.wrappedValue.toggle()
                } label: {
                    Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22, weight: .semibold))
                    Text(isOn.wrappedValue ? onText : (offText ?? onText))
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                }
                .buttonStyle(.plain)
            .foregroundStyle(isOn.wrappedValue ? Color(hex: 0x2DAE12) : Color(hex: 0x475467))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }

    private func staffPicker(_ title: String, selection: Binding<String>) -> some View {
        Menu {
            Button("Clear") { selection.wrappedValue = "" }
            ForEach(staff) { item in
                Button(item.displayName) { selection.wrappedValue = item.id }
            }
        } label: {
            DirectBookingPickerShell(title: title, value: staff.first { $0.id == selection.wrappedValue }?.displayName ?? "Select", icon: "person")
        }
    }

    private var projectPickerSheet: some View {
        NavigationStack {
            List(projects) { project in
                Button(project.name ?? "Unnamed") {
                    selectedProject = project
                    booking.projectName = project.name ?? ""
                    selectedUnit = nil
                    booking.plotNo = ""
                    showProjectPicker = false
                }
            }
            .navigationTitle("Select Project")
        }
        .presentationDetents([.medium, .large])
    }

    private var unitPickerSheet: some View {
        NavigationStack {
            List(availableUnits) { unit in
                Button {
                    guard unit.status == "available" else {
                        errorMessage = "Unit is no longer available"
                        return
                    }
                    selectedUnit = unit
                    booking.plotNo = unit.unitNumber ?? ""
                    showUnitPicker = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(unit.unitNumber ?? "Unit")
                        Text(unit.status)
                            .font(AppModuleFont.rowMeta)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Select Plot")
        }
        .presentationDetents([.medium, .large])
    }

    private var leadPickerSheet: some View {
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
        }
        .presentationDetents([.medium])
    }

    @MainActor
    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadProjects() }
            group.addTask { await loadStaff() }
        }
    }

    @MainActor
    private func loadProjects() async {
        guard let token = authStore.currentSession?.token else { return }
        projects = (try? await MarketingConvexAPIService.getMarketingProjects(token: token)) ?? []
    }

    @MainActor
    private func loadStaff() async {
        guard let token = authStore.currentSession?.token else { return }
        staff = ((try? await HRConvexAPIService.listAllStaff(token: token)) ?? []).filter(\.isActive)
    }

    @MainActor
    private func loadProjectsThenShowPicker() async {
        if projects.isEmpty { await loadProjects() }
        showProjectPicker = !projects.isEmpty
        if projects.isEmpty { errorMessage = "No projects available" }
    }

    @MainActor
    private func loadUnitsThenShowPicker() async {
        guard let token = authStore.currentSession?.token else { return }
        guard let project = selectedProject else {
            errorMessage = "Pick a project first"
            return
        }
        do {
            availableUnits = try await MarketingConvexAPIService.listInventoryUnits(token: token, projectId: project.id, status: "available")
                .filter { $0.status == "available" }
            showUnitPicker = !availableUnits.isEmpty
            if availableUnits.isEmpty { errorMessage = "No available plots in this project" }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func lookupLeadIfNeeded(phone: String) async {
        guard phone.count == 10 else {
            selectedLead = nil
            leadMatches = []
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        isSearchingLead = true
        defer { isSearchingLead = false }
        do {
            let matches = try await MarketingConvexAPIService.searchTelecallerLeadsByPhone(token: token, phone: phone)
            guard AppModuleFormatters.normalizePhone(booking.phone) == phone else { return }
            leadMatches = matches
            if let first = matches.first { applyLead(first) }
        } catch {
            // Lead lookup is helpful, but manual booking entry must stay usable.
        }
    }

    @MainActor
    private func applyLead(_ lead: TelecallerLeadSearchData) {
        selectedLead = lead
        if booking.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            booking.name = lead.displayName
        }
        booking.phone = AppModuleFormatters.normalizePhone(lead.mobileNumber ?? booking.phone)
        booking.homeAddress = lead.suggestedVisitAddress?.directBookingNilIfBlank ?? lead.latestAnalysisProfile?.address?.directBookingNilIfBlank ?? booking.homeAddress
        booking.pincode = lead.latestAnalysisProfile?.pincode?.directBookingNilIfBlank ?? booking.pincode
        booking.state = lead.latestAnalysisProfile?.state?.directBookingNilIfBlank ?? booking.state
        booking.district = lead.latestAnalysisProfile?.district?.directBookingNilIfBlank ?? booking.district
        booking.location = lead.locationPreferred?.directBookingNilIfBlank ?? booking.location
    }

    @MainActor
    private func submit() async {
        let mobile = AppModuleFormatters.normalizePhone(booking.phone)
        guard mobile.count == 10 else { errorMessage = "Client phone number is required"; selectedTab = .client; return }
        guard !booking.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "Client name is required"; selectedTab = .client; return }
        guard booking.bookingDate.directBookingNilIfBlank != nil else { errorMessage = "Booking date is required"; selectedTab = .booking; return }
        guard let token = authStore.currentSession?.token else { return }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await MarketingConvexAPIService.createBooking(
                token: token,
                request: booking.createRequest(
                    mobile: mobile,
                    selectedLead: selectedLead,
                    selectedProject: selectedProject,
                    selectedUnit: selectedUnit
                )
            )
            clearDraft()
            successMessage = "Booking created"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func goToNextTab() {
        let tabs = DirectBookingTab.allCases
        guard let index = tabs.firstIndex(of: selectedTab), index + 1 < tabs.count else { return }
        withAnimation(.snappy(duration: 0.22)) {
            selectedTab = tabs[index + 1]
        }
    }

    private func clearForm() {
        booking = DirectBookingDraft()
        selectedProject = initialProject
        selectedUnit = initialUnit
        selectedLead = nil
        leadMatches = []
        if let initialProject { booking.projectName = initialProject.name ?? "" }
        if let initialUnit { booking.plotNo = initialUnit.unitNumber ?? "" }
        clearDraft()
    }

    private var draftStorageKey: String {
        let subject = authStore.viewer?.subject ?? authStore.currentSession?.user._id ?? "anonymous"
        return "booking.draft.walk_in.full.\(subject)"
    }

    @MainActor
    private func restoreDraftIfNeeded() {
        guard !hasRestoredDraft else { return }
        hasRestoredDraft = true
        if let initialProject { booking.projectName = initialProject.name ?? "" }
        if let initialUnit { booking.plotNo = initialUnit.unitNumber ?? "" }
        guard initialProject == nil, initialUnit == nil,
              let data = UserDefaults.standard.data(forKey: draftStorageKey),
              let draft = try? JSONDecoder().decode(DirectBookingDraft.self, from: data),
              !draft.isEmpty else { return }
        booking = draft
        draftMessage = "Draft restored"
    }

    private func scheduleDraftAutosave() {
        guard hasRestoredDraft, !booking.isEmpty else { return }
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await saveDraft()
        }
    }

    @MainActor
    private func saveDraft() async {
        guard let data = try? JSONEncoder().encode(booking) else { return }
        UserDefaults.standard.set(data, forKey: draftStorageKey)
        draftMessage = "Draft saved"
        guard let token = authStore.currentSession?.token else { return }
        try? await MarketingConvexAPIService.saveBookingDraft(token: token, payload: booking.remotePayload)
    }

    @MainActor
    private func clearDraft() {
        draftSaveTask?.cancel()
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
        draftMessage = nil
        guard let token = authStore.currentSession?.token else { return }
        Task { try? await MarketingConvexAPIService.clearBookingDraft(token: token) }
    }
}

private enum DirectBookingTab: String, CaseIterable, Identifiable {
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
        case .client: return "Client Details"
        case .professional: return "Professional Details"
        case .office: return "Office Details"
        case .booking: return "Booking & Finance"
        case .charges: return "Charges Details"
        case .payment: return "Payment Details"
        case .staff: return "Payment & Staff"
        }
    }
}

private enum DirectBookingSaveAs: String, Codable, Hashable {
    case draft
    case confirmed
}

private struct DirectBookingDraft: Codable, Equatable, Sendable {
    var phone = ""
    var title = ""
    var name = ""
    var fatherSpouseName = ""
    var dateOfBirth = ""
    var anniversaryDate = ""
    var alternateNumbers = ""
    var whatsappNumber = ""
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
    var projectName = ""
    var plotNo = ""
    var bookingType = ""
    var sourceType = "walk_in"
    var cefNo = ""
    var bookingDate = AppModuleFormatters.ymd.string(from: Date())
    var propertyType = ""
    var bookingMode = ""
    var isAgainstSV = false
    var isDuplicateBooking = false
    var bookingCost = ""
    var guidelineValue = ""
    var specialConsideration = ""
    var discountApprovedBy = ""
    var specialConsiderationReason = ""
    var specialConsiderationValidity = ""
    var promotionalOffers = ""
    var promotionalOffersTnC = ""
    var promotionalOfferValue = ""
    var offerValidityPeriod = ""
    var registrationCharges = ""
    var gstAmount = ""
    var gstApplicable = true
    var documentCharges = ""
    var pattaCharges = ""
    var otherCharges = ""
    var otherChargesApplicable = true
    var advanceAmount = ""
    var paymentMode = ""
    var freePayment = true
    var allotmentDueAmount = ""
    var allotmentDueDate = ""
    var secondPaymentAmount = ""
    var secondPaymentDate = ""
    var thirdPaymentAmount = ""
    var thirdPaymentDate = ""
    var fourthPaymentAmount = ""
    var fourthPaymentDate = ""
    var preferredRegistrationDate = ""
    var originalAvpStaffId = ""
    var originalGmStaffId = ""
    var originalSeniorManagerStaffId = ""
    var originalBdoStaffId = ""
    var originalTelecallerStaffId = ""
    var aadhaar = ""
    var pan = ""
    var referenceName1 = ""
    var referenceMobile1 = ""
    var referenceProfession1 = ""
    var referenceName2 = ""
    var referenceMobile2 = ""
    var referenceProfession2 = ""
    var docPreparedIn = ""
    var saveAs: DirectBookingSaveAs = .draft

    var isEmpty: Bool {
        [
            phone, name, projectName, plotNo, bookingCost, advanceAmount, email, homeAddress,
            fatherSpouseName, officeName, cefNo, registrationCharges
        ].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var remotePayload: BookingRemoteDraftPayload {
        BookingRemoteDraftPayload(
            source: "walk_in",
            projectId: nil,
            plotId: nil,
            plotNo: plotNo.directBookingNilIfBlank,
            leadId: nil,
            clientName: name,
            mobileNumber: AppModuleFormatters.normalizePhone(phone),
            bookingDate: bookingDate,
            bookingCost: Double(bookingCost),
            advanceAmount: Double(advanceAmount)
        )
    }

    func createRequest(
        mobile: String,
        selectedLead: TelecallerLeadSearchData?,
        selectedProject: MarketingProject?,
        selectedUnit: InventoryUnit?
    ) -> CreateBookingRequest {
        let cost = Double(bookingCost)
        let advance = Double(advanceAmount)
        let special = Double(specialConsideration)
        return CreateBookingRequest(
            clientName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mobileNumber: mobile,
            bookingDate: bookingDate.directBookingNilIfBlank ?? AppModuleFormatters.ymd.string(from: Date()),
            leadId: selectedLead?.id,
            title: title.directBookingNilIfBlank,
            fatherSpouseName: fatherSpouseName.directBookingNilIfBlank,
            dateOfBirth: dateOfBirth.directBookingNilIfBlank,
            anniversaryDate: anniversaryDate.directBookingNilIfBlank,
            alternateNumbers: alternateNumbers.directBookingNilIfBlank,
            whatsappNumber: whatsappNumber.directBookingNilIfBlank,
            projectId: selectedProject?.id,
            plotId: selectedUnit?.id,
            plotNo: selectedUnit?.unitNumber ?? plotNo.directBookingNilIfBlank,
            bookingType: bookingType.directBookingNilIfBlank,
            cefNo: cefNo.directBookingNilIfBlank,
            isDuplicateBooking: isDuplicateBooking,
            isAgainstSV: isAgainstSV,
            propertyType: propertyType.directBookingNilIfBlank,
            bookingMode: bookingMode.directBookingNilIfBlank,
            bookingCost: cost,
            guidelineValue: Double(guidelineValue),
            specialConsideration: special,
            specialConsiderationReason: specialConsiderationReason.directBookingNilIfBlank,
            discountApprovedBy: discountApprovedBy.directBookingNilIfBlank,
            specialConsiderationValidity: Double(specialConsiderationValidity),
            promotionalOffers: promotionalOffers.directBookingNilIfBlank,
            promotionalOffersTnC: promotionalOffersTnC.directBookingNilIfBlank,
            promotionalOfferValue: Double(promotionalOfferValue),
            offerValidityPeriod: Double(offerValidityPeriod),
            agreedAmount: cost.map { $0 - (special ?? 0) },
            registrationCharges: Double(registrationCharges),
            gstAmount: Double(gstAmount),
            gstApplicable: gstApplicable,
            documentCharges: Double(documentCharges),
            pattaCharges: Double(pattaCharges),
            otherCharges: Double(otherCharges),
            otherChargesApplicable: otherChargesApplicable,
            advanceAmount: advance,
            balanceAmount: cost.flatMap { total in advance.map { total - $0 } },
            paymentMode: paymentMode.directBookingNilIfBlank,
            freePayment: freePayment,
            allotmentDueAmount: Double(allotmentDueAmount),
            allotmentDueDate: allotmentDueDate.directBookingNilIfBlank,
            secondPaymentAmount: Double(secondPaymentAmount),
            secondPaymentDate: secondPaymentDate.directBookingNilIfBlank,
            thirdPaymentAmount: Double(thirdPaymentAmount),
            thirdPaymentDate: thirdPaymentDate.directBookingNilIfBlank,
            fourthPaymentAmount: Double(fourthPaymentAmount),
            fourthPaymentDate: fourthPaymentDate.directBookingNilIfBlank,
            preferredRegistrationDate: preferredRegistrationDate.directBookingNilIfBlank,
            originalAvpStaffId: originalAvpStaffId.directBookingNilIfBlank,
            originalGmStaffId: originalGmStaffId.directBookingNilIfBlank,
            originalSeniorManagerStaffId: originalSeniorManagerStaffId.directBookingNilIfBlank,
            originalBdoStaffId: originalBdoStaffId.directBookingNilIfBlank,
            originalTelecallerStaffId: originalTelecallerStaffId.directBookingNilIfBlank,
            aadhaar: aadhaar.directBookingNilIfBlank,
            pan: pan.directBookingNilIfBlank,
            referenceName1: referenceName1.directBookingNilIfBlank,
            referenceMobile1: referenceMobile1.directBookingNilIfBlank,
            referenceProfession1: referenceProfession1.directBookingNilIfBlank,
            referenceName2: referenceName2.directBookingNilIfBlank,
            referenceMobile2: referenceMobile2.directBookingNilIfBlank,
            referenceProfession2: referenceProfession2.directBookingNilIfBlank,
            docPreparedIn: docPreparedIn.directBookingNilIfBlank,
            email: email.directBookingNilIfBlank,
            pincode: pincode.directBookingNilIfBlank,
            homeAddress: homeAddress.directBookingNilIfBlank,
            profession: profession.directBookingNilIfBlank,
            designation: designation.directBookingNilIfBlank,
            incomePerAnnum: incomePerAnnum.directBookingNilIfBlank,
            officeName: officeName.directBookingNilIfBlank,
            officeAddress: officeAddress.directBookingNilIfBlank,
            state: state.directBookingNilIfBlank,
            district: district.directBookingNilIfBlank,
            location: location.directBookingNilIfBlank,
            officeMobile: officeMobile.directBookingNilIfBlank,
            officePhone: officePhone.directBookingNilIfBlank,
            officeEmail: officeEmail.directBookingNilIfBlank,
            nationality: nationality.directBookingNilIfBlank,
            cpVisitId: nil,
            siteVisitId: nil,
            source: "walk_in",
            status: saveAs == .confirmed ? "pending_confirmation" : "draft",
            sourceType: sourceType.directBookingNilIfBlank ?? "walk_in",
            sourceClientPlaceVisitId: nil,
            sourceSiteVisitId: nil,
            notes: nil
        )
    }

    var serializedNotes: String? {
        [
            "Project: \(projectName)",
            "Plot: \(plotNo)",
            "Save as: \(saveAs.rawValue)"
        ].joined(separator: "\n").directBookingNilIfBlank
    }
}

private struct BookingRemoteDraftPayload: Encodable, Sendable {
    let source: String
    let projectId: String?
    let plotId: String?
    let plotNo: String?
    let leadId: String?
    let clientName: String
    let mobileNumber: String
    let bookingDate: String
    let bookingCost: Double?
    let advanceAmount: Double?
}

private struct DirectBookingTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let icon: String
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    init(_ title: String, text: Binding<String>, placeholder: String = "Enter", icon: String = "pencil", keyboard: UIKeyboardType = .default, axis: Axis = .horizontal) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.icon = icon
        self.keyboard = keyboard
        self.axis = axis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))
            HStack(alignment: axis == .vertical ? .top : .center, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color(hex: 0x98A2B3))
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18)
                TextField(placeholder, text: $text, axis: axis)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .default ? .words : .never)
                    .autocorrectionDisabled(keyboard != .default)
                    .lineLimit(axis == .vertical ? 3...5 : 1...1)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, axis == .vertical ? 11 : 0)
            .frame(minHeight: axis == .vertical ? 72 : 46)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }
}

private struct DirectBookingPicker: View {
    let title: String
    @Binding var value: String
    let placeholder: String
    let icon: String
    let options: [String]

    init(_ title: String, value: Binding<String>, placeholder: String, icon: String, options: [String]) {
        self.title = title
        self._value = value
        self.placeholder = placeholder
        self.icon = icon
        self.options = options
    }

    var body: some View {
        Menu {
            Button("Clear") { value = "" }
            ForEach(options, id: \.self) { option in
                Button(option) { value = option }
            }
        } label: {
            DirectBookingPickerShell(title: title, value: value.isEmpty ? placeholder : value, icon: icon)
        }
    }
}

private struct DirectBookingPickerButton: View {
    let title: String
    let value: String
    let placeholder: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DirectBookingPickerShell(title: title, value: value.directBookingNilIfBlank ?? placeholder, icon: icon)
        }
        .buttonStyle(.plain)
    }
}

private struct DirectBookingPickerShell: View {
    let title: String
    let value: String
    let icon: String

    private var isPlaceholder: Bool {
        value.hasPrefix("Select") || value.hasPrefix("Enter") || value == "dd/mm/yyyy"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color(hex: 0x98A2B3))
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18)
                Text(value)
                    .foregroundStyle(isPlaceholder ? Color(hex: 0x98A2B3) : Color(hex: 0x101828))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }
}

private struct DirectBookingDateField: View {
    let title: String
    @Binding var text: String
    let defaultsToToday: Bool
    @State private var date = Date()
    @State private var showPicker = false

    init(_ title: String, text: Binding<String>, defaultsToToday: Bool = false) {
        self.title = title
        self._text = text
        self.defaultsToToday = defaultsToToday
    }

    var body: some View {
        Button { showPicker = true } label: {
            DirectBookingPickerShell(title: title, value: text.directBookingNilIfBlank ?? "dd/mm/yyyy", icon: "calendar")
        }
        .buttonStyle(.plain)
        .onAppear {
            if let parsed = AppModuleFormatters.ymd.date(from: text) {
                date = parsed
            } else if text.isEmpty, defaultsToToday {
                text = AppModuleFormatters.ymd.string(from: date)
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker(title, selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showPicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                text = AppModuleFormatters.ymd.string(from: date)
                                showPicker = false
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(hex: 0x2DAE12))
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }
}

private extension String {
    var directBookingNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
