import SwiftUI
import UIKit

struct SiteVisitOutcomeSheet: View {
    let siteVisitId: String
    let initialOutcome: String?
    let locksOutcome: Bool
    let onCompleted: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedOutcome: SiteVisitOutcome?
    @State private var bookingSub: SiteVisitBookingSub = .client
    @State private var booking = SiteVisitBookingDraft()
    @State private var projects: [MarketingProject] = []
    @State private var units: [InventoryUnit] = []
    @State private var staff: [ConvexStaffListItem] = []
    @State private var selectedProject: MarketingProject?
    @State private var selectedUnit: InventoryUnit?
    @State private var selectedLead: TelecallerLeadSearchData?
    @State private var leadMatches: [TelecallerLeadSearchData] = []
    @State private var showProjectPicker = false
    @State private var showUnitPicker = false
    @State private var showLeadPicker = false
    @State private var activeStaffPicker: SiteVisitOutcomeStaffField?
    @State private var isSearchingLead = false

    @State private var selectedPostponeReasons: Set<SiteVisitPostponeReason> = []
    @State private var postponedNotes = ""
    @State private var followupDueDate = ""
    @State private var otherRemarks = ""
    @State private var selectedNotInterestedReasons: Set<SiteVisitNotInterestedReason> = []
    @State private var notInterestedDetails: [SiteVisitNotInterestedReason: String] = [:]
    @State private var notInterestedNotes = ""

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let titleOptions = ["Mr", "Mrs", "Ms", "Dr", "Prof"]
    private let nationalityOptions = ["Indian", "NRI", "Foreign National"]
    private let professionOptions = ["Business", "Salaried", "Self-Employed", "Other"]
    private let bookingTypeOptions = ["NEW", "CONVERSION", "EXCHANGE", "INTERNAL EXCHANGE"]
    private let sourceTypeOptions = ["walk_in", "cp_visit", "site_visit"]
    private let propertyTypeOptions = ["Plot", "Apartment", "Villa", "Commercial"]
    private let bookingModeOptions = ["Cash", "Cheque", "NEFT", "Online", "Loan"]
    private let promoTncOptions = ["Default T&C", "Festive T&C", "Custom T&C"]
    private let paymentModeOptions = ["Cash", "Cheque", "NEFT", "Online", "Loan"]
    private let documentLanguageOptions = ["English", "Tamil", "Hindi"]

