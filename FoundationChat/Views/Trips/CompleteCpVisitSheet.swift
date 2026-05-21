import SwiftUI
import UIKit

// MARK: - CompleteCpVisitSheet

struct CompleteCpVisitSheet: View {
    let cpVisitId: String
    let initialOutcome: String?
    let onCompleted: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedOutcome: CpVisitOutcome?
    @State private var budgetConcern = ""
    @State private var timingNotes = ""
    @State private var projectDetails = ""
    @State private var otherPostponeNotes = ""
    @State private var postponeFollowUpDate = Date()
    @State private var notInterestedBudgetConcern = ""
    @State private var notInterestedTimingNotes = ""
    @State private var notInterestedProjectDetails = ""
    @State private var notInterestedOtherNotes = ""
    @State private var bookingSub: BookingSub = .client
    @State private var bookingStep: BookingStep = .findMobile
    @State private var bookingClientMobile = ""
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

    private let titleOptions = ["Mr", "Mrs", "Ms", "Dr", "Prof"]
    private let nationalityOptions = ["Indian", "NRI", "Foreign National"]
    private let professionOptions = ["Business", "Salaried", "Self-Employed", "Other"]
    private let bookingTypeOptions = ["Direct", "Channel Partner", "Online"]
    private let sourceTypeOptions = ["Walk-in", "Referral", "Marketing", "Online"]
    private let propertyTypeOptions = ["Plot", "Apartment", "Villa"]
    private let bookingModeOptions = ["Cash", "Cheque", "Online Transfer"]
    private let promoTncOptions = ["Default T&C", "Festive T&C", "Custom T&C"]
    private let paymentModeOptions = ["Lump Sum", "Construction-Linked", "Flexi"]
    private let documentLanguageOptions = ["English", "Tamil", "Hindi"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Capsule()
                        .fill(Color(hex: 0xE4E7EC))
                        .frame(width: 40, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 2)

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Outcome Information")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x101828))
                            Text("Information about Client Details")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: 0x94A3B8))
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
                                .background(Color(hex: 0xEFF6FF), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            resetOutcomeToBookingFindClient()
                        } label: {
                            Text("Edit")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x2DAE12))
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(Color(hex: 0xEAF8E8), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

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
                        notInterestedSection
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
                            Text(ctaTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x1ECB09), Color(hex: 0x3D9D02)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 26)
                    )
                    .padding(.top, 6)
                    .disabled(isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .scrollDismissesKeyboard(.interactively)
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
        HStack(spacing: 0) {
            ForEach(Array(CpVisitOutcome.allCases.enumerated()), id: \.element.id) { index, outcome in
                Button {
                    selectedOutcome = outcome
                    if outcome == .booking {
                        bookingSub = .client
                        bookingStep = .findMobile
                    }
                } label: {
                    OutcomeTabView(
                        outcome: outcome,
                        isSelected: selectedOutcome == outcome
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                if index < CpVisitOutcome.allCases.count - 1 {
                    Rectangle()
                        .fill(Color(hex: 0xF3F3F5))
                        .frame(width: 1, height: 28)
                }
            }
        }
        .padding(.top, 14)
    }

    private func resetOutcomeToBookingFindClient() {
        dismissKeyboard()
        selectedOutcome = .booking
        bookingSub = .client
        bookingStep = .findMobile
        errorMessage = nil
    }

    private var siteVisitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Date")
                    DatePicker("", selection: $siteVisitDate, displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 48)
                        .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Time")
                    DatePicker("", selection: $siteVisitTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 48)
                        .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            sectionLabel("Pickup From")
            HStack(spacing: 12) {
                SegmentButton(title: "Own Vehicle", isSelected: travelMode == .ownVehicle) {
                    travelMode = .ownVehicle
                }
                SegmentButton(title: "Cab Vehicle", isSelected: travelMode == .cab) {
                    travelMode = .cab
                }
            }
            fieldEditor("Enter Address", text: $pickupAddress, minLines: 3, label: "Pickup Address (If Needed)")

            sectionLabel("Business Development Organisation")
            FieldShell {
                Text("Keep Original")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x64748B))
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
            TextField("0", text: $visitorCount)
                .keyboardType(.numberPad)
                .cpFieldStyle(icon: "person")
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
            if bookingStep == .clientForm {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(BookingSub.allCases) { sub in
                            BookingSubTab(title: sub.title, isSelected: bookingSub == sub)
                        }
                    }
                }
            }
            bookingSubBody
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var bookingSubBody: some View {
        switch bookingSub {
        case .client:
            if bookingStep == .findMobile {
                bookingFindClientFields
            } else {
                bookingClientFields
            }
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

    private var bookingFindClientFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 62, weight: .regular))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 120, height: 120)
                    .background(Color(hex: 0xEAF2FF), in: Circle())
                Text("Let's find your client")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Text("Enter the client's mobile number to fetch their details from the project.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x94A3B8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 8)

            BookingTextField("Client Mobile Number *", text: $bookingClientMobile, placeholder: "Enter Mobile Number", icon: "phone", keyboard: .phonePad)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2DAE12))
                Text("We will fetch and auto-fill client details from the project.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x2DAE12))
            }
            .padding(12)
            .background(Color(hex: 0xECFDF3), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var bookingClientFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            BookingReadonlyField(title: "Client Phone Number *", value: booking.phone, icon: "phone")
            BookingPickerTextField("Title", text: $booking.title, placeholder: "Select Title", icon: "person", options: titleOptions)
            BookingTextField("Client Name *", text: $booking.name, placeholder: "Enter Client Name", icon: "person")
            BookingTextField("Father/Spouse Name", text: $booking.fatherOrSpouse, placeholder: "Enter Name", icon: "person")
            BookingDateTextField("Date of Birth", text: $booking.dob)
            BookingDateTextField("Anniversary Date", text: $booking.anniversary)
            BookingTextField("Alternate Number", text: $booking.altNumber, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            BookingTextField("Whatsapp Number", text: $booking.whatsapp, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            BookingTextField("Email", text: $booking.email, placeholder: "Enter Email", icon: "envelope", keyboard: .emailAddress)
            BookingPickerTextField("Nationality", text: $booking.nationality, placeholder: "Select Nationality", icon: "globe", options: nationalityOptions)
            BookingTextField("Home Address", text: $booking.homeAddress, placeholder: "Enter Address", icon: "mappin", axis: .vertical)
            BookingTextField("Pincode", text: $booking.pincode, placeholder: "Enter Pincode", icon: "mappin", keyboard: .numberPad)
            BookingTextField("State", text: $booking.state, placeholder: "Enter State", icon: "mappin")
            BookingTextField("District", text: $booking.district, placeholder: "Enter District", icon: "mappin")
            BookingTextField("Location", text: $booking.location, placeholder: "Enter Location", icon: "mappin")
        }
    }

    private var bookingProfessionalFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            BookingPickerTextField("Profession", text: $booking.profession, placeholder: "Select Profession", icon: "briefcase", options: professionOptions)
            BookingTextField("Designation", text: $booking.designation, placeholder: "Enter Designation", icon: "person")
            BookingTextField("Income Per Annum", text: $booking.incomePerAnnum, placeholder: "Enter Income", icon: "indianrupeesign", keyboard: .decimalPad)
        }
    }

    private var bookingOfficeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            BookingTextField("Office Name", text: $booking.officeName, placeholder: "Enter Office Name", icon: "building.2")
            BookingTextField("Office Email", text: $booking.officeEmail, placeholder: "Enter Email", icon: "envelope", keyboard: .emailAddress)
            BookingTextField("Office Mobile", text: $booking.officeMobile, placeholder: "Enter Mobile", icon: "phone", keyboard: .phonePad)
            BookingTextField("Office Phone", text: $booking.officePhone, placeholder: "Enter Phone", icon: "phone", keyboard: .phonePad)
            BookingTextField("Office Address", text: $booking.officeAddress, placeholder: "Enter Address", icon: "mappin", axis: .vertical)
        }
    }

    private var bookingDetailsFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            BookingTextField("Booking Ref No", text: $booking.bookingRefNo, placeholder: "Enter Ref No", icon: "number")
            BookingPickerTextField("Booking Type", text: $booking.bookingType, placeholder: "Select Type", icon: "briefcase", options: bookingTypeOptions)
            BookingPickerTextField("Source Type", text: $booking.sourceType, placeholder: "Select Type", icon: "briefcase", options: sourceTypeOptions)
            BookingTextField("CEF No", text: $booking.cefNo, placeholder: "Enter CEF No", icon: "doc")
            BookingDateTextField("Booking Date *", text: $booking.bookingDate)
            BookingPickerTextField("Project", text: $booking.project, placeholder: "Select Project", icon: "briefcase", options: projectPickerOptions)
            BookingPickerTextField("Plot available Only", text: $booking.plot, placeholder: "Select Project First", icon: "briefcase", options: plotPickerOptions)
            BookingPickerTextField("Property Type", text: $booking.propertyType, placeholder: "Select Type", icon: "briefcase", options: propertyTypeOptions)
            BookingPickerTextField("Booking Mode", text: $booking.bookingMode, placeholder: "Select Mode", icon: "briefcase", options: bookingModeOptions)
            sectionLabel("Is Against Client Visit")
            HStack(spacing: 12) {
                RadioRow(title: "Yes", isSelected: booking.isAgainstClientVisit) { booking.isAgainstClientVisit = true }
                RadioRow(title: "No (Online Sales)", isSelected: !booking.isAgainstClientVisit) { booking.isAgainstClientVisit = false }
            }
            sectionLabel("Duplicate Bookings")
            RadioRow(title: "Yes", isSelected: booking.duplicateBookings) { booking.duplicateBookings.toggle() }
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
            BookingPickerTextField("Promotional Offers T&C", text: $booking.promotionalOffersTnc, placeholder: "Select Offers", icon: "indianrupeesign", options: promoTncOptions)
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
            BookingPickerTextField("Payment Mode", text: $booking.paymentMode, placeholder: "Select Mode", icon: "info.circle", options: paymentModeOptions)
            Toggle("Flexi Payment", isOn: $booking.flexiPayment)
                .font(.system(size: 13, weight: .medium))
            BookingTextField("Allotment Due Amount", text: $booking.allotmentDueAmount, keyboard: .decimalPad)
            BookingDateTextField("Allotment Due Date", text: $booking.allotmentDueDate)
            BookingTextField("2nd Payment Mode", text: $booking.secondPaymentMode)
            BookingDateTextField("2nd Payment Date", text: $booking.secondPaymentDate)
            BookingTextField("3rd Payment Mode", text: $booking.thirdPaymentMode)
            BookingDateTextField("3rd Payment Date", text: $booking.thirdPaymentDate)
            BookingTextField("4th Payment Mode", text: $booking.fourthPaymentMode)
            BookingDateTextField("4th Payment Date", text: $booking.fourthPaymentDate)
            BookingDateTextField("Preferred Registration Date", text: $booking.preferredRegistrationDate)
        }
    }

    private var bookingStaffFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Booking · Staff Details")
            BookingPickerTextField("AVP", text: $booking.avp, placeholder: "Select", icon: "person", options: staffPickerOptions(fallback: ["AVP A", "AVP B"]))
            BookingPickerTextField("General Manager", text: $booking.generalManager, placeholder: "Select", icon: "person", options: staffPickerOptions(fallback: ["GM A", "GM B"]))
            BookingPickerTextField("Senior Manager", text: $booking.seniorManager, placeholder: "Select", icon: "person", options: staffPickerOptions(fallback: ["SM A", "SM B"]))
            BookingPickerTextField("BDO", text: $booking.bdo, placeholder: "Select", icon: "person", options: staffPickerOptions(fallback: ["BDO A", "BDO B"]))
            BookingPickerTextField("Telecaller", text: $booking.telecaller, placeholder: "Select", icon: "phone", options: staffPickerOptions(fallback: ["Telecaller A", "Telecaller B"]))
            BookingTextField("Aadhar Details", text: $booking.aadhar, placeholder: "Enter Details", icon: "doc", keyboard: .numberPad)
            BookingTextField("Pancard Details", text: $booking.pancard, placeholder: "Enter Details", icon: "doc")
            BookingTextField("Reference Name 1", text: $booking.referenceName1)
            BookingTextField("Reference Mobile 1", text: $booking.referenceMobile1, keyboard: .phonePad)
            BookingTextField("Reference Profession 1", text: $booking.referenceProfession1)
            BookingTextField("Reference Name 2", text: $booking.referenceName2)
            BookingTextField("Reference Mobile 2", text: $booking.referenceMobile2, keyboard: .phonePad)
            BookingTextField("Reference Profession 2", text: $booking.referenceProfession2)
            BookingPickerTextField("Document to be prepared in", text: $booking.documentLanguage, placeholder: "Select", icon: "doc", options: documentLanguageOptions)
            sectionLabel("Save as")
            HStack(spacing: 12) {
                RadioRow(title: "Draft", isSelected: booking.saveAs == .draft) { booking.saveAs = .draft }
                RadioRow(title: "Confirmed", isSelected: booking.saveAs == .confirmed) { booking.saveAs = .confirmed }
            }
        }
    }

    private var postponeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledEditor("Please specify the budget concern", text: $budgetConcern, minLines: 3)
            BookingTextField("What's the timing?", text: $timingNotes, placeholder: "Enter Details", icon: "clock")
            BookingTextField("Tell the Project Details", text: $projectDetails, placeholder: "Enter Details", icon: "clock")
            BookingTextField("Tell Other Details", text: $otherPostponeNotes, placeholder: "Enter Details", icon: "clock")
            DatePicker("Date & Time", selection: $postponeFollowUpDate, displayedComponents: [.date, .hourAndMinute])
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.top, 4)
    }

    private var notInterestedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledEditor("Please specify the budget concern", text: $notInterestedBudgetConcern, minLines: 3)
            BookingTextField("What's the timing?", text: $notInterestedTimingNotes, placeholder: "Enter Details", icon: "clock")
            BookingTextField("Tell the Project Details", text: $notInterestedProjectDetails, placeholder: "Enter Details", icon: "clock")
            BookingTextField("Tell Other Details", text: $notInterestedOtherNotes, placeholder: "Enter Details", icon: "clock")
        }
        .padding(.top, 4)
    }

    private var projectPickerOptions: [String] {
        let loaded = projects.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return loaded.isEmpty ? ["Project A", "Project B", "Project C"] : loaded
    }

    private var plotPickerOptions: [String] {
        ["Plot 101", "Plot 102", "Plot 103"]
    }

    private func staffPickerOptions(fallback: [String]) -> [String] {
        let loaded = salesStaff.map(\.displayName).filter { !$0.isEmpty }
        return loaded.isEmpty ? fallback : loaded
    }

    private var ctaTitle: String {
        if isSaving { return "Saving..." }
        switch selectedOutcome {
        case .booking:
            if bookingStep == .findMobile { return "Next" }
            return bookingSub == .staff ? "Save Booking" : "Next"
        case .siteVisit, .postponed, .notInterested:
            return "Save"
        case nil:
            return "Next"
        }
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

    private func fieldEditor(_ placeholder: String, text: Binding<String>, minLines: Int = 1, label: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                sectionLabel(label)
            }
            TextField(placeholder, text: text, axis: .vertical)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(minLines...max(minLines, 4))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
        }
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
        dismissKeyboard()
        errorMessage = nil
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in"
            return
        }
        guard let selectedOutcome else {
            errorMessage = "Please pick an outcome"
            return
        }
        if selectedOutcome == .booking {
            if bookingStep == .findMobile {
                let mobile = bookingClientMobile.trimmingCharacters(in: .whitespacesAndNewlines)
                guard mobile.count >= 6 else {
                    errorMessage = "Enter a valid mobile number"
                    return
                }
                booking.phone = mobile
                bookingStep = .clientForm
                return
            }
            if bookingSub != .staff {
                bookingSub = bookingSub.next
                return
            }
            guard !booking.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "Client name is required (Client Details tab)"
                return
            }
        }
        if selectedOutcome == .postponed && postponeNotesPayload == nil {
            errorMessage = "Please share at least one reason for the postpone"
            return
        }
        if selectedOutcome == .notInterested && notInterestedNotesPayload == nil {
            errorMessage = "Please share at least one reason"
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
                        postponeReasons: nil,
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func buildOutcomeNotes(for outcome: CpVisitOutcome) -> String? {
        switch outcome {
        case .booking:
            return booking.serializedNotes
        case .postponed:
            return postponeNotesPayload
        case .notInterested:
            return notInterestedNotesPayload
        case .siteVisit:
            return nil
        }
    }

    private var postponeNotesPayload: String? {
        let followUp = DateFormatter.cpOutcomeDateTime.string(from: postponeFollowUpDate)
        return [
            "[Postponed]",
            budgetConcern.nilIfBlank.map { "Budget concern: \($0)" },
            timingNotes.nilIfBlank.map { "Timing: \($0)" },
            projectDetails.nilIfBlank.map { "Project details: \($0)" },
            otherPostponeNotes.nilIfBlank.map { "Other: \($0)" },
            "Follow-up: \(followUp)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        .nilIfBlank
    }

    private var notInterestedNotesPayload: String? {
        let rows = [
            notInterestedBudgetConcern.nilIfBlank.map { "Budget concern: \($0)" },
            notInterestedTimingNotes.nilIfBlank.map { "Timing: \($0)" },
            notInterestedProjectDetails.nilIfBlank.map { "Project details: \($0)" },
            notInterestedOtherNotes.nilIfBlank.map { "Other: \($0)" }
        ]
        .compactMap { $0 }
        guard !rows.isEmpty else { return nil }
        return (["[Not interested]"] + rows).joined(separator: "\n")
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .booking: return "Booking"
        case .siteVisit: return "Site Visit"
        case .postponed: return "Postpone"
        case .notInterested: return "Not Interested"
        }
    }

    var icon: String {
        switch self {
        case .booking: return "checkmark.seal.fill"
        case .siteVisit: return "building.2.fill"
        case .postponed: return "calendar.badge.clock"
        case .notInterested: return "xmark.circle.fill"
        }
    }
}

