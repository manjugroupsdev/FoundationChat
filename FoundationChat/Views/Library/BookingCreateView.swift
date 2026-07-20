import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct BookingCreateView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let initialProject: MarketingProject?
    let initialUnit: InventoryUnit?

    @State private var booking = DirectBookingDraft()
    @State private var selectedTab: DirectBookingTab = .client
    @State private var selectedProject: MarketingProject?
    @State private var selectedProjectSpecialPaymentEnabled: Bool?
    @State private var selectedUnit: InventoryUnit?
    @State private var selectedLead: TelecallerLeadSearchData?
    @State private var leadMatches: [TelecallerLeadSearchData] = []
    @State private var projects: [MarketingProject] = []
    @State private var availableUnits: [InventoryUnit] = []
    @State private var staff: [ConvexStaffListItem] = []
    @State private var showProjectPicker = false
    @State private var showUnitPicker = false
    @State private var showLeadPicker = false
    @State private var activeStaffPicker: DirectBookingStaffField?
    @State private var clientImagePickerItem: PhotosPickerItem?
    @State private var isUploadingClientImage = false
    @State private var showAdvanceProofImporter = false
    @State private var showAadhaarImporter = false
    @State private var showPanImporter = false
    @State private var isUploadingDocument = false
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
        _selectedProjectSpecialPaymentEnabled = State(initialValue: initialProject?.specialPaymentEnabled)
        _selectedUnit = State(initialValue: initialUnit)
    }

    private var canCreateBooking: Bool {
        authStore.hasPermission("marketing.bookings.create")
    }

    var body: some View {
        VStack(spacing: 0) {
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }

            fixedFooterAction
        }
        .background(Color.white.ignoresSafeArea())
        .task {
            restoreDraftIfNeeded()
            await loadInitialData()
            await resolveSelectedProjectSpecialPaymentIfNeeded()
        }
        .onDisappear {
            draftSaveTask?.cancel()
        }
        .onChange(of: booking) { _, _ in scheduleDraftAutosave() }
        .onChange(of: booking.customerPaymentCategory) { _, value in
            if value != "B" { booking.loanAmountRequested = "" }
        }
        .onChange(of: booking.paymentPlan) { _, value in
            booking.freePayment = value == "Flexi"
        }
        .onChange(of: booking.profession) { _, value in
            if value != "Salaried" {
                booking.department = ""
                booking.otherDepartment = ""
            }
        }
        .onChange(of: clientImagePickerItem) { _, item in
            Task { await uploadClientImage(item) }
        }
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
        .fileImporter(
            isPresented: $showAdvanceProofImporter,
            allowedContentTypes: [.image, .pdf, .data],
            allowsMultipleSelection: false
        ) { result in
            Task { await importDocument(result, kind: .advanceProof) }
        }
        .fileImporter(
            isPresented: $showAadhaarImporter,
            allowedContentTypes: [.image, .pdf, .data],
            allowsMultipleSelection: false
        ) { result in
            Task { await importDocument(result, kind: .aadhaar) }
        }
        .fileImporter(
            isPresented: $showPanImporter,
            allowedContentTypes: [.image, .pdf, .data],
            allowsMultipleSelection: false
        ) { result in
            Task { await importDocument(result, kind: .pan) }
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

    private var fixedFooterAction: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color(hex: 0xEAECF0))
            footerAction
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .background(Color.white.ignoresSafeArea(edges: .bottom))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("New Booking")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x0F172A))
                .frame(maxWidth: .infinity)

            HStack {
                Text("Booking form")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))

                Spacer()

                Button("Clear") {
                    clearForm()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x20B40B))
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DirectBookingTab.allCases) { tab in
                    Button(tab.title) { selectedTab = tab } 
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? .white : Color(hex: 0x20B40B))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(selectedTab == tab ? Color(hex: 0x20B40B) : Color.white, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedTab == tab ? Color.clear : Color(hex: 0xDDEFE0), lineWidth: 1)
                        )
                }
            }
            .padding(.vertical, 2)
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
                        Text(booking.saveAs.actionTitle)
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
            VStack(alignment: .leading, spacing: 12) {
                clientDetails
                professionalDetails
                officeDetails
            }
        case .bookingFinance:
            VStack(alignment: .leading, spacing: 12) {
                bookingDetails
                sourceReferralDetails
                chargesDetails
                chargesAndAdvanceDetails
            }
        case .paymentStaff:
            VStack(alignment: .leading, spacing: 12) {
                paymentDetails
                staffDetails
            }
        }
    }

    private var clientDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingTextField("Client Phone Number *", text: $booking.phone, placeholder: "Enter Mobile Number", icon: "phone", keyboard: .phonePad)
                .onChange(of: booking.phone) { _, value in
                    booking.phone = String(value.filter(\.isNumber).prefix(10))
                    if booking.whatsappSameAsMobile { booking.whatsappNumber = booking.phone }
                    Task { await lookupLeadIfNeeded(phone: AppModuleFormatters.normalizePhone(value)) }
                }
            leadLookupStatus
            DirectBookingPicker("Title", value: $booking.title, placeholder: "Select Title", icon: "person", options: ["Mr", "Mrs", "Ms", "Dr", "Prof"])
            DirectBookingTextField("Client Name *", text: $booking.name, placeholder: "Enter Client Name", icon: "person")
            clientImageUploadCard
            DirectBookingTextField("Father/Spouse Name", text: $booking.fatherSpouseName, placeholder: "Enter Name", icon: "person")
            DirectBookingDateField("Date of Birth", text: $booking.dateOfBirth)
            DirectBookingDateField("Anniversary Date", text: $booking.anniversaryDate)
            DirectBookingTextField("Alternate Numbers", text: $booking.alternateNumbers, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            DirectBookingTextField("WhatsApp Number", text: $booking.whatsappNumber, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            androidCheckRow("WhatsApp Number", isOn: $booking.whatsappSameAsMobile, onText: "Same as personal mobile")
                .onChange(of: booking.whatsappSameAsMobile) { _, same in
                    if same { booking.whatsappNumber = booking.phone }
                }
            DirectBookingTextField("Email", text: $booking.email, placeholder: "Enter Email Id", icon: "envelope", keyboard: .emailAddress)
            DirectBookingPicker("Nationality", value: $booking.nationality, placeholder: "Select Nationality", icon: "globe", options: ["Indian", "NRI", "Foreign"])
            DirectBookingTextField("Home Address", text: $booking.homeAddress, placeholder: "Enter Address", icon: "mappin", axis: .vertical)
            DirectBookingTextField("Pincode", text: $booking.pincode, placeholder: "Enter Pincode", icon: "mappin", keyboard: .numberPad)
            DirectBookingTextField("State", text: $booking.state, placeholder: "Enter State", icon: "mappin")
            DirectBookingTextField("District", text: $booking.district, placeholder: "Enter District", icon: "mappin")
            DirectBookingTextField("Location", text: $booking.location, placeholder: "Enter Location", icon: "mappin")
            DirectBookingTextField("Latitude", text: $booking.latitude, placeholder: "Optional map latitude", icon: "location", keyboard: .decimalPad)
            DirectBookingTextField("Longitude", text: $booking.longitude, placeholder: "Optional map longitude", icon: "location", keyboard: .decimalPad)
            DirectBookingTextField("Google Maps Link", text: $booking.googleMapsLink, placeholder: "Paste map link", icon: "link", keyboard: .URL)
        }
    }

    private var clientImageUploadCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Client Image")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))
            PhotosPicker(selection: $clientImagePickerItem, matching: .images) {
                HStack(spacing: 12) {
                    Image(systemName: booking.clientImageStorageId.directBookingNilIfBlank == nil ? "photo.badge.plus" : "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(booking.clientImageStorageId.directBookingNilIfBlank == nil ? Color(hex: 0x0B61CA) : Color(hex: 0x18B400))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isUploadingClientImage ? "Uploading client image..." : (booking.clientImageFileName.directBookingNilIfBlank ?? "Upload client photo"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x101828))
                            .lineLimit(1)
                        Text("Optional profile photo for the client")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0x667085))
                            .lineLimit(1)
                    }
                    Spacer()
                    if isUploadingClientImage {
                        ProgressView()
                            .controlSize(.small)
                    } else if booking.clientImageStorageId.directBookingNilIfBlank != nil {
                        Button {
                            booking.clientImageStorageId = ""
                            booking.clientImageFileName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x98A2B3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                        .foregroundStyle(Color(hex: 0xD0D5DD))
                )
            }
            .disabled(isUploadingClientImage)
        }
    }

    private func bookingDocumentUploadCard(
        title: String,
        fileName: String,
        isUploaded: Bool,
        onSelect: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))
            HStack(spacing: 10) {
                Image(systemName: isUploaded ? "checkmark.circle.fill" : "doc.badge.plus")
                    .foregroundStyle(isUploaded ? Color(hex: 0x18B400) : Color(hex: 0x0B61CA))
                Text(fileName.directBookingNilIfBlank ?? (isUploadingDocument ? "Uploading..." : "Select image or PDF"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                Spacer()
                if isUploadingDocument {
                    ProgressView().controlSize(.small)
                } else if isUploaded {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Choose", action: onSelect)
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }

    private var professionalDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingPicker("Profession", value: $booking.profession, placeholder: "Select Profession", icon: "briefcase", options: ["Business", "Salaried", "Pension"])
            DirectBookingTextField("Designation", text: $booking.designation, placeholder: "Enter Designation", icon: "person")
            if booking.profession == "Salaried" {
                DirectBookingPicker("Department", value: $booking.department, placeholder: "Select Department", icon: "building.2", options: ["Admin", "Sales", "HR", "Software Developer", "Other"])
                if booking.department == "Other" {
                    DirectBookingTextField("Other Department", text: $booking.otherDepartment, placeholder: "Enter Department", icon: "building.2")
                }
            }
            DirectBookingTextField("Income Per Annum", text: $booking.incomePerAnnum, placeholder: "Enter Income", icon: "indianrupeesign", keyboard: .decimalPad)
        }
    }

    private var officeDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingTextField("Office Name", text: $booking.officeName, placeholder: "Enter Name", icon: "building.2")
            DirectBookingTextField("Office Email", text: $booking.officeEmail, placeholder: "Enter Email", icon: "envelope", keyboard: .emailAddress)
            DirectBookingTextField("Office Mobile", text: $booking.officeMobile, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            DirectBookingTextField("Office Phone", text: $booking.officePhone, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            sectionTitle("Office Address")
            DirectBookingTextField("Door No", text: $booking.officeDoorNo, placeholder: "Enter door / floor number", icon: "door.left.hand.open")
            DirectBookingTextField("Street Name", text: $booking.officeStreetName, placeholder: "Enter street name", icon: "road.lanes")
            DirectBookingTextField("Address Line 1", text: $booking.officeAddressLine1, placeholder: "Enter address line 1", icon: "mappin")
            DirectBookingTextField("Address Line 2", text: $booking.officeAddressLine2, placeholder: "Enter address line 2", icon: "mappin")
            DirectBookingTextField("Office Area", text: $booking.officeArea, placeholder: "Enter Area", icon: "mappin")
            DirectBookingTextField("Office Pincode", text: $booking.officePincode, placeholder: "6-digit pincode", icon: "mappin", keyboard: .numberPad)
        }
    }

    private var bookingDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingPickerShell(title: "Booking Ref No", value: "Auto", icon: "number")
            DirectBookingPicker("Booking Type", value: $booking.bookingType, placeholder: "Select Type", icon: "briefcase", options: ["NEW", "CONVERSION", "EXCHANGE", "INTERNAL EXCHANGE"])
            conversionAndExchangeDetails
            DirectBookingTextField("CEF No", text: $booking.cefNo, placeholder: "Enter Number", icon: "doc")
            DirectBookingDateField("Booking Date *", text: $booking.bookingDate, defaultsToToday: true)
            DirectBookingPickerButton(title: "Project *", value: selectedProject?.name ?? booking.projectName, placeholder: "Select Project", icon: "briefcase") {
                Task { await loadProjectsThenShowPicker() }
            }
            DirectBookingPickerButton(title: "Plot (available only) *", value: selectedUnit?.unitNumber ?? booking.plotNo, placeholder: "Select Project First", icon: "square") {
                Task { await loadUnitsThenShowPicker() }
            }
            DirectBookingPicker("Property Type", value: $booking.propertyType, placeholder: "Select Type", icon: "building.2", options: ["Plot", "Apartment", "Villa", "Commercial"])
            androidCheckRow("Duplicate Bookings", isOn: $booking.isDuplicateBooking, onText: "Yes")
        }
    }

    private var sourceReferralDetails: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Source / Referral")
                DirectBookingPicker("Client Source", value: $booking.clientSource, placeholder: "Select Source", icon: "person.2", options: ["Direct / Walk-in", "Reference", "Channel Partner", "Site Visit", "Online / Social Media", "Other"])
                DirectBookingTextField("Source / Reference Name", text: $booking.clientSourceName, placeholder: "Name, CP, or campaign", icon: "person")
                DirectBookingTextField("Source / Reference Mobile", text: $booking.clientSourceMobile, placeholder: "Mobile number", icon: "phone", keyboard: .phonePad)
                DirectBookingTextField("Referral Benefit", text: $booking.referralBenefit, placeholder: "If any", icon: "gift")
                androidCheckRow("Is Against Site Visit?", isOn: $booking.isAgainstSV, onText: "Yes", offText: "No (Online Sales)")
                siteVisitDetails
            }
        )
    }

    private var siteVisitDetails: AnyView {
        guard booking.isAgainstSV else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                DirectBookingTextField("SV Name", text: $booking.svName, placeholder: "Enter Site Visit Name", icon: "person")
                DirectBookingTextField("SV Mobile No.", text: $booking.svMobileNo, placeholder: "Enter Mobile Number", icon: "phone", keyboard: .phonePad)
            }
        )
    }

    // Type erasure keeps this large conditional form from producing a deeply
    // nested SwiftUI generic type. On physical devices that type previously
    // overflowed the Swift metadata stack as soon as this tab was displayed.
    private var conversionAndExchangeDetails: AnyView {
        switch booking.bookingType {
        case "CONVERSION":
            return AnyView(conversionDetails)
        case "EXCHANGE", "INTERNAL EXCHANGE":
            return AnyView(exchangeDetails)
        default:
            return AnyView(EmptyView())
        }
    }

    private var conversionDetails: AnyView {
        if booking.conversionManualEntry {
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    androidCheckRow("Conversion Source", isOn: $booking.conversionManualEntry, onText: "Manual previous booking entry", offText: "Linked previous booking")
                    DirectBookingTextField("Previous Project", text: $booking.manualConversionProjectName, placeholder: "Enter previous project name", icon: "building.2")
                    DirectBookingTextField("Previous Plot", text: $booking.manualConversionPlotNo, placeholder: "Enter previous plot number", icon: "square")
                    DirectBookingTextField("Conversion Credit", text: $booking.manualConversionCredit, placeholder: "Amount paid on previous booking", icon: "indianrupeesign", keyboard: .decimalPad)
                    DirectBookingTextField("Conversion Notes", text: $booking.conversionNotes, placeholder: "Details about the previous booking", icon: "doc", axis: .vertical)
                }
            )
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                androidCheckRow("Conversion Source", isOn: $booking.conversionManualEntry, onText: "Manual previous booking entry", offText: "Linked previous booking")
                DirectBookingTextField("Previous Booking ID", text: $booking.sourceExchangeBookingId, placeholder: "Linked booking ID", icon: "link")
            }
        )
    }

    private var exchangeDetails: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 10) {
                androidCheckRow("Exchange Source", isOn: $booking.exchangeManualEntry, onText: "Manual old property entry", offText: "Linked old property")
                exchangeSourceDetails
                DirectBookingTextField("Exchange Value", text: $booking.exchangeOldRegisteredValue, placeholder: "Old property value", icon: "indianrupeesign", keyboard: .decimalPad)
                if booking.bookingType == "EXCHANGE" {
                    DirectBookingPickerShell(title: "Balance Payable", value: AppModuleFormatters.rupees(booking.exchangeBalancePayable), icon: "indianrupeesign")
                }
                DirectBookingTextField("Exchange Notes", text: $booking.exchangeNotes, placeholder: "Details about the exchanged property", icon: "doc", axis: .vertical)
            }
        )
    }

    private var exchangeSourceDetails: AnyView {
        if booking.exchangeManualEntry {
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    DirectBookingTextField("Old Project Name", text: $booking.manualExchangeProjectName, placeholder: "Enter old project name", icon: "building.2")
                    DirectBookingTextField("Old Plot Number", text: $booking.manualExchangePlotNo, placeholder: "Enter old plot number", icon: "square")
                    DirectBookingTextField("Extent (Sq. Ft.)", text: $booking.manualExchangeExtentSqft, placeholder: "Old property extent", icon: "ruler", keyboard: .decimalPad)
                }
            )
        }
        if booking.bookingType == "INTERNAL EXCHANGE" {
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    DirectBookingTextField("Old Project ID", text: $booking.exchangeLookupProjectId, placeholder: "Linked old project ID", icon: "building.2")
                    DirectBookingTextField("Old Plot Number", text: $booking.exchangeLookupPlotNo, placeholder: "Old plot", icon: "square")
                    DirectBookingTextField("Connected Mobile Number", text: $booking.exchangeConnectedMobileNumber, placeholder: "10-digit booked mobile", icon: "phone", keyboard: .phonePad)
                    DirectBookingTextField("Source Booking ID", text: $booking.sourceExchangeBookingId, placeholder: "Matched booking ID", icon: "link")
                }
            )
        }
        return AnyView(
            DirectBookingTextField("Exchanged Property Booking ID", text: $booking.sourceExchangeBookingId, placeholder: "Linked confirmed booking ID", icon: "link")
        )
    }

    private var chargesDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingTextField("Booking Cost", text: $booking.bookingCost, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("Guideline Value", text: $booking.guidelineValue, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("Special Consideration", text: $booking.specialConsideration, placeholder: "Discount amount", icon: "indianrupeesign", keyboard: .decimalPad)
            if (Double(booking.specialConsideration) ?? 0) > 0 {
                DirectBookingTextField("Discount Approved By", text: $booking.discountApprovedBy, placeholder: "AVP or GM name", icon: "person")
                DirectBookingTextField("SC Reason", text: $booking.specialConsiderationReason, placeholder: "Enter Details", icon: "doc", axis: .vertical)
                DirectBookingTextField("SC Validity", text: $booking.specialConsiderationValidity, placeholder: "Enter Days", icon: "calendar", keyboard: .numberPad)
            }
            if let agreedAmount = booking.agreedAmount {
                DirectBookingPickerShell(title: "Agreed Amount", value: AppModuleFormatters.rupees(agreedAmount), icon: "indianrupeesign")
            }
            DirectBookingTextField("Promotional Offers", text: $booking.promotionalOffers, placeholder: "Enter Details", icon: "tag", axis: .vertical)
            DirectBookingPicker("Promotional Offers T&C", value: $booking.promotionalOffersTnC, placeholder: "Select Timeline", icon: "doc", options: ["7days", "15days", "30days"])
                .onChange(of: booking.promotionalOffersTnC) { _, value in
                    booking.offerValidityPeriod = String(value.filter(\.isNumber))
                }
            DirectBookingTextField("Promotional Offer Value", text: $booking.promotionalOfferValue, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("Offer Validity Period", text: $booking.offerValidityPeriod, placeholder: "Enter Days", icon: "calendar", keyboard: .numberPad)
        }
    }

    private var chargesAndAdvanceDetails: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Charges & Advance")
                DirectBookingTextField("Registration Charges", text: $booking.registrationCharges, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
                DirectBookingTextField("GST Amount", text: $booking.gstAmount, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
                androidCheckRow("GST Applicable", isOn: $booking.gstApplicable, onText: "Applicable", offText: "Not Applicable")
                DirectBookingTextField("Document Charges", text: $booking.documentCharges, placeholder: "Enter Cost", icon: "doc", keyboard: .decimalPad)
                DirectBookingTextField("Patta Charges", text: $booking.pattaCharges, placeholder: "Enter Cost", icon: "doc", keyboard: .decimalPad)
                DirectBookingTextField("Other Charges", text: $booking.otherCharges, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
                androidCheckRow("Other Charges Applicable", isOn: $booking.otherChargesApplicable, onText: "Applicable", offText: "Not Applicable")

                sectionTitle("Customer Funding")
                DirectBookingOptionPicker("Customer Payment Category", value: $booking.customerPaymentCategory, placeholder: "Select Category", icon: "creditcard", options: Self.customerPaymentCategoryOptions)
                customerLoanDetails
                DirectBookingPicker("Advance Booking Payment", value: $booking.bookingMode, placeholder: "Select Payment Method", icon: "creditcard", options: ["CASH", "UPI", "NEFT", "RTGS", "CHEQUE", "DD"])
                DirectBookingTextField("Advance Amount", text: $booking.advanceAmount, placeholder: "Enter Amount", icon: "indianrupeesign", keyboard: .decimalPad)
                advancePaymentDetails
            }
        )
    }

    private var customerLoanDetails: AnyView {
        guard booking.customerPaymentCategory == "B" else { return AnyView(EmptyView()) }
        return AnyView(
            DirectBookingTextField("Loan Amount Required", text: $booking.loanAmountRequested, placeholder: "Amount customer wants as loan", icon: "doc", keyboard: .decimalPad)
        )
    }

    private var advancePaymentDetails: AnyView {
        if ["UPI", "NEFT", "RTGS"].contains(booking.bookingMode) {
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    DirectBookingTextField("Transaction ID", text: $booking.advanceTransactionId, placeholder: "UTR / Ref no", icon: "number")
                    bookingDocumentUploadCard(
                        title: "Payment Proof",
                        fileName: booking.advancePaymentProofFileName,
                        isUploaded: booking.advancePaymentProofStorageId.directBookingNilIfBlank != nil,
                        onSelect: { showAdvanceProofImporter = true },
                        onRemove: {
                            booking.advancePaymentProofStorageId = ""
                            booking.advancePaymentProofFileName = ""
                        }
                    )
                }
            )
        }
        if ["CHEQUE", "DD"].contains(booking.bookingMode) {
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    DirectBookingTextField(booking.bookingMode == "DD" ? "DD No" : "Cheque No", text: $booking.advanceInstrumentNo, placeholder: "Enter instrument number", icon: "number")
                    DirectBookingTextField("Bank", text: $booking.advanceBankName, placeholder: "Enter bank", icon: "building.columns")
                    DirectBookingTextField("Branch", text: $booking.advanceBankBranch, placeholder: "Enter branch", icon: "building.2")
                    DirectBookingDateField("Instrument Date", text: $booking.advanceInstrumentDate)
                }
            )
        }
        return AnyView(EmptyView())
    }

    private var paymentDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Payment Schedule")
            DirectBookingOptionPicker("Payment Plan", value: $booking.paymentPlan, placeholder: "Select Plan", icon: "calendar", options: paymentPlanOptions)
            DirectBookingTextField("Allotment Due Amount", text: $booking.allotmentDueAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingDateField("Allotment Due Date", text: $booking.allotmentDueDate, maxDate: paymentDateLimit(days: 10))
            if booking.freePayment {
                HStack {
                    sectionTitle("Flexi Payment Schedule")
                    Spacer()
                    Button("Add Payment", systemImage: "plus") {
                        booking.flexiPaymentRows.append(DirectBookingPaymentDraft())
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.bordered)
                    .tint(Color(hex: 0x2DAE12))
                }
                ForEach(Array(booking.flexiPaymentRows.indices), id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(ordinalPaymentLabel(index + 2))
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            Button(role: .destructive) {
                                if booking.flexiPaymentRows.count == 1 {
                                    booking.flexiPaymentRows[0] = DirectBookingPaymentDraft()
                                } else {
                                    booking.flexiPaymentRows.remove(at: index)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        DirectBookingTextField(
                            "\(ordinalPaymentLabel(index + 2)) Payment Amount",
                            text: Binding(
                                get: { booking.flexiPaymentRows[index].amount },
                                set: { booking.flexiPaymentRows[index].amount = $0 }
                            ),
                            placeholder: "Enter Cost",
                            icon: "indianrupeesign",
                            keyboard: .decimalPad
                        )
                        DirectBookingDateField(
                            "\(ordinalPaymentLabel(index + 2)) Payment Date",
                            text: Binding(
                                get: { booking.flexiPaymentRows[index].dueDate },
                                set: { booking.flexiPaymentRows[index].dueDate = $0 }
                            ),
                            maxDate: paymentDateLimit(days: paymentPlanDays)
                        )
                    }
                    .padding(12)
                    .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                DirectBookingTextField("2nd Payment Amount", text: $booking.secondPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
                DirectBookingDateField("2nd Payment Date", text: $booking.secondPaymentDate, maxDate: paymentDateLimit(days: paymentPlanDays))
                DirectBookingTextField("3rd Payment Amount", text: $booking.thirdPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
                DirectBookingDateField("3rd Payment Date", text: $booking.thirdPaymentDate, maxDate: paymentDateLimit(days: paymentPlanDays))
                DirectBookingTextField("4th Payment Amount", text: $booking.fourthPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
                DirectBookingDateField("4th Payment Date", text: $booking.fourthPaymentDate, maxDate: paymentDateLimit(days: paymentPlanDays))
            }
            DirectBookingDateField("Preferred Registration Date", text: $booking.preferredRegistrationDate)
        }
    }

    private var staffDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            staffPicker(.avp)
            staffPicker(.generalManager)
            staffPicker(.seniorManager)
            staffPicker(.bdo)
            staffPicker(.telecaller)
            DirectBookingTextField("Aadhar Details", text: $booking.aadhaar, placeholder: "Enter Details", icon: "doc", keyboard: .numberPad)
                .onChange(of: booking.aadhaar) { _, value in
                    booking.aadhaar = String(value.filter(\.isNumber).prefix(12))
                }
            bookingDocumentUploadCard(
                title: "Aadhaar Upload",
                fileName: booking.aadhaarDocumentFileName,
                isUploaded: booking.aadhaarDocumentStorageId.directBookingNilIfBlank != nil,
                onSelect: { showAadhaarImporter = true },
                onRemove: {
                    booking.aadhaarDocumentStorageId = ""
                    booking.aadhaarDocumentFileName = ""
                }
            )
            DirectBookingTextField("Pancard Details", text: $booking.pan, placeholder: "Enter Details", icon: "doc")
                .onChange(of: booking.pan) { _, value in
                    booking.pan = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(10))
                }
            bookingDocumentUploadCard(
                title: "PAN Upload",
                fileName: booking.panDocumentFileName,
                isUploaded: booking.panDocumentStorageId.directBookingNilIfBlank != nil,
                onSelect: { showPanImporter = true },
                onRemove: {
                    booking.panDocumentStorageId = ""
                    booking.panDocumentFileName = ""
                }
            )
            DirectBookingTextField("Reference Name 1", text: $booking.referenceName1, placeholder: "Enter Name", icon: "person")
            DirectBookingTextField("Reference Mobile 1", text: $booking.referenceMobile1, placeholder: "Enter No", icon: "phone", keyboard: .phonePad)
            DirectBookingPicker("Reference Relation 1", value: $booking.referenceProfession1, placeholder: "Select Relation", icon: "person.2", options: Self.referenceRelationOptions)
            DirectBookingTextField("Reference Name 2", text: $booking.referenceName2, placeholder: "Enter Name", icon: "person")
            DirectBookingTextField("Reference Mobile 2", text: $booking.referenceMobile2, placeholder: "Enter No", icon: "phone", keyboard: .phonePad)
            DirectBookingPicker("Reference Relation 2", value: $booking.referenceProfession2, placeholder: "Select Relation", icon: "person.2", options: Self.referenceRelationOptions)
            DirectBookingPicker("Document to be prepared in", value: $booking.docPreparedIn, placeholder: "Select", icon: "doc", options: ["English", "Kannada", "Tamil", "Telugu", "Hindi"])
            Picker("Save as", selection: $booking.saveAs) {
                Text("Draft").tag(DirectBookingSaveAs.draft)
                Text("Confirmed").tag(DirectBookingSaveAs.confirmed)
                Text("Cancelled").tag(DirectBookingSaveAs.cancelled)
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

    private func staffPicker(_ field: DirectBookingStaffField) -> some View {
        Button {
            activeStaffPicker = field
        } label: {
            DirectBookingPickerShell(
                title: field.title,
                value: staff.first { $0.id == staffSelection(for: field) }?.displayName ?? "Select",
                icon: "person"
            )
        }
        .buttonStyle(.plain)
    }

    private func staffSelection(for field: DirectBookingStaffField) -> String {
        switch field {
        case .avp: booking.originalAvpStaffId
        case .generalManager: booking.originalGmStaffId
        case .seniorManager: booking.originalSeniorManagerStaffId
        case .bdo: booking.originalBdoStaffId
        case .telecaller: booking.originalTelecallerStaffId
        }
    }

    private func setStaffSelection(_ id: String, for field: DirectBookingStaffField) {
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
                selectedProjectSpecialPaymentEnabled = project.specialPaymentEnabled
                booking.projectId = project.id
                booking.projectName = project.name ?? ""
                selectedUnit = nil
                booking.plotId = ""
                booking.plotNo = ""
                if booking.paymentPlan == "Special", project.specialPaymentEnabled == false {
                    booking.paymentPlan = "Regular"
                }
                showProjectPicker = false
                Task { await resolveSelectedProjectSpecialPaymentIfNeeded() }
            }
        )
        .appLibraryNativeSheet([.medium, .large])
    }

    private var unitPickerSheet: some View {
        NativeSearchableSelectionSheet(
            title: "Select Plot",
            prompt: "Search plots",
            items: availableUnits,
            selectedId: selectedUnit?.id,
            searchText: { unit in
                [unit.unitNumber, unit.status].compactMap(\.self).joined(separator: " ")
            },
            rowContent: { unit, isSelected in
                selectionRow(
                    title: unit.unitNumber ?? "Unit",
                    subtitle: unit.status,
                    isSelected: isSelected
                )
            },
            onSelect: { unit in
                guard unit.status == "available" else {
                    errorMessage = "Unit is no longer available"
                    return
                }
                selectedUnit = unit
                booking.plotId = unit.id
                booking.plotNo = unit.unitNumber ?? ""
                showUnitPicker = false
            }
        )
        .appLibraryNativeSheet([.medium, .large])
    }

    private var leadPickerSheet: some View {
        NativeSearchableSelectionSheet(
            title: "Select Linked Lead",
            prompt: "Search leads",
            items: leadMatches,
            selectedId: selectedLead?.id,
            searchText: { lead in
                [lead.displayName, lead.mobileNumber].compactMap(\.self).joined(separator: " ")
            },
            rowContent: { lead, isSelected in
                selectionRow(
                    title: lead.displayName,
                    subtitle: lead.mobileNumber ?? "No phone",
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
                    .foregroundStyle(Color(hex: 0x101828))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppModuleFont.rowMeta)
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
        if selectedProject == nil, let projectId = booking.projectId.directBookingNilIfBlank {
            selectedProject = projects.first { $0.id == projectId }
            selectedProjectSpecialPaymentEnabled = selectedProject?.specialPaymentEnabled
        }
        if selectedUnit == nil, let plotId = booking.plotId.directBookingNilIfBlank {
            selectedUnit = try? await MarketingConvexAPIService.getInventoryUnit(token: token, id: plotId)
        }
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
    private func uploadClientImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Session expired. Please login again."
            return
        }
        isUploadingClientImage = true
        defer {
            isUploadingClientImage = false
            clientImagePickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Could not read selected image."
                return
            }
            let storageId = try await HRConvexAPIService.uploadPhoto(token: token, imageData: data)
            booking.clientImageStorageId = storageId
            booking.clientImageFileName = "client-photo.jpg"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importDocument(_ result: Result<[URL], Error>, kind: DirectBookingUploadKind) async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Session expired. Please login again."
            return
        }
        do {
            guard let url = try result.get().first else { return }
            isUploadingDocument = true
            defer { isUploadingDocument = false }
            let uploaded = try await PostSalesStorageService.uploadFile(token: token, fileURL: url)
            switch kind {
            case .advanceProof:
                booking.advancePaymentProofStorageId = uploaded.storageId
                booking.advancePaymentProofFileName = uploaded.fileName
            case .aadhaar:
                booking.aadhaarDocumentStorageId = uploaded.storageId
                booking.aadhaarDocumentFileName = uploaded.fileName
            case .pan:
                booking.panDocumentStorageId = uploaded.storageId
                booking.panDocumentFileName = uploaded.fileName
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func resolveSelectedProjectSpecialPaymentIfNeeded() async {
        guard selectedProjectSpecialPaymentEnabled == nil else { return }
        guard let token = authStore.currentSession?.token, let project = selectedProject else { return }
        do {
            let detail = try await ProjectConvexAPIService.getProjectDetail(token: token, id: project.id)
            guard selectedProject?.id == project.id else { return }
            selectedProjectSpecialPaymentEnabled = detail.specialPaymentEnabled
            if booking.paymentPlan == "Special", detail.specialPaymentEnabled != true {
                booking.paymentPlan = "Regular"
            }
        } catch {
            // Keep the trimmed project response behavior if the detail fallback is unavailable.
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
        booking.email = lead.emailId?.directBookingNilIfBlank ?? booking.email
        booking.alternateNumbers = lead.latestAnalysisProfile?.alternateMobileNumber?.directBookingNilIfBlank ?? booking.alternateNumbers
        booking.homeAddress = lead.suggestedVisitAddress?.directBookingNilIfBlank ?? lead.latestAnalysisProfile?.address?.directBookingNilIfBlank ?? booking.homeAddress
        booking.pincode = lead.latestAnalysisProfile?.pincode?.directBookingNilIfBlank ?? booking.pincode
        booking.state = lead.latestAnalysisProfile?.state?.directBookingNilIfBlank ?? booking.state
        booking.district = lead.latestAnalysisProfile?.district?.directBookingNilIfBlank ?? booking.district
        booking.location = lead.locationPreferred?.directBookingNilIfBlank ?? booking.location
        booking.latitude = lead.suggestedVisitLat.map { String($0) } ?? booking.latitude
        booking.longitude = lead.suggestedVisitLng.map { String($0) } ?? booking.longitude
        booking.googleMapsLink = lead.suggestedGoogleMapsLink?.directBookingNilIfBlank ?? booking.googleMapsLink
        booking.propertyType = lead.latestAnalysisProfile?.propertyType?.directBookingNilIfBlank ?? booking.propertyType
        if booking.isAgainstSV {
            booking.svName = booking.svName.directBookingNilIfBlank ?? lead.displayName
            booking.svMobileNo = booking.svMobileNo.directBookingNilIfBlank ?? AppModuleFormatters.normalizePhone(lead.mobileNumber ?? "")
        }
    }

    @MainActor
    private func submit() async {
        let mobile = AppModuleFormatters.normalizePhone(booking.phone)
        if let validation = bookingValidationError(mobile: mobile) {
            errorMessage = validation.message
            selectedTab = validation.tab
            return
        }
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

    private func bookingValidationError(mobile: String) -> (message: String, tab: DirectBookingTab)? {
        let required: [(String, String, DirectBookingTab)] = [
            ("Mobile Number", mobile, .client),
            ("Title", booking.title, .client),
            ("Client Name", booking.name, .client),
            ("Father / Spouse Name", booking.fatherSpouseName, .client),
            ("Date of Birth", booking.dateOfBirth, .client),
            ("Alternate Numbers", booking.alternateNumbers, .client),
            ("WhatsApp Number", booking.whatsappNumber, .client),
            ("Email", booking.email, .client),
            ("Nationality", booking.nationality, .client),
            ("Home Address", booking.homeAddress, .client),
            ("Pincode", booking.pincode, .client),
            ("District", booking.district, .client),
            ("Profession", booking.profession, .client),
            ("Designation", booking.designation, .client),
            ("Income Per Annum", booking.incomePerAnnum, .client),
            ("Office Name", booking.officeName, .client),
            ("Office Door No", booking.officeDoorNo, .client),
            ("Office Street Name", booking.officeStreetName, .client),
            ("Office Address Line 1", booking.officeAddressLine1, .client),
            ("Booking Type", booking.bookingType, .bookingFinance),
            ("CEF No", booking.cefNo, .bookingFinance),
            ("Booking Date", booking.bookingDate, .bookingFinance),
            ("Project", selectedProject?.id ?? booking.projectId, .bookingFinance),
            ("Plot", selectedUnit?.id ?? booking.plotId, .bookingFinance),
            ("Property Type", booking.propertyType, .bookingFinance),
            ("Advance Booking Payment", booking.bookingMode, .bookingFinance),
            ("Booking Cost", booking.bookingCost, .bookingFinance),
            ("Guideline Value", booking.guidelineValue, .bookingFinance),
            ("Promotional Offers", booking.promotionalOffers, .bookingFinance),
            ("Promotional Offers T & C", booking.promotionalOffersTnC, .bookingFinance),
            ("Promotional Offer Value", booking.promotionalOfferValue, .bookingFinance),
            ("Registration Charges", booking.registrationCharges, .bookingFinance),
            ("GST Amount", booking.gstAmount, .bookingFinance),
            ("Document Charges", booking.documentCharges, .bookingFinance),
            ("Patta Charges", booking.pattaCharges, .bookingFinance),
            ("Other Charges", booking.otherCharges, .bookingFinance),
            ("Advance Amount", booking.advanceAmount, .bookingFinance),
            ("Customer Payment Category", booking.customerPaymentCategory, .bookingFinance),
            ("Allotment Due Amount", booking.allotmentDueAmount, .paymentStaff),
            ("Allotment Due Date", booking.allotmentDueDate, .paymentStaff),
            ("Preferred Registration Date", booking.preferredRegistrationDate, .paymentStaff),
            ("AVP", booking.originalAvpStaffId, .paymentStaff),
            ("General Manager", booking.originalGmStaffId, .paymentStaff),
            ("Senior Manager", booking.originalSeniorManagerStaffId, .paymentStaff),
            ("BDO", booking.originalBdoStaffId, .paymentStaff),
            ("Telecaller", booking.originalTelecallerStaffId, .paymentStaff),
            ("Aadhaar Number", booking.aadhaar, .paymentStaff),
            ("Aadhaar Upload", booking.aadhaarDocumentStorageId, .paymentStaff),
            ("PAN Number", booking.pan, .paymentStaff),
            ("PAN Upload", booking.panDocumentStorageId, .paymentStaff),
            ("Reference 1 — Name", booking.referenceName1, .paymentStaff),
            ("Reference 1 — Relation", booking.referenceProfession1, .paymentStaff),
            ("Reference 1 — Mobile", booking.referenceMobile1, .paymentStaff),
            ("Reference 2 — Name", booking.referenceName2, .paymentStaff),
            ("Reference 2 — Relation", booking.referenceProfession2, .paymentStaff),
            ("Reference 2 — Mobile", booking.referenceMobile2, .paymentStaff),
            ("Document to be Prepared In", booking.docPreparedIn, .paymentStaff)
        ]
        if let missing = required.first(where: { $0.1.directBookingNilIfBlank == nil }) {
            return ("\(missing.0) is required", missing.2)
        }
        if !leadMatches.isEmpty, selectedLead == nil {
            return ("Linked Lead is required", .client)
        }
        if booking.profession == "Salaried" {
            let department = booking.department == "Other" ? booking.otherDepartment : booking.department
            if department.directBookingNilIfBlank == nil { return ("Department is required", .client) }
        }
        for (label, value) in [("Mobile Number", mobile), ("Alternate Numbers", booking.alternateNumbers), ("WhatsApp Number", booking.whatsappNumber)] {
            if AppModuleFormatters.normalizePhone(value).count != 10 {
                return ("\(label) must be exactly 10 digits", .client)
            }
        }
        if booking.aadhaar.filter(\.isNumber).count != 12 { return ("Aadhaar Number must be exactly 12 digits", .paymentStaff) }

        if booking.bookingType == "CONVERSION", booking.conversionManualEntry {
            if booking.manualConversionProjectName.directBookingNilIfBlank == nil { return ("Manual Previous Project is required", .bookingFinance) }
            if booking.manualConversionPlotNo.directBookingNilIfBlank == nil { return ("Manual Previous Plot is required", .bookingFinance) }
            if (Double(booking.manualConversionCredit) ?? 0) <= 0 { return ("Manual Conversion Credit is required", .bookingFinance) }
        }
        if booking.bookingType == "EXCHANGE" || booking.bookingType == "INTERNAL EXCHANGE" {
            if booking.exchangeManualEntry {
                if booking.manualExchangeProjectName.directBookingNilIfBlank == nil { return ("Manual Old Project Name is required", .bookingFinance) }
                if booking.manualExchangePlotNo.directBookingNilIfBlank == nil { return ("Manual Old Plot Number is required", .bookingFinance) }
            } else {
                if booking.bookingType == "INTERNAL EXCHANGE" {
                    if booking.exchangeLookupProjectId.directBookingNilIfBlank == nil { return ("Old Project Name is required", .bookingFinance) }
                    if booking.exchangeLookupPlotNo.directBookingNilIfBlank == nil { return ("Old Plot Number is required", .bookingFinance) }
                    if AppModuleFormatters.normalizePhone(booking.exchangeConnectedMobileNumber).count != 10 {
                        return ("Connected Mobile Number must be exactly 10 digits", .bookingFinance)
                    }
                }
                if booking.sourceExchangeBookingId.directBookingNilIfBlank == nil {
                    return ("Matching confirmed booking is required", .bookingFinance)
                }
            }
            if booking.bookingType == "EXCHANGE", (Double(booking.exchangeOldRegisteredValue) ?? 0) <= 0 {
                return ("Exchange Value is required", .bookingFinance)
            }
        }
        if (Double(booking.specialConsideration) ?? 0) > 0 {
            if booking.discountApprovedBy.directBookingNilIfBlank == nil { return ("Discount Approved By is required", .bookingFinance) }
            if booking.specialConsiderationReason.directBookingNilIfBlank == nil { return ("SC Reason is required", .bookingFinance) }
            if (Double(booking.specialConsiderationValidity) ?? 0) <= 0 { return ("SC Validity is required", .bookingFinance) }
        }
        if booking.isAgainstSV {
            if booking.svName.directBookingNilIfBlank == nil { return ("SV Name is required", .bookingFinance) }
            if AppModuleFormatters.normalizePhone(booking.svMobileNo).count != 10 { return ("SV Mobile No. must be exactly 10 digits", .bookingFinance) }
        }
        if ["UPI", "NEFT", "RTGS"].contains(booking.bookingMode) {
            if booking.advanceTransactionId.directBookingNilIfBlank == nil { return ("Transaction ID is required", .bookingFinance) }
            if booking.advancePaymentProofStorageId.directBookingNilIfBlank == nil { return ("Payment Proof is required", .bookingFinance) }
        }
        if ["CHEQUE", "DD"].contains(booking.bookingMode) {
            if booking.advanceInstrumentNo.directBookingNilIfBlank == nil { return ("Cheque / DD number is required", .bookingFinance) }
            if booking.advanceBankName.directBookingNilIfBlank == nil { return ("Bank is required", .bookingFinance) }
            if booking.advanceBankBranch.directBookingNilIfBlank == nil { return ("Branch is required", .bookingFinance) }
            if booking.advanceInstrumentDate.directBookingNilIfBlank == nil { return ("Instrument date is required", .bookingFinance) }
        }
        if booking.customerPaymentCategory == "B", (Double(booking.loanAmountRequested) ?? 0) <= 0 {
            return ("Bank Loan Amount is required", .bookingFinance)
        }
        if !booking.freePayment {
            let schedule = [
                ("2nd Payment", booking.secondPaymentAmount, booking.secondPaymentDate),
                ("3rd Payment", booking.thirdPaymentAmount, booking.thirdPaymentDate),
                ("4th Payment", booking.fourthPaymentAmount, booking.fourthPaymentDate)
            ]
            if let incomplete = schedule.first(where: { $0.1.directBookingNilIfBlank == nil || $0.2.directBookingNilIfBlank == nil }) {
                return ("\(incomplete.0) amount and date are required", .paymentStaff)
            }
        }
        return nil
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
        selectedProjectSpecialPaymentEnabled = initialProject?.specialPaymentEnabled
        selectedUnit = initialUnit
        selectedLead = nil
        leadMatches = []
        if let initialProject {
            booking.projectId = initialProject.id
            booking.projectName = initialProject.name ?? ""
        }
        if let initialUnit {
            booking.plotId = initialUnit.id
            booking.plotNo = initialUnit.unitNumber ?? ""
        }
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
        selectedProjectSpecialPaymentEnabled = initialProject?.specialPaymentEnabled
        if let initialProject {
            booking.projectId = initialProject.id
            booking.projectName = initialProject.name ?? ""
        }
        if let initialUnit {
            booking.plotId = initialUnit.id
            booking.plotNo = initialUnit.unitNumber ?? ""
        }
        guard initialProject == nil, initialUnit == nil,
              let data = UserDefaults.standard.data(forKey: draftStorageKey),
              let draft = decodeDraft(data),
              !draft.isEmpty else { return }
        booking = draft
        booking.migrateLegacyOfficeAddressIfNeeded()
        draftMessage = "Draft restored"
    }

    private func decodeDraft(_ data: Data) -> DirectBookingDraft? {
        if let decoded = try? JSONDecoder().decode(DirectBookingDraft.self, from: data) {
            return decoded
        }
        guard var saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(DirectBookingDraft()),
              let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return nil }
        for (key, value) in defaults where saved[key] == nil {
            saved[key] = value
        }
        guard let migrated = try? JSONSerialization.data(withJSONObject: saved) else { return nil }
        return try? JSONDecoder().decode(DirectBookingDraft.self, from: migrated)
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
        let payload = BookingRemoteDraftPayload(
            sourceKey: "walk_in",
            draftJson: String(data: data, encoding: .utf8) ?? "{}"
        )
        try? await MarketingConvexAPIService.saveBookingDraft(token: token, payload: payload)
    }

    @MainActor
    private func clearDraft() {
        draftSaveTask?.cancel()
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
        draftMessage = nil
        guard let token = authStore.currentSession?.token else { return }
        Task { try? await MarketingConvexAPIService.clearBookingDraft(token: token) }
    }

    private static let customerPaymentCategoryOptions = [
        DirectBookingOption(value: "A", label: "A - Self Finance / Hand Cash"),
        DirectBookingOption(value: "B", label: "B - Loan Customer"),
        DirectBookingOption(value: "C", label: "C - EMI")
    ]

    private static let referenceRelationOptions = [
        "Father", "Mother", "Spouse", "Brother", "Sister", "Son", "Daughter",
        "Friend", "Colleague", "Neighbour", "Relative", "Other"
    ]

    private var paymentPlanOptions: [DirectBookingOption] {
        var options = [
            DirectBookingOption(value: "Regular", label: paymentPlanLabel("Regular")),
            DirectBookingOption(value: "Flexi", label: paymentPlanLabel("Flexi"))
        ]
        if specialPaymentAllowed {
            options.append(DirectBookingOption(value: "Special", label: paymentPlanLabel("Special")))
        }
        return options
    }

    private var specialPaymentAllowed: Bool {
        selectedProject?.specialPaymentEnabled == true || selectedProjectSpecialPaymentEnabled == true
    }

    private var paymentPlanDays: Int {
        switch booking.normalizedPaymentPlan {
        case "Flexi": return 60
        case "Special": return 180
        default: return 30
        }
    }

    private func paymentPlanLabel(_ plan: String) -> String {
        let days: Int
        switch plan {
        case "Flexi": days = 60
        case "Special": days = 180
        default: days = 30
        }
        return "\(plan) (max \(days) days)"
    }

    private func ordinalPaymentLabel(_ position: Int) -> String {
        let remainder = position % 100
        let suffix: String
        if (11...13).contains(remainder) {
            suffix = "th"
        } else {
            switch position % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(position)\(suffix)"
    }

    private func paymentDateLimit(days: Int) -> Date? {
        let base = AppModuleFormatters.ymd.date(from: booking.bookingDate) ?? Date()
        return Calendar.current.date(byAdding: .day, value: days, to: base)
    }
}

private enum DirectBookingTab: String, CaseIterable, Identifiable {
    case client
    case bookingFinance
    case paymentStaff

    var id: String { rawValue }
    var title: String {
        switch self {
        case .client: return "Client Details"
        case .bookingFinance: return "Booking & Finance"
        case .paymentStaff: return "Payment & Staff"
        }
    }
}

private enum DirectBookingStaffField: String, Identifiable {
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

private enum DirectBookingUploadKind {
    case advanceProof
    case aadhaar
    case pan
}

private enum DirectBookingSaveAs: String, Codable, Hashable {
    case draft
    case confirmed
    case cancelled

    var actionTitle: String {
        switch self {
        case .draft: return "Save Draft"
        case .confirmed: return "Save & Send for Approval"
        case .cancelled: return "Save as Cancelled"
        }
    }
}

private struct DirectBookingPaymentDraft: Codable, Equatable, Sendable {
    var amount = ""
    var dueDate = ""
}

private struct DirectBookingDraft: Codable, Equatable, Sendable {
    var phone = ""
    var title = ""
    var name = ""
    var clientImageStorageId = ""
    var clientImageFileName = ""
    var fatherSpouseName = ""
    var dateOfBirth = ""
    var anniversaryDate = ""
    var alternateNumbers = ""
    var whatsappNumber = ""
    var whatsappSameAsMobile = false
    var email = ""
    var nationality = ""
    var homeAddress = ""
    var pincode = ""
    var state = ""
    var district = ""
    var location = ""
    var latitude = ""
    var longitude = ""
    var googleMapsLink = ""
    var profession = ""
    var designation = ""
    var department = ""
    var otherDepartment = ""
    var incomePerAnnum = ""
    var officeName = ""
    var officeEmail = ""
    var officeMobile = ""
    var officePhone = ""
    var officeAddress = ""
    var officeDoorNo = ""
    var officeStreetName = ""
    var officeAddressLine1 = ""
    var officeAddressLine2 = ""
    var officeArea = ""
    var officePincode = ""
    var projectId = ""
    var projectName = ""
    var plotId = ""
    var plotNo = ""
    var bookingType = ""
    var conversionManualEntry = true
    var manualConversionProjectName = ""
    var manualConversionPlotNo = ""
    var manualConversionCredit = ""
    var conversionNotes = ""
    var sourceExchangeBookingId = ""
    var exchangeManualEntry = true
    var exchangeLookupProjectId = ""
    var exchangeLookupPlotNo = ""
    var exchangeConnectedMobileNumber = ""
    var manualExchangeProjectName = ""
    var manualExchangePlotNo = ""
    var manualExchangeExtentSqft = ""
    var exchangeOldRegisteredValue = ""
    var exchangeNotes = ""
    var sourceType = "walk_in"
    var cefNo = ""
    var bookingDate = AppModuleFormatters.ymd.string(from: Date())
    var propertyType = ""
    var bookingMode = ""
    var clientSource = ""
    var clientSourceName = ""
    var clientSourceMobile = ""
    var referralBenefit = ""
    var isAgainstSV = true
    var svName = ""
    var svMobileNo = ""
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
    var advanceTransactionId = ""
    var advancePaymentProofStorageId = ""
    var advancePaymentProofFileName = ""
    var advanceInstrumentNo = ""
    var advanceBankName = ""
    var advanceBankBranch = ""
    var advanceInstrumentDate = ""
    var customerPaymentCategory = ""
    var loanAmountRequested = ""
    var paymentPlan = "Flexi"
    var freePayment = true
    var allotmentDueAmount = ""
    var allotmentDueDate = ""
    var secondPaymentAmount = ""
    var secondPaymentDate = ""
    var thirdPaymentAmount = ""
    var thirdPaymentDate = ""
    var fourthPaymentAmount = ""
    var fourthPaymentDate = ""
    var flexiPaymentRows = [DirectBookingPaymentDraft()]
    var preferredRegistrationDate = ""
    var originalAvpStaffId = ""
    var originalGmStaffId = ""
    var originalSeniorManagerStaffId = ""
    var originalBdoStaffId = ""
    var originalTelecallerStaffId = ""
    var aadhaar = ""
    var aadhaarDocumentStorageId = ""
    var aadhaarDocumentFileName = ""
    var pan = ""
    var panDocumentStorageId = ""
    var panDocumentFileName = ""
    var referenceName1 = ""
    var referenceMobile1 = ""
    var referenceProfession1 = ""
    var referenceName2 = ""
    var referenceMobile2 = ""
    var referenceProfession2 = ""
    var docPreparedIn = ""
    var saveAs: DirectBookingSaveAs = .draft

    var composedOfficeAddress: String? {
        let composed = [
            ("Door No", officeDoorNo),
            ("Street Name", officeStreetName),
            ("Address Line 1", officeAddressLine1),
            ("Address Line 2", officeAddressLine2)
        ]
            .compactMap { label, value -> String? in
                guard let value = value.directBookingNilIfBlank else { return nil }
                return "\(label): \(value)"
            }
            .joined(separator: ", ")
        return composed.directBookingNilIfBlank ?? officeAddress.directBookingNilIfBlank
    }

    mutating func migrateLegacyOfficeAddressIfNeeded() {
        let splitFields = [officeDoorNo, officeStreetName, officeAddressLine1, officeAddressLine2]
        guard splitFields.allSatisfy({ $0.directBookingNilIfBlank == nil }),
              let legacyAddress = officeAddress.directBookingNilIfBlank else { return }

        let parts = legacyAddress.split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var foundLabel = false
        for part in parts {
            let pieces = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { continue }
            let label = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            switch label {
            case "door no": officeDoorNo = value
            case "street name": officeStreetName = value
            case "floor", "address line 1": officeAddressLine1 = value
            case "area", "address line 2": officeAddressLine2 = value
            default: continue
            }
            foundLabel = true
        }
        if !foundLabel {
            officeDoorNo = parts.indices.contains(0) ? parts[0] : ""
            officeStreetName = parts.indices.contains(1) ? parts[1] : ""
            officeAddressLine1 = parts.indices.contains(2) ? parts[2] : ""
            officeAddressLine2 = parts.indices.contains(3) ? parts[3] : ""
        }
        officeAddress = ""
    }

    var agreedAmount: Double? {
        guard let cost = Double(bookingCost) else { return nil }
        return max(cost - (Double(specialConsideration) ?? 0), 0)
    }

    var totalPayableAmount: Double? {
        guard let agreedAmount else { return nil }
        return agreedAmount
            + (Double(registrationCharges) ?? 0)
            + (gstApplicable ? (Double(gstAmount) ?? 0) : 0)
            + (Double(documentCharges) ?? 0)
            + (Double(pattaCharges) ?? 0)
            + (otherChargesApplicable ? (Double(otherCharges) ?? 0) : 0)
    }

    var exchangeBalancePayable: Double {
        max((totalPayableAmount ?? 0) - (Double(exchangeOldRegisteredValue) ?? 0), 0)
    }

    var isEmpty: Bool {
        [
            phone, name, projectName, plotNo, bookingCost, advanceAmount, email, homeAddress,
            fatherSpouseName, officeName, officeDoorNo, officeStreetName, officeAddressLine1,
            cefNo, registrationCharges
        ].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
        let category = customerPaymentCategory.directBookingNilIfBlank
        let plan = normalizedPaymentPlan
        let isExchange = bookingType == "EXCHANGE" || bookingType == "INTERNAL EXCHANGE"
        let isOnlinePayment = ["UPI", "NEFT", "RTGS"].contains(bookingMode)
        let isInstrumentPayment = ["CHEQUE", "DD"].contains(bookingMode)
        let flexiSchedule = freePayment
            ? flexiPaymentRows.compactMap { row -> BookingPaymentScheduleItem? in
                guard let amount = Double(row.amount), let dueDate = row.dueDate.directBookingNilIfBlank else { return nil }
                return BookingPaymentScheduleItem(amount: amount, dueDate: dueDate)
            }
            : []
        let total = bookingType == "EXCHANGE" ? exchangeBalancePayable : totalPayableAmount
        let conversionCredit = bookingType == "CONVERSION" && conversionManualEntry
            ? (Double(manualConversionCredit) ?? 0)
            : 0
        return CreateBookingRequest(
            clientName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mobileNumber: mobile,
            bookingDate: bookingDate.directBookingNilIfBlank ?? AppModuleFormatters.ymd.string(from: Date()),
            leadId: selectedLead?.id,
            title: title.directBookingNilIfBlank,
            clientImageStorageId: clientImageStorageId.directBookingNilIfBlank,
            clientImageFileName: clientImageStorageId.directBookingNilIfBlank == nil ? nil : (clientImageFileName.directBookingNilIfBlank ?? "client-photo.jpg"),
            fatherSpouseName: fatherSpouseName.directBookingNilIfBlank,
            dateOfBirth: dateOfBirth.directBookingNilIfBlank,
            anniversaryDate: anniversaryDate.directBookingNilIfBlank,
            alternateNumbers: alternateNumbers.directBookingNilIfBlank,
            whatsappNumber: whatsappNumber.directBookingNilIfBlank,
            lat: Double(latitude),
            lng: Double(longitude),
            googleMapsLink: googleMapsLink.directBookingNilIfBlank,
            projectId: selectedProject?.id ?? projectId.directBookingNilIfBlank,
            plotId: selectedUnit?.id ?? plotId.directBookingNilIfBlank,
            plotNo: selectedUnit?.unitNumber ?? plotNo.directBookingNilIfBlank,
            bookingType: bookingType.directBookingNilIfBlank,
            conversionManualEntry: bookingType == "CONVERSION" ? conversionManualEntry : nil,
            manualConversionProjectName: bookingType == "CONVERSION" && conversionManualEntry ? manualConversionProjectName.directBookingNilIfBlank : nil,
            manualConversionPlotNo: bookingType == "CONVERSION" && conversionManualEntry ? manualConversionPlotNo.directBookingNilIfBlank : nil,
            manualConversionCredit: bookingType == "CONVERSION" && conversionManualEntry ? Double(manualConversionCredit) : nil,
            conversionNotes: bookingType == "CONVERSION" && conversionManualEntry ? conversionNotes.directBookingNilIfBlank : nil,
            sourceExchangeBookingId: isExchange && !exchangeManualEntry ? sourceExchangeBookingId.directBookingNilIfBlank : nil,
            exchangeManualEntry: isExchange ? exchangeManualEntry : nil,
            exchangeLookupProjectId: bookingType == "INTERNAL EXCHANGE" && !exchangeManualEntry ? exchangeLookupProjectId.directBookingNilIfBlank : nil,
            exchangeLookupPlotNo: bookingType == "INTERNAL EXCHANGE" && !exchangeManualEntry ? exchangeLookupPlotNo.directBookingNilIfBlank : nil,
            exchangeConnectedMobileNumber: bookingType == "INTERNAL EXCHANGE" && !exchangeManualEntry ? AppModuleFormatters.normalizePhone(exchangeConnectedMobileNumber) : nil,
            manualExchangeProjectName: isExchange && exchangeManualEntry ? manualExchangeProjectName.directBookingNilIfBlank : nil,
            manualExchangePlotNo: isExchange && exchangeManualEntry ? manualExchangePlotNo.directBookingNilIfBlank : nil,
            manualExchangeExtentSqft: isExchange && exchangeManualEntry ? Double(manualExchangeExtentSqft) : nil,
            exchangeOldRegisteredValue: isExchange ? Double(exchangeOldRegisteredValue) : nil,
            exchangeNewValue: bookingType == "EXCHANGE" ? agreedAmount : nil,
            exchangeBalancePayable: bookingType == "EXCHANGE" ? exchangeBalancePayable : nil,
            exchangeNotes: isExchange ? exchangeNotes.directBookingNilIfBlank : nil,
            cefNo: cefNo.directBookingNilIfBlank,
            isDuplicateBooking: isDuplicateBooking,
            isAgainstSV: isAgainstSV,
            svName: isAgainstSV ? svName.directBookingNilIfBlank : nil,
            svMobileNo: isAgainstSV ? AppModuleFormatters.normalizePhone(svMobileNo).directBookingNilIfBlank : nil,
            propertyType: propertyType.directBookingNilIfBlank,
            bookingMode: bookingMode.directBookingNilIfBlank,
            clientSource: clientSource.directBookingNilIfBlank,
            clientSourceName: clientSourceName.directBookingNilIfBlank,
            clientSourceMobile: clientSourceMobile.directBookingNilIfBlank,
            referralBenefit: referralBenefit.directBookingNilIfBlank,
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
            balanceAmount: total.map { max($0 - (advance ?? 0) - conversionCredit, 0) },
            paymentMode: bookingMode.directBookingNilIfBlank,
            advanceTransactionId: isOnlinePayment ? advanceTransactionId.directBookingNilIfBlank : nil,
            advancePaymentProofStorageId: isOnlinePayment ? advancePaymentProofStorageId.directBookingNilIfBlank : nil,
            advancePaymentProofFileName: isOnlinePayment ? advancePaymentProofFileName.directBookingNilIfBlank : nil,
            advanceInstrumentNo: isInstrumentPayment ? advanceInstrumentNo.directBookingNilIfBlank : nil,
            advanceBankName: isInstrumentPayment ? advanceBankName.directBookingNilIfBlank : nil,
            advanceBankBranch: isInstrumentPayment ? advanceBankBranch.directBookingNilIfBlank : nil,
            advanceInstrumentDate: isInstrumentPayment ? advanceInstrumentDate.directBookingNilIfBlank : nil,
            customerPaymentCategory: category,
            loanAmountRequested: category == "B" ? Double(loanAmountRequested) : nil,
            paymentPlan: plan,
            freePayment: plan == "Flexi",
            allotmentDueAmount: Double(allotmentDueAmount),
            allotmentDueDate: allotmentDueDate.directBookingNilIfBlank,
            secondPaymentAmount: freePayment ? flexiSchedule.first?.amount : Double(secondPaymentAmount),
            secondPaymentDate: freePayment ? flexiSchedule.first?.dueDate : secondPaymentDate.directBookingNilIfBlank,
            thirdPaymentAmount: freePayment ? flexiSchedule.dropFirst().first?.amount : Double(thirdPaymentAmount),
            thirdPaymentDate: freePayment ? flexiSchedule.dropFirst().first?.dueDate : thirdPaymentDate.directBookingNilIfBlank,
            fourthPaymentAmount: freePayment ? flexiSchedule.dropFirst(2).first?.amount : Double(fourthPaymentAmount),
            fourthPaymentDate: freePayment ? flexiSchedule.dropFirst(2).first?.dueDate : fourthPaymentDate.directBookingNilIfBlank,
            flexiPaymentSchedule: flexiSchedule.isEmpty ? nil : flexiSchedule,
            preferredRegistrationDate: preferredRegistrationDate.directBookingNilIfBlank,
            originalAvpStaffId: originalAvpStaffId.directBookingNilIfBlank,
            originalGmStaffId: originalGmStaffId.directBookingNilIfBlank,
            originalSeniorManagerStaffId: originalSeniorManagerStaffId.directBookingNilIfBlank,
            originalBdoStaffId: originalBdoStaffId.directBookingNilIfBlank,
            originalTelecallerStaffId: originalTelecallerStaffId.directBookingNilIfBlank,
            aadhaar: aadhaar.directBookingNilIfBlank,
            aadhaarDocumentStorageId: aadhaarDocumentStorageId.directBookingNilIfBlank,
            aadhaarDocumentFileName: aadhaarDocumentFileName.directBookingNilIfBlank,
            pan: pan.directBookingNilIfBlank,
            panDocumentStorageId: panDocumentStorageId.directBookingNilIfBlank,
            panDocumentFileName: panDocumentFileName.directBookingNilIfBlank,
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
            department: profession == "Salaried" ? (department == "Other" ? otherDepartment.directBookingNilIfBlank : department.directBookingNilIfBlank) : nil,
            incomePerAnnum: incomePerAnnum.directBookingNilIfBlank,
            officeName: officeName.directBookingNilIfBlank,
            officeAddress: composedOfficeAddress,
            officeArea: officeArea.directBookingNilIfBlank,
            officePincode: officePincode.directBookingNilIfBlank,
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
            status: saveAs.rawValue,
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

    var normalizedPaymentPlan: String {
        switch paymentPlan.directBookingNilIfBlank ?? (freePayment ? "Flexi" : "Regular") {
        case "Flexi": return "Flexi"
        case "Special": return "Special"
        default: return "Regular"
        }
    }

    static func paymentCategoryLabel(for category: String?) -> String? {
        switch category {
        case "A": return "A - Self Finance / Hand Cash"
        case "B": return "B - Loan Customer"
        case "C": return "C - EMI"
        default: return nil
        }
    }
}

private struct BookingRemoteDraftPayload: Encodable, Sendable {
    let sourceKey: String
    let draftJson: String
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

private struct DirectBookingOption: Identifiable, Hashable {
    let value: String
    let label: String

    var id: String { value }
}

private struct DirectBookingOptionPicker: View {
    let title: String
    @Binding var value: String
    let placeholder: String
    let icon: String
    let options: [DirectBookingOption]

    init(_ title: String, value: Binding<String>, placeholder: String, icon: String, options: [DirectBookingOption]) {
        self.title = title
        self._value = value
        self.placeholder = placeholder
        self.icon = icon
        self.options = options
    }

    private var selectedLabel: String {
        options.first { $0.value == value }?.label ?? placeholder
    }

    var body: some View {
        Menu {
            Button("Clear") { value = "" }
            ForEach(options) { option in
                Button(option.label) { value = option.value }
            }
        } label: {
            DirectBookingPickerShell(title: title, value: selectedLabel, icon: icon)
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
    let maxDate: Date?
    @State private var date = Date()
    @State private var showPicker = false

    init(_ title: String, text: Binding<String>, defaultsToToday: Bool = false, maxDate: Date? = nil) {
        self.title = title
        self._text = text
        self.defaultsToToday = defaultsToToday
        self.maxDate = maxDate
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
            if let maxDate, date > maxDate {
                date = maxDate
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                VStack {
                    if let maxDate {
                        DatePicker(title, selection: $date, in: Date.distantPast...maxDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                    } else {
                        DatePicker(title, selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if let maxDate, date > maxDate {
                                date = maxDate
                            }
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

private extension String {
    var directBookingNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