    init(siteVisitId: String, initialOutcome: String? = nil, locksOutcome: Bool = false, onCompleted: @escaping () -> Void) {
        self.siteVisitId = siteVisitId
        self.initialOutcome = initialOutcome
        self.locksOutcome = locksOutcome
        self.onCompleted = onCompleted
        // Nothing pre-selected unless an explicit initial outcome is passed in
        // (e.g. the list view's locked quick-outcome buttons). Matches Android.
        _selectedOutcome = State(initialValue: initialOutcome.flatMap(SiteVisitOutcome.init(rawValue:)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    outcomeChips

                    switch selectedOutcome {
                    case .booking:
                        bookingSection
                    case .followUp:
                        followUpSection
                    case .notInterested:
                        notInterestedSection
                    case .other:
                        otherSection
                    case .none:
                        chooserPrompt
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xB42318))
                    }

                    if selectedOutcome != nil {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text(ctaTitle)
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(Color(hex: 0x2DAE12))
                        .padding(.top, 6)
                        .disabled(isSaving)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            .background(Color(.systemBackground))
            .appCompactSheetCTAContainer()
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .task { await loadInitialData() }
            .sheet(isPresented: $showProjectPicker) { projectPickerSheet }
            .sheet(isPresented: $showUnitPicker) { unitPickerSheet }
            .sheet(isPresented: $showLeadPicker) { leadPickerSheet }
            .sheet(item: $activeStaffPicker) { field in
                NativeSearchableSelectionSheet(
                    title: "Select \(field.title)",
                    prompt: "Search staff",
                    items: staff,
                    selectedId: staffSelection(for: field),
                    searchText: { item in
                        [item.displayName, item.designation, item.role, item.employeeId, item.phone].compactMap(\.self).joined(separator: " ")
                    },
                    rowContent: { item, isSelected in
                        selectionRow(
                            title: item.displayName,
                            subtitle: item.subtitle.isEmpty ? item.formattedPhone : item.subtitle,
                            isSelected: isSelected
                        )
                    },
                    onSelect: { item in
                        setStaffSelection(item.id, for: field)
                        activeStaffPicker = nil
                    }
                )
                .appLibraryNativeSheet([.medium, .large])
            }
        }
        .appFormActivity()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Outcome Information")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Information about Client Details")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismissKeyboard()
            } label: {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2563EB))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color(hex: 0x2563EB).opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                resetForm()
            } label: {
                Text("Edit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2DAE12))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color(hex: 0x2DAE12).opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var outcomeChips: some View {
        HStack(spacing: 0) {
            ForEach(Array(SiteVisitOutcome.allCases.enumerated()), id: \.element.id) { index, outcome in
                Button {
                    guard !locksOutcome || outcome == selectedOutcome else { return }
                    selectedOutcome = outcome
                    errorMessage = nil
                } label: {
                    SiteVisitOutcomeTabView(outcome: outcome, isSelected: selectedOutcome == outcome)
                        .frame(maxWidth: .infinity)
                        .opacity(locksOutcome && outcome != selectedOutcome ? 0.35 : 1)
                }
                .buttonStyle(.plain)
                .disabled(locksOutcome && outcome != selectedOutcome)

                if index < SiteVisitOutcome.allCases.count - 1 {
                    Rectangle()
                        .fill(Color.appSeparator)
                        .frame(width: 1, height: 28)
                }
            }
        }
        .padding(.top, 14)
    }

    private var bookingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SiteVisitBookingSub.allCases) { sub in
                        Button { bookingSub = sub } label: {
                            Text(sub.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(bookingSub == sub ? .white : Color(hex: 0x475467))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(bookingSub == sub ? Color(hex: 0x2DAE12) : Color.appSurface, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color(hex: 0xE4E7EC), lineWidth: bookingSub == sub ? 0 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            switch bookingSub {
            case .client:
                bookingClientSection
            case .professional:
                bookingProfessionalSection
            case .office:
                bookingOfficeSection
            case .booking:
                bookingDetailsSection
            case .charges:
                bookingChargesSection
            case .payment:
                bookingPaymentSection
            case .staff:
                bookingStaffSection
            }
        }
    }

    private var bookingClientSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiteVisitOutcomeTextField("Client Phone Number *", text: $booking.phone, placeholder: "Enter Mobile Number", icon: "phone", keyboard: .phonePad)
                .onChange(of: booking.phone) { _, value in
                    Task { await lookupLeadIfNeeded(phone: AppModuleFormatters.normalizePhone(value)) }
                }
            leadLookupStatus
            SiteVisitOutcomePicker("Title", value: $booking.title, placeholder: "Select Title", icon: "person", options: titleOptions)
            SiteVisitOutcomeTextField("Client Name *", text: $booking.name, placeholder: "Enter Client Name", icon: "person")
            SiteVisitOutcomeTextField("Father/Spouse Name", text: $booking.fatherSpouseName, placeholder: "Enter Name", icon: "person")
            SiteVisitOutcomeDateField("Date of Birth", text: $booking.dateOfBirth)
            SiteVisitOutcomeDateField("Anniversary Date", text: $booking.anniversaryDate)
            SiteVisitOutcomeTextField("Alternate Numbers", text: $booking.alternateNumbers, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            SiteVisitOutcomeTextField("WhatsApp Number", text: $booking.whatsappNumber, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            SiteVisitOutcomeTextField("Email", text: $booking.email, placeholder: "Enter Email Id", icon: "envelope", keyboard: .emailAddress)
            SiteVisitOutcomePicker("Nationality", value: $booking.nationality, placeholder: "Select Nationality", icon: "globe", options: nationalityOptions)
            SiteVisitOutcomeTextField("Home Address", text: $booking.homeAddress, placeholder: "Enter Address", icon: "mappin", axis: .vertical)
            SiteVisitOutcomeTextField("Pincode", text: $booking.pincode, placeholder: "Enter Pincode", icon: "globe", keyboard: .numberPad)
            SiteVisitOutcomeTextField("State", text: $booking.state, placeholder: "Enter State", icon: "mappin")
            SiteVisitOutcomeTextField("District", text: $booking.district, placeholder: "Enter District", icon: "mappin")
            SiteVisitOutcomeTextField("Location", text: $booking.location, placeholder: "Enter Location", icon: "mappin")
        }
    }

    private var bookingProfessionalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiteVisitOutcomePicker("Profession", value: $booking.profession, placeholder: "Select Profession", icon: "briefcase", options: professionOptions)
            SiteVisitOutcomeTextField("Designation", text: $booking.designation, placeholder: "Enter Designation", icon: "person")
            SiteVisitOutcomeTextField("Income Per Annum", text: $booking.incomePerAnnum, placeholder: "Enter Income", icon: "indianrupeesign", keyboard: .decimalPad)
        }
    }

    private var bookingOfficeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiteVisitOutcomeTextField("Office Name", text: $booking.officeName, placeholder: "Enter Name", icon: "building.2")
            SiteVisitOutcomeTextField("Office Email", text: $booking.officeEmail, placeholder: "Enter Email", icon: "envelope", keyboard: .emailAddress)
            SiteVisitOutcomeTextField("Office Mobile", text: $booking.officeMobile, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            SiteVisitOutcomeTextField("Office Phone", text: $booking.officePhone, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            SiteVisitOutcomeTextField("Office Address", text: $booking.officeAddress, placeholder: "Enter Address", icon: "mappin", axis: .vertical)
        }
    }

    private var bookingDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiteVisitOutcomePickerShell(title: "Booking Ref No", value: "Auto", icon: "number")
            SiteVisitOutcomePicker("Booking Type", value: $booking.bookingType, placeholder: "Select Type", icon: "briefcase", options: bookingTypeOptions)
            SiteVisitOutcomePicker("Source Type", value: $booking.sourceType, placeholder: "Select Type", icon: "briefcase", options: sourceTypeOptions)
            SiteVisitOutcomeTextField("CEF No", text: $booking.cefNo, placeholder: "Enter Number", icon: "doc")
            SiteVisitOutcomeDateField("Booking Date *", text: $booking.bookingDate, defaultsToToday: true)
            SiteVisitOutcomePickerButton(title: "Project", value: selectedProject?.name ?? booking.projectName, placeholder: "Select Project", icon: "briefcase") {
                Task { await loadProjectsThenShowPicker() }
            }
            SiteVisitOutcomePickerButton(title: "Plot available Only", value: selectedUnit?.unitNumber ?? booking.plotNo, placeholder: "Select Project First", icon: "briefcase") {
                Task { await loadUnitsThenShowPicker() }
            }
            SiteVisitOutcomePicker("Property Type", value: $booking.propertyType, placeholder: "Select Type", icon: "briefcase", options: propertyTypeOptions)
            SiteVisitOutcomePicker("Booking Mode", value: $booking.bookingMode, placeholder: "Select Mode", icon: "briefcase", options: bookingModeOptions)
            androidCheckRow("Is Against Client Visit", isOn: $booking.isAgainstSV, onText: "Yes", offText: "No (Online Sales)")
            androidCheckRow("Duplicate Bookings", isOn: $booking.isDuplicateBooking, onText: "Yes")
        }
    }

    private var bookingChargesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiteVisitOutcomeTextField("Booking Cost", text: $booking.bookingCost, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            SiteVisitOutcomeTextField("Guideline Value", text: $booking.guidelineValue, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            SiteVisitOutcomeTextField("Special Consideration", text: $booking.specialConsideration, placeholder: "Enter Details", icon: "indianrupeesign", keyboard: .decimalPad)
            SiteVisitOutcomeTextField("Discount Approved By", text: $booking.discountApprovedBy, placeholder: "Enter Details", icon: "person")
            SiteVisitOutcomeTextField("SC Reason", text: $booking.specialConsiderationReason, placeholder: "Enter Details", icon: "doc", axis: .vertical)
            SiteVisitOutcomeTextField("SC Validity", text: $booking.specialConsiderationValidity, placeholder: "Enter Days", icon: "calendar", keyboard: .numberPad)
            SiteVisitOutcomeTextField("Promotional Offers", text: $booking.promotionalOffers, placeholder: "Enter Details", icon: "tag", axis: .vertical)
            SiteVisitOutcomePicker("Promotional Offers T&C", value: $booking.promotionalOffersTnC, placeholder: "Select Offers", icon: "doc", options: promoTncOptions)
            SiteVisitOutcomeTextField("Promotional Offers Value", text: $booking.promotionalOfferValue, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            SiteVisitOutcomeTextField("Offer Validity Period", text: $booking.offerValidityPeriod, placeholder: "Enter Days", icon: "calendar", keyboard: .numberPad)
        }
    }

    private var bookingPaymentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiteVisitOutcomeTextField("Registration Charges", text: $booking.registrationCharges, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            SiteVisitOutcomeTextField("Gst Amount", text: $booking.gstAmount, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            androidCheckRow("If Applicable", isOn: $booking.gstApplicable, onText: "Yes")
            SiteVisitOutcomeTextField("Document Charges", text: $booking.documentCharges, placeholder: "Enter Cost", icon: "doc", keyboard: .decimalPad)
            SiteVisitOutcomeTextField("Patta Charges", text: $booking.pattaCharges, placeholder: "Enter Cost", icon: "doc", keyboard: .decimalPad)
            SiteVisitOutcomeTextField("Other Charges", text: $booking.otherCharges, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            androidCheckRow("If Applicable", isOn: $booking.otherChargesApplicable, onText: "Yes")
            SiteVisitOutcomeTextField("Advance Amount", text: $booking.advanceAmount, placeholder: "Enter Details", icon: "indianrupeesign", keyboard: .decimalPad)
            SiteVisitOutcomePicker("Payment Mode", value: $booking.paymentMode, placeholder: "Select Mode", icon: "creditcard", options: paymentModeOptions)
            androidCheckRow("Flexi Payment", isOn: $booking.freePayment, onText: "Yes")
            SiteVisitOutcomeTextField("Allotment Due Amount", text: $booking.allotmentDueAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            SiteVisitOutcomeDateField("Allotment Due Date", text: $booking.allotmentDueDate)
            SiteVisitOutcomeTextField("2nd Payment Amount", text: $booking.secondPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            SiteVisitOutcomeDateField("2nd Payment Date", text: $booking.secondPaymentDate)
            SiteVisitOutcomeTextField("3rd Payment Amount", text: $booking.thirdPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            SiteVisitOutcomeDateField("3rd Payment Date", text: $booking.thirdPaymentDate)
            SiteVisitOutcomeTextField("4th Payment Amount", text: $booking.fourthPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            SiteVisitOutcomeDateField("4th Payment Date", text: $booking.fourthPaymentDate)
            SiteVisitOutcomeDateField("Preferred Registration Date", text: $booking.preferredRegistrationDate)
        }
    }

    private var bookingStaffSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            staffPicker(.avp)
            staffPicker(.generalManager)
            staffPicker(.seniorManager)
            staffPicker(.bdo)
            staffPicker(.telecaller)
            SiteVisitOutcomeTextField("Aadhar Details", text: $booking.aadhaar, placeholder: "Enter Details", icon: "doc", keyboard: .numberPad)
            SiteVisitOutcomeTextField("Pancard Details", text: $booking.pan, placeholder: "Enter Details", icon: "doc")
            SiteVisitOutcomeTextField("Reference Name 1", text: $booking.referenceName1, placeholder: "Enter Name", icon: "person")
            SiteVisitOutcomeTextField("Reference Mobile 1", text: $booking.referenceMobile1, placeholder: "Enter No", icon: "phone", keyboard: .phonePad)
            SiteVisitOutcomeTextField("Reference Profession 1", text: $booking.referenceProfession1, placeholder: "Enter Details", icon: "briefcase")
            SiteVisitOutcomeTextField("Reference Name 2", text: $booking.referenceName2, placeholder: "Enter Name", icon: "person")
            SiteVisitOutcomeTextField("Reference Mobile 2", text: $booking.referenceMobile2, placeholder: "Enter No", icon: "phone", keyboard: .phonePad)
            SiteVisitOutcomeTextField("Reference Profession 2", text: $booking.referenceProfession2, placeholder: "Enter Details", icon: "briefcase")
            SiteVisitOutcomePicker("Document to be prepared in", value: $booking.docPreparedIn, placeholder: "Select", icon: "doc", options: documentLanguageOptions)
            Picker("Save as", selection: $booking.saveAs) {
                Text("Draft").tag(SiteVisitBookingSaveAs.draft)
                Text("Confirmed").tag(SiteVisitBookingSaveAs.confirmed)
            }
            .pickerStyle(.segmented)
        }
    }

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiteVisitOutcomeDateField("Follow-up due date", text: $followupDueDate)

            Text("Reasons")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))

            ForEach(SiteVisitPostponeReason.allCases) { reason in
                outcomeCheckCard(title: reason.title, isOn: binding(for: reason))
            }

            SiteVisitOutcomeTextField("Additional notes", text: $postponedNotes, placeholder: "Add notes", icon: "doc", axis: .vertical)
        }
    }

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remarks")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))

            SiteVisitOutcomeTextField("Remarks *", text: $otherRemarks, placeholder: "Explain why this visit is being closed", icon: "doc", axis: .vertical)
        }
    }

    private var chooserPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x98A2B3))
            Text("Select an outcome above to continue.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xF8F9FB), in: RoundedRectangle(cornerRadius: 14))
    }

    private var notInterestedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Why is the client not interested?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(SiteVisitNotInterestedReason.allCases) { reason in
                VStack(alignment: .leading, spacing: 10) {
                    outcomeCheckCard(title: reason.title, isOn: binding(for: reason))
                    if selectedNotInterestedReasons.contains(reason) {
                        SiteVisitOutcomeTextField(
                            "\(reason.title) detail",
                            text: detailBinding(for: reason),
                            placeholder: "Add reason-wise detail",
                            icon: "doc",
                            axis: .vertical
                        )
                    }
                }
            }

            SiteVisitOutcomeTextField("Additional notes", text: $notInterestedNotes, placeholder: "Add notes", icon: "doc", axis: .vertical)
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
            .foregroundStyle(.secondary)
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

    private func androidCheckRow(_ title: String, isOn: Binding<Bool>, onText: String, offText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22, weight: .semibold))
                    Text(isOn.wrappedValue ? onText : (offText ?? onText))
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isOn.wrappedValue ? Color(hex: 0x2DAE12) : Color(hex: 0x475467))
        }
    }

    private func outcomeCheckCard(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? Color(hex: 0x2DAE12) : Color(hex: 0x98A2B3))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(14)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isOn.wrappedValue ? Color(hex: 0x2DAE12) : Color(hex: 0xE4E7EC), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func staffPicker(_ field: SiteVisitOutcomeStaffField) -> some View {
        Button {
            activeStaffPicker = field
        } label: {
            SiteVisitOutcomePickerShell(
                title: field.title,
                value: staff.first { $0.id == staffSelection(for: field) }?.displayName ?? "Select",
                icon: "person"
            )
        }
        .buttonStyle(.plain)
    }

    private func staffSelection(for field: SiteVisitOutcomeStaffField) -> String {
        switch field {
        case .avp: booking.originalAvpStaffId
        case .generalManager: booking.originalGmStaffId
        case .seniorManager: booking.originalSeniorManagerStaffId
        case .bdo: booking.originalBdoStaffId
        case .telecaller: booking.originalTelecallerStaffId
        }
    }

    private func setStaffSelection(_ id: String, for field: SiteVisitOutcomeStaffField) {
        switch field {
        case .avp: booking.originalAvpStaffId = id
        case .generalManager: booking.originalGmStaffId = id
        case .seniorManager: booking.originalSeniorManagerStaffId = id
        case .bdo: booking.originalBdoStaffId = id
        case .telecaller: booking.originalTelecallerStaffId = id
        }
    }

    private var projectPickerSheet: some View {
        NativeSearchableSelectionSheet(
            title: "Select Project",
            prompt: "Search projects",
            items: projects,
            selectedId: selectedProject?.id,
            searchText: { project in
                [project.name, project.location].compactMap(\.self).joined(separator: " ")
            },
            rowContent: { project, isSelected in
                selectionRow(
                    title: project.name ?? "Unnamed project",
                    subtitle: project.location,
                    isSelected: isSelected
                )
            },
            onSelect: { project in
                selectedProject = project
                booking.projectName = project.name ?? ""
                selectedUnit = nil
                booking.plotNo = ""
                showProjectPicker = false
            }
        )
        .appLibraryNativeSheet([.medium, .large])
    }

    private var unitPickerSheet: some View {
        NativeSearchableSelectionSheet(
            title: "Select Plot",
            prompt: "Search plots",
            items: units,
            selectedId: selectedUnit?.id,
            searchText: { unit in
                [unit.unitNumber, unitSummary(unit)].compactMap(\.self).joined(separator: " ")
            },
            rowContent: { unit, isSelected in
                selectionRow(
                    title: unit.unitNumber ?? "Unit",
                    subtitle: unitSummary(unit),
                    isSelected: isSelected
                )
            },
            onSelect: { unit in
                selectedUnit = unit
                booking.plotNo = unit.unitNumber ?? ""
                showUnitPicker = false
            }
        )
        .appLibraryNativeSheet([.medium, .large])
    }

    private var leadPickerSheet: some View {
        NativeSearchableSelectionSheet(
            title: "Select Client",
            prompt: "Search clients",
            items: leadMatches,
            selectedId: selectedLead?.id,
            searchText: { lead in
                [lead.displayName, lead.mobileNumber].compactMap(\.self).joined(separator: " ")
            },
            rowContent: { lead, isSelected in
                selectionRow(
                    title: lead.displayName,
                    subtitle: lead.mobileNumber ?? "No mobile",
                    isSelected: isSelected
                )
            },
            onSelect: { lead in
                applyLead(lead)
                showLeadPicker = false
            }
        )
        .appLibraryNativeSheet([.medium])
    }

    private func selectionRow(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }
        }
        .padding(.vertical, 4)
    }

    private var ctaTitle: String {
        switch selectedOutcome {
        case .booking: return booking.saveAs == .confirmed ? "Create Confirmed Booking" : "Save Booking Draft"
        case .followUp: return "Save Follow-up Outcome"
        case .notInterested: return "Save Not Interested Outcome"
        case .other: return "Save Outcome"
        case .none: return "Save Outcome"
        }
    }

    private func binding(for reason: SiteVisitPostponeReason) -> Binding<Bool> {
        Binding {
            selectedPostponeReasons.contains(reason)
        } set: { isSelected in
            if isSelected {
                selectedPostponeReasons.insert(reason)
            } else {
                selectedPostponeReasons.remove(reason)
            }
        }
    }

    private func binding(for reason: SiteVisitNotInterestedReason) -> Binding<Bool> {
        Binding {
            selectedNotInterestedReasons.contains(reason)
        } set: { isSelected in
            if isSelected {
                selectedNotInterestedReasons.insert(reason)
            } else {
                selectedNotInterestedReasons.remove(reason)
                notInterestedDetails[reason] = nil
            }
        }
    }

    private func detailBinding(for reason: SiteVisitNotInterestedReason) -> Binding<String> {
        Binding {
            notInterestedDetails[reason] ?? ""
        } set: {
            notInterestedDetails[reason] = $0
        }
    }

    @MainActor
    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadProjectsIfNeeded() }
            group.addTask { await loadStaffIfNeeded() }
        }
    }

    @MainActor
    private func loadProjectsIfNeeded() async {
        guard projects.isEmpty, let token = authStore.currentSession?.token else { return }
        projects = (try? await MarketingConvexAPIService.getMarketingProjects(token: token)) ?? []
    }

    @MainActor
    private func loadStaffIfNeeded() async {
        guard staff.isEmpty, let token = authStore.currentSession?.token else { return }
        staff = ((try? await HRConvexAPIService.listAllStaff(token: token)) ?? []).filter(\.isActive)
    }

    @MainActor
    private func loadProjectsThenShowPicker() async {
        await loadProjectsIfNeeded()
        guard !projects.isEmpty else {
            errorMessage = "No projects available"
            return
        }
        showProjectPicker = true
    }

    @MainActor
    private func loadUnitsThenShowPicker() async {
        guard let project = selectedProject else {
            errorMessage = "Pick a project first"
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        do {
            units = try await MarketingConvexAPIService.listInventoryUnits(token: token, projectId: project.id, status: "available")
                .filter { $0.status == "available" }
            showUnitPicker = !units.isEmpty
            if units.isEmpty { errorMessage = "No available units in this project" }
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
            // Manual booking entry should remain usable when lookup fails.
        }
    }

    @MainActor
    private func applyLead(_ lead: TelecallerLeadSearchData) {
        selectedLead = lead
        booking.phone = AppModuleFormatters.normalizePhone(lead.mobileNumber ?? booking.phone)
        if booking.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            booking.name = lead.displayName
        }
        booking.homeAddress = lead.suggestedVisitAddress?.outcomeNilIfBlank ?? lead.latestAnalysisProfile?.address?.outcomeNilIfBlank ?? booking.homeAddress
        booking.pincode = lead.latestAnalysisProfile?.pincode?.outcomeNilIfBlank ?? booking.pincode
        booking.state = lead.latestAnalysisProfile?.state?.outcomeNilIfBlank ?? booking.state
        booking.district = lead.latestAnalysisProfile?.district?.outcomeNilIfBlank ?? booking.district
        booking.location = lead.locationPreferred?.outcomeNilIfBlank ?? booking.location
    }

    @MainActor
    private func submit() async {
        errorMessage = nil
        guard let token = authStore.currentSession?.token else { return }
        guard let outcome = selectedOutcome else {
            errorMessage = "Select an outcome to continue"
            return
        }
        isSaving = true
        defer { isSaving = false }

        do {
            switch outcome {
            case .booking:
                let bookingId = try await createBooking(token: token)
                try await saveOutcome(token: token, outcome: outcome, bookingId: bookingId)
            case .followUp:
                guard !selectedPostponeReasons.isEmpty else {
                    errorMessage = "Select at least one follow-up reason"
                    return
                }
                try await saveOutcome(token: token, outcome: outcome, bookingId: nil)
            case .notInterested:
                guard !selectedNotInterestedReasons.isEmpty else {
                    errorMessage = "Select at least one not interested reason"
                    return
                }
                try await saveOutcome(token: token, outcome: outcome, bookingId: nil)
            case .other:
                guard otherRemarks.outcomeNilIfBlank != nil else {
                    errorMessage = "Add remarks to explain this outcome"
                    return
                }
                try await saveOutcome(token: token, outcome: outcome, bookingId: nil)
            }
            onCompleted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createBooking(token: String) async throws -> String {
        let mobile = AppModuleFormatters.normalizePhone(booking.phone)
        let name = booking.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mobile.count == 10 else { throw SiteVisitOutcomeError.message("Client phone number is required") }
        guard !name.isEmpty else { throw SiteVisitOutcomeError.message("Client name is required") }
        guard booking.bookingDate.outcomeNilIfBlank != nil else { throw SiteVisitOutcomeError.message("Booking date is required") }

        return try await MarketingConvexAPIService.createBooking(
            token: token,
            request: booking.createRequest(
                mobile: mobile,
                selectedLead: selectedLead,
                selectedProject: selectedProject,
                selectedUnit: selectedUnit,
                siteVisitId: siteVisitId
            )
        )
    }

    private func saveOutcome(token: String, outcome: SiteVisitOutcome, bookingId: String?) async throws {
        // Best-effort unlock: the outcome buttons unlock at on_site, but setOutcome
        // only accepts on_counselling|picked_from_site|dropped, so nudge first.
        try? await MarketingConvexAPIService.markSiteVisitOnCounselling(token: token, id: siteVisitId)

        let reasonCodes = selectedReasonCodes(for: outcome)
        try await MarketingConvexAPIService.setSiteVisitOutcome(
            token: token,
            request: SetSiteVisitOutcomeRequest(
                id: siteVisitId,
                outcome: outcome.rawValue,
                reasons: reasonCodes,
                postponeReasons: outcome == .followUp ? reasonCodes : nil,
                notInterestedReasons: outcome == .notInterested ? reasonCodes : nil,
                notInterestedDetails: outcome == .notInterested ? notInterestedDetailPayload : nil,
                notes: outcome == .other ? otherRemarks.outcomeNilIfBlank : outcomeNotes(outcome: outcome, bookingId: bookingId),
                bookingId: bookingId,
                followupDueDate: outcome == .followUp ? followupDueDate.outcomeNilIfBlank : nil,
                followupDueTime: nil
            )
        )
    }

    private func selectedReasonCodes(for outcome: SiteVisitOutcome) -> [String]? {
        switch outcome {
        case .booking, .other:
            return nil
        case .followUp:
            return selectedPostponeReasons.map(\.rawValue).sorted()
        case .notInterested:
            return selectedNotInterestedReasons.map(\.rawValue).sorted()
        }
    }

    private var notInterestedDetailPayload: [SiteVisitNotInterestedDetail]? {
        let items = selectedNotInterestedReasons.sorted { $0.title < $1.title }.map {
            SiteVisitNotInterestedDetail(reason: $0.rawValue, detail: notInterestedDetails[$0]?.outcomeNilIfBlank)
        }
        return items.isEmpty ? nil : items
    }

    private func outcomeNotes(outcome: SiteVisitOutcome, bookingId: String?) -> String? {
        var rows: [String] = []
        if let bookingId { rows.append("Booking ID: \(bookingId)") }
        switch outcome {
        case .booking:
            rows.append("Outcome: Converted to Booking")
            if let notes = booking.notes.outcomeNilIfBlank { rows.append("Notes: \(notes)") }
        case .followUp:
            rows.append("Reasons: \(selectedPostponeReasons.map(\.title).sorted().joined(separator: ", "))")
            if let due = followupDueDate.outcomeNilIfBlank { rows.append("Follow-up: \(due)") }
            if let notes = postponedNotes.outcomeNilIfBlank { rows.append("Notes: \(notes)") }
        case .notInterested:
            rows.append(contentsOf: selectedNotInterestedReasons.sorted { $0.title < $1.title }.map { reason in
                if let detail = notInterestedDetails[reason]?.outcomeNilIfBlank {
                    return "\(reason.title): \(detail)"
                }
                return reason.title
            })
            if let notes = notInterestedNotes.outcomeNilIfBlank { rows.append("Notes: \(notes)") }
        case .other:
            if let notes = otherRemarks.outcomeNilIfBlank { rows.append("Notes: \(notes)") }
        }
        return rows.joined(separator: "\n").outcomeNilIfBlank
    }

    private func unitSummary(_ unit: InventoryUnit) -> String {
        var parts: [String] = []
        if let type = unit.unitType?.outcomeNilIfBlank { parts.append(type) }
        if let facing = unit.facing?.outcomeNilIfBlank { parts.append("facing \(facing)") }
        if let area = unit.area { parts.append("\(Int(area)) sqft") }
        return parts.joined(separator: " · ")
    }

    private func resetForm() {
        errorMessage = nil
        switch selectedOutcome {
        case .booking:
            booking = SiteVisitBookingDraft()
            selectedProject = nil
            selectedUnit = nil
            selectedLead = nil
            leadMatches = []
            bookingSub = .client
        case .followUp:
            selectedPostponeReasons = []
            postponedNotes = ""
            followupDueDate = ""
        case .notInterested:
            selectedNotInterestedReasons = []
            notInterestedDetails = [:]
            notInterestedNotes = ""
        case .other:
            otherRemarks = ""
        case .none:
            break
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private enum SiteVisitOutcome: String, CaseIterable, Identifiable {
    case booking = "converted_to_booking"
    case followUp = "follow_up"
    case notInterested = "not_interested"
    case other = "other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .booking: return "Booking"
        case .followUp: return "Follow up"
        case .notInterested: return "Not Interested"
        case .other: return "Others"
        }
    }

    var icon: String {
        switch self {
        case .booking: return "briefcase.fill"
        case .followUp: return "calendar.badge.clock"
        case .notInterested: return "hand.thumbsdown.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

private enum SiteVisitBookingSub: String, CaseIterable, Identifiable {
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

private enum SiteVisitOutcomeStaffField: String, Identifiable {
    case avp
    case generalManager
    case seniorManager
    case bdo
    case telecaller

    var id: String { rawValue }

    var title: String {
        switch self {
        case .avp: return "AVP"
        case .generalManager: return "General Manager"
        case .seniorManager: return "Senior Manager"
        case .bdo: return "BDO"
        case .telecaller: return "Telecaller"
        }
    }
}

private enum SiteVisitBookingSaveAs: String, Codable, Hashable {
    case draft
    case confirmed
}

private struct SiteVisitBookingDraft: Codable, Equatable, Sendable {
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
    var sourceType = "site_visit"
    var cefNo = ""
    var bookingDate = AppModuleFormatters.ymd.string(from: Date())
    var propertyType = ""
    var bookingMode = ""
    var isAgainstSV = true
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
    var notes = ""
    var saveAs: SiteVisitBookingSaveAs = .confirmed

    func createRequest(
        mobile: String,
        selectedLead: TelecallerLeadSearchData?,
        selectedProject: MarketingProject?,
        selectedUnit: InventoryUnit?,
        siteVisitId: String
    ) -> CreateBookingRequest {
        let cost = Double(bookingCost)
        let advance = Double(advanceAmount)
        let special = Double(specialConsideration)
        return CreateBookingRequest(
            clientName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mobileNumber: mobile,
            bookingDate: bookingDate.outcomeNilIfBlank ?? AppModuleFormatters.ymd.string(from: Date()),
            leadId: selectedLead?.id,
            title: title.outcomeNilIfBlank,
            fatherSpouseName: fatherSpouseName.outcomeNilIfBlank,
            dateOfBirth: dateOfBirth.outcomeNilIfBlank,
            anniversaryDate: anniversaryDate.outcomeNilIfBlank,
            alternateNumbers: alternateNumbers.outcomeNilIfBlank,
            whatsappNumber: whatsappNumber.outcomeNilIfBlank,
            projectId: selectedProject?.id,
            plotId: selectedUnit?.id,
            plotNo: selectedUnit?.unitNumber ?? plotNo.outcomeNilIfBlank,
            bookingType: bookingType.outcomeNilIfBlank,
            cefNo: cefNo.outcomeNilIfBlank,
            isDuplicateBooking: isDuplicateBooking,
            isAgainstSV: isAgainstSV,
            propertyType: propertyType.outcomeNilIfBlank,
            bookingMode: bookingMode.outcomeNilIfBlank,
            bookingCost: cost,
            guidelineValue: Double(guidelineValue),
            specialConsideration: special,
            specialConsiderationReason: specialConsiderationReason.outcomeNilIfBlank,
            discountApprovedBy: discountApprovedBy.outcomeNilIfBlank,
            specialConsiderationValidity: Double(specialConsiderationValidity),
            promotionalOffers: promotionalOffers.outcomeNilIfBlank,
            promotionalOffersTnC: promotionalOffersTnC.outcomeNilIfBlank,
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
            paymentMode: paymentMode.outcomeNilIfBlank,
            freePayment: freePayment,
            allotmentDueAmount: Double(allotmentDueAmount),
            allotmentDueDate: allotmentDueDate.outcomeNilIfBlank,
            secondPaymentAmount: Double(secondPaymentAmount),
            secondPaymentDate: secondPaymentDate.outcomeNilIfBlank,
            thirdPaymentAmount: Double(thirdPaymentAmount),
            thirdPaymentDate: thirdPaymentDate.outcomeNilIfBlank,
            fourthPaymentAmount: Double(fourthPaymentAmount),
            fourthPaymentDate: fourthPaymentDate.outcomeNilIfBlank,
            preferredRegistrationDate: preferredRegistrationDate.outcomeNilIfBlank,
            originalAvpStaffId: originalAvpStaffId.outcomeNilIfBlank,
            originalGmStaffId: originalGmStaffId.outcomeNilIfBlank,
            originalSeniorManagerStaffId: originalSeniorManagerStaffId.outcomeNilIfBlank,
            originalBdoStaffId: originalBdoStaffId.outcomeNilIfBlank,
            originalTelecallerStaffId: originalTelecallerStaffId.outcomeNilIfBlank,
            aadhaar: aadhaar.outcomeNilIfBlank,
            pan: pan.outcomeNilIfBlank,
            referenceName1: referenceName1.outcomeNilIfBlank,
            referenceMobile1: referenceMobile1.outcomeNilIfBlank,
            referenceProfession1: referenceProfession1.outcomeNilIfBlank,
            referenceName2: referenceName2.outcomeNilIfBlank,
            referenceMobile2: referenceMobile2.outcomeNilIfBlank,
            referenceProfession2: referenceProfession2.outcomeNilIfBlank,
            docPreparedIn: docPreparedIn.outcomeNilIfBlank,
            email: email.outcomeNilIfBlank,
            pincode: pincode.outcomeNilIfBlank,
            homeAddress: homeAddress.outcomeNilIfBlank,
            profession: profession.outcomeNilIfBlank,
            designation: designation.outcomeNilIfBlank,
            incomePerAnnum: incomePerAnnum.outcomeNilIfBlank,
            officeName: officeName.outcomeNilIfBlank,
            officeAddress: officeAddress.outcomeNilIfBlank,
            state: state.outcomeNilIfBlank,
            district: district.outcomeNilIfBlank,
            location: location.outcomeNilIfBlank,
            officeMobile: officeMobile.outcomeNilIfBlank,
            officePhone: officePhone.outcomeNilIfBlank,
            officeEmail: officeEmail.outcomeNilIfBlank,
            nationality: nationality.outcomeNilIfBlank,
            cpVisitId: nil,
            siteVisitId: siteVisitId,
            source: "site_visit",
            status: saveAs == .confirmed ? "pending_confirmation" : "draft",
            sourceType: sourceType.outcomeNilIfBlank ?? "site_visit",
            sourceClientPlaceVisitId: nil,
            sourceSiteVisitId: siteVisitId,
            notes: notes.outcomeNilIfBlank
        )
    }
}

private struct SiteVisitOutcomeTabView: View {
    let outcome: SiteVisitOutcome
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: outcome.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color(hex: 0x2DAE12) : Color(hex: 0x667085))
            Text(outcome.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color(hex: 0x2DAE12) : Color(hex: 0x667085))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(height: 62)
        .background(isSelected ? Color(hex: 0x2DAE12).opacity(0.14) : Color.appSurface)
        .overlay(
            Rectangle()
                .fill(isSelected ? Color(hex: 0x2DAE12) : .clear)
                .frame(height: 2),
            alignment: .bottom
        )
    }
}

private struct SiteVisitOutcomeTextField: View {
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: axis == .vertical ? .top : .center, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Color(hex: 0x98A2B3))
                    .frame(width: 20)
                TextField(placeholder, text: $text, axis: axis)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .default ? .words : .never)
                    .autocorrectionDisabled(keyboard != .default)
                    .lineLimit(axis == .vertical ? 3...5 : 1...1)
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }
}

private struct SiteVisitOutcomePicker: View {
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
            SiteVisitOutcomePickerShell(title: title, value: value.isEmpty ? placeholder : value, icon: icon)
        }
    }
}