private enum BookingStep {
    case findMobile
    case clientForm
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
        case .client: return "Client Details"
        case .professional: return "Professional Details"
        case .office: return "Office Details"
        case .booking: return "Booking Details"
        case .charges: return "Charges Details"
        case .payment: return "Payment Details"
        case .staff: return "Staff Details"
        }
    }

    var next: BookingSub {
        switch self {
        case .client: return .professional
        case .professional: return .office
        case .office: return .booking
        case .booking: return .charges
        case .charges: return .payment
        case .payment: return .staff
        case .staff: return .staff
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

    var bookingRefNo = ""
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
            ("Booking Ref No", bookingRefNo),
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

private struct OutcomeTabView: View {
    let outcome: CpVisitOutcome
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0xF8FAFC))
                    .frame(width: 36, height: 36)
                Image(systemName: outcome.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Color(hex: 0x6A6D78))
            }
            Text(outcome.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0x6A6D78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Capsule()
                .fill(isSelected ? Color(hex: 0x0B61CA) : .clear)
                .frame(width: 24, height: 2)
                .padding(.top, 2)
        }
        .frame(height: 62)
    }
}

private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color(hex: 0x475467))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    isSelected
                        ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x1ECB09), Color(hex: 0x3D9D02)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color(hex: 0xF8FAFC)),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? .clear : Color(hex: 0xEAECF0), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct BookingSubTab: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? .white : Color(hex: 0x475467))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                isSelected
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x1ECB09), Color(hex: 0x3D9D02)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color(hex: 0xF8FAFC)),
                in: Capsule()
            )
    }
}