private struct SiteVisitOutcomePickerButton: View {
    let title: String
    let value: String
    let placeholder: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SiteVisitOutcomePickerShell(title: title, value: value.outcomeNilIfBlank ?? placeholder, icon: icon)
        }
        .buttonStyle(.plain)
    }
}

private struct SiteVisitOutcomePickerShell: View {
    let title: String
    let value: String
    let icon: String

    private var isPlaceholder: Bool {
        value.hasPrefix("Select") || value.hasPrefix("Enter") || value == "dd/mm/yyyy"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Color(hex: 0x98A2B3))
                    .frame(width: 20)
                Text(value)
                    .foregroundStyle(isPlaceholder ? Color(hex: 0x98A2B3) : Color(hex: 0x101828))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }
}

private struct SiteVisitOutcomeDateField: View {
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
            SiteVisitOutcomePickerShell(title: title, value: text.outcomeNilIfBlank ?? "dd/mm/yyyy", icon: "calendar")
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
            .appLibraryNativeSheet([.medium])
        }
    }
}

private enum SiteVisitPostponeReason: String, CaseIterable, Identifiable {
    case clientUnavailable = "client_unavailable"
    case weather
    case vehicleIssue = "vehicle_issue"
    case documentPending = "document_pending"
    case rescheduledByClient = "rescheduled_by_client"
    case otherCommitment = "other_commitment"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clientUnavailable: return "Client unavailable"
        case .weather: return "Weather"
        case .vehicleIssue: return "Vehicle issue"
        case .documentPending: return "Document pending"
        case .rescheduledByClient: return "Rescheduled by client"
        case .otherCommitment: return "Other commitment"
        }
    }
}

private enum SiteVisitNotInterestedReason: String, CaseIterable, Identifiable {
    case price
    case distance
    case location
    case developmentInSourcingArea = "development_in_sourcing_area"
    case preferredPlotNotChoice = "preferred_plot_not_choice"
    case loanEligibility = "loan_eligibility"
    case staffBehaviour = "staff_behaviour"
    case driverBehaviour = "driver_behaviour"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .price: return "Price"
        case .distance: return "Distance"
        case .location: return "Location"
        case .developmentInSourcingArea: return "Development in sourcing area"
        case .preferredPlotNotChoice: return "Preferred plot not choice"
        case .loanEligibility: return "Loan eligibility"
        case .staffBehaviour: return "Staff behaviour"
        case .driverBehaviour: return "Driver behaviour"
        }
    }
}

private enum SiteVisitOutcomeError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}

private extension String {
    var outcomeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