private struct RadioRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0x98A2B3))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct BookingReadonlyField: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x475467))
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(width: 16)
                Text(value.nilIfBlank ?? "-")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct BookingTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let icon: String
    let trailingChevron: Bool
    let keyboard: UIKeyboardType
    let axis: Axis

    init(
        _ title: String,
        text: Binding<String>,
        placeholder: String? = nil,
        icon: String = "square.and.pencil",
        trailingChevron: Bool = false,
        keyboard: UIKeyboardType = .default,
        axis: Axis = .horizontal
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder ?? title
        self.icon = icon
        self.trailingChevron = trailingChevron
        self.keyboard = keyboard
        self.axis = axis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x475467))
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(width: 16)
                TextField(placeholder, text: $text, axis: axis)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                    .autocorrectionDisabled(keyboard == .emailAddress)
                    .lineLimit(axis == .vertical ? 2...4 : 1...1)
                    .font(.system(size: 13, weight: .medium))
                if trailingChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: axis == .vertical ? 72 : 48)
            .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct BookingPickerTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let icon: String
    let options: [String]

    init(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        icon: String,
        options: [String]
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.icon = icon
        self.options = options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x475467))
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        text = option
                    }
                }
            } label: {
                fieldContent
            }
            .buttonStyle(.plain)
        }
    }

    private var fieldContent: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .frame(width: 16)
            Text(text.isEmpty ? placeholder : text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(text.isEmpty ? Color(hex: 0x94A3B8) : Color(hex: 0x101828))
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x667085))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct BookingDateTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    @State private var isPickingDate = false
    @State private var selectedDate = Date()

    init(_ title: String, text: Binding<String>, placeholder: String = "dd/mm/yyyy") {
        self.title = title
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x475467))
            Button {
                selectedDate = Self.dateFormatter.date(from: text) ?? Date()
                isPickingDate = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .frame(width: 16)
                    Text(text.isEmpty ? placeholder : text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(text.isEmpty ? Color(hex: 0x94A3B8) : Color(hex: 0x101828))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $isPickingDate) {
            NavigationStack {
                DatePicker(title, selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isPickingDate = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                text = Self.dateFormatter.string(from: selectedDate)
                                isPickingDate = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()
}

private struct FieldShell<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
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
    func cpFieldStyle(icon: String? = nil) -> some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(width: 16)
            }
            self
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Color(hex: 0xF5F6FA), in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension DateFormatter {
    static let cpOutcomeDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy hh:mm a"
        return formatter
    }()
}
