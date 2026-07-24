import MapKit
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
    @State private var plotPrefill: BookingPlotPrefill?
    @State private var conversionPrefill: BookingConversionPrefill?
    @State private var exchangeSourceCandidates: [BookingExchangeSource] = []
    @State private var lastAutoFilledPlotId: String?
    @State private var selectedLead: TelecallerLeadSearchData?
    @State private var matchedClient: BookingClientProfile?
    @State private var leadMatches: [TelecallerLeadSearchData] = []
    @State private var projects: [MarketingProject] = []
    @State private var availableUnits: [InventoryUnit] = []
    @State private var unitsProjectId: String?
    @State private var staff: [ConvexStaffListItem] = []
    @State private var showProjectPicker = false
    @State private var showUnitPicker = false
    @State private var showLeadPicker = false
    @State private var showExchangeProjectPicker = false
    @State private var showExchangeSourcePicker = false
    @State private var showInternalExchangePlotPicker = false
    @State private var activeStaffPicker: DirectBookingStaffField?
    @State private var clientImagePickerItem: PhotosPickerItem?
    @State private var clientImageURL: URL?
    @State private var clientImagePreview: DirectBookingClientImagePreviewItem?
    @State private var isResolvingClientImageURL = false
    @State private var isUploadingClientImage = false
    @State private var showDocumentImporter = false
    @State private var pendingDocumentUploadKind: DirectBookingUploadKind?
    @State private var isUploadingDocument = false
    @State private var isSubmitting = false
    @State private var isSearchingLead = false
    @State private var isLoadingStaff = false
    @State private var isLoadingUnits = false
    @State private var unitLoadError: String?
    @State private var isLoadingPlotPrefill = false
    @State private var plotPrefillError: String?
    @State private var isLoadingBookingTypeAutofill = false
    @State private var bookingTypeAutofillError: String?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var draftMessage: String?
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var phoneLookupTask: Task<Void, Never>?
    @State private var clientImageURLTask: Task<Void, Never>?
    @State private var unitListTask: Task<Void, Never>?
    @State private var unitLoadGeneration = 0
    @State private var plotPrefillTask: Task<Void, Never>?
    @State private var bookingTypeAutofillTask: Task<Void, Never>?
    @State private var homeGeocodeTask: Task<Void, Never>?
    @State private var homeCoordinateAddressQuery: String?
    @State private var isGeocodingHomeAddress = false
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
        bookingAlertView
            .appFormActivity()
    }

    private var bookingContent: some View {
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
        .appCompactSheetCTAContainer()
    }

    private var bookingTaskView: some View {
        bookingContent
            .task {
                await prepareBookingForm()
            }
            .onDisappear(perform: cancelPendingTasks)
    }

    private var bookingDraftTrackingView: some View {
        bookingTaskView
        .onChange(of: booking) { _, _ in scheduleDraftAutosave() }
        .onChange(of: booking.homeAddressSearchText) { _, _ in scheduleHomeAddressGeocode() }
    }

    private var bookingPaymentTrackingView: some View {
        bookingDraftTrackingView
        .onChange(of: booking.customerPaymentCategory) { _, value in
            if value != "B" { booking.loanAmountRequested = "" }
        }
        .onChange(of: booking.paymentPlan) { _, value in
            booking.freePayment = value == "Flexi"
        }
    }

    private var bookingStaffTrackingView: some View {
        bookingPaymentTrackingView
        .onChange(of: selectedTab) { _, tab in
            guard tab == .paymentStaff else { return }
            Task { await loadStaffIfNeeded() }
        }
        .onChange(of: booking.profession) { _, value in
            if value != "Salaried" {
                booking.department = ""
                booking.otherDepartment = ""
            }
        }
    }

    private var bookingLifecycleView: some View {
        bookingStaffTrackingView
        .onChange(of: clientImagePickerItem) { _, item in
            Task { await uploadClientImage(item) }
        }
        .onChange(of: booking.clientImageStorageId) { _, storageId in
            scheduleClientImageURLResolution(for: storageId)
        }
    }

    @MainActor
    private func prepareBookingForm() async {
        restoreDraftIfNeeded()
        scheduleClientImageURLResolution(for: booking.clientImageStorageId)
        await Task.yield()
        await loadInitialData()
        await resolveSelectedProjectSpecialPaymentIfNeeded()
        scheduleBookingTypeAutofill()
        guard let initialUnit else { return }
        await loadPlotPrefill(for: initialUnit)
    }

    private func cancelPendingTasks() {
        draftSaveTask?.cancel()
        phoneLookupTask?.cancel()
        clientImageURLTask?.cancel()
        unitListTask?.cancel()
        plotPrefillTask?.cancel()
        bookingTypeAutofillTask?.cancel()
        homeGeocodeTask?.cancel()
    }

    private var bookingPickerView: some View {
        bookingLifecycleView
        .sheet(isPresented: $showProjectPicker) { projectPickerSheet }
        .sheet(isPresented: $showUnitPicker) { unitPickerSheet }
        .sheet(isPresented: $showLeadPicker) { leadPickerSheet }
        .sheet(isPresented: $showExchangeProjectPicker) { exchangeProjectPickerSheet }
        .sheet(isPresented: $showExchangeSourcePicker) { exchangeSourcePickerSheet }
        .sheet(isPresented: $showInternalExchangePlotPicker) { internalExchangePlotPickerSheet }
        .fullScreenCover(item: $clientImagePreview) { preview in
            DirectBookingClientImagePreview(preview: preview)
        }
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

    private var bookingImporterView: some View {
        bookingPickerView
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: [.image, .pdf, .data],
            allowsMultipleSelection: false
        ) { result in
            guard let kind = pendingDocumentUploadKind else { return }
            pendingDocumentUploadKind = nil
            Task { await importDocument(result, kind: kind) }
        }
    }

    private var bookingAlertView: some View {
        bookingImporterView
        .alert("Booking", isPresented: bookingAlertBinding) {
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

    private var bookingAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil || successMessage != nil },
            set: { isPresented in
                guard !isPresented else { return }
                errorMessage = nil
                successMessage = nil
            }
        )
    }

    private var fixedFooterAction: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color(hex: 0xEAECF0))
            footerAction
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
        .background(Color.white)
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
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            selectedTab = .bookingFinance
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color(hex: 0x2DAE12))
                    .disabled(isSubmitting)

                    Button {
                        Task { await submit(as: .draft) }
                    } label: {
                        if isSubmitting && booking.saveAs == .draft {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Save Draft", systemImage: "doc")
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color(hex: 0x2DAE12))
                    .disabled(!canCreateBooking || isSubmitting)
                }

                Button {
                    Task { await submit(as: .confirmed) }
                } label: {
                    if isSubmitting && booking.saveAs == .confirmed {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Save & Send for Approval", systemImage: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
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

    private var tabBody: AnyView {
        switch selectedTab {
        case .client:
            return AnyView(clientTabBody)
        case .bookingFinance:
            return AnyView(bookingFinanceTabBody)
        case .paymentStaff:
            return AnyView(paymentStaffTabBody)
        }
    }

    private var clientTabBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            clientDetails
            professionalDetails
            officeDetails
        }
    }

    private var bookingFinanceTabBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            bookingDetails
            sourceReferralDetails
            chargesDetails
            chargesAndAdvanceDetails
        }
    }

    private var paymentStaffTabBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            paymentDetails
            staffDetails
        }
    }

    private var clientDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            clientIdentityDetails
            clientContactDetails
            clientHomeAddressDetails
        }
    }

    private var clientIdentityDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            clientPhoneField
            leadLookupStatus
            DirectBookingPicker("Title *", value: $booking.title, placeholder: "Select Title", icon: "person", options: ["Mr", "Mrs", "Ms", "Dr", "Prof"])
            DirectBookingTextField("Client Name *", text: $booking.name, placeholder: "Enter Client Name", icon: "person")
            clientImageUploadCard
            DirectBookingTextField("Father/Spouse Name *", text: $booking.fatherSpouseName, placeholder: "Enter Name", icon: "person")
            DirectBookingDateField("Date of Birth *", text: $booking.dateOfBirth)
            DirectBookingDateField("Anniversary Date", text: $booking.anniversaryDate)
        }
    }

    private var clientPhoneField: some View {
        DirectBookingTextField(
            "Client Phone Number *",
            text: $booking.phone,
            placeholder: "Enter Mobile Number",
            icon: "phone",
            keyboard: .phonePad
        )
        .onChange(of: booking.phone) { _, value in
            handleClientPhoneChange(value)
        }
    }

    private var clientContactDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingTextField("Alternate Numbers *", text: $booking.alternateNumbers, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            DirectBookingTextField("WhatsApp Number *", text: $booking.whatsappNumber, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            androidCheckRow("WhatsApp Number", isOn: $booking.whatsappSameAsMobile, onText: "Same as personal mobile")
                .onChange(of: booking.whatsappSameAsMobile) { _, same in
                    if same { booking.whatsappNumber = booking.phone }
                }
            DirectBookingTextField("Email *", text: $booking.email, placeholder: "Enter Email Id", icon: "envelope", keyboard: .emailAddress)
            DirectBookingPicker("Nationality *", value: $booking.nationality, placeholder: "Select Nationality", icon: "globe", options: ["Indian", "NRI", "Foreign"])
        }
    }

    private var clientHomeAddressDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Home Address")
            DirectBookingTextField("Door No *", text: $booking.homeDoorNo, placeholder: "Enter door number", icon: "door.left.hand.open")
            DirectBookingTextField("Street Name *", text: $booking.homeStreetName, placeholder: "Enter street name", icon: "road.lanes")
            DirectBookingTextField("Pincode *", text: $booking.pincode, placeholder: "6-digit pincode", icon: "mappin", keyboard: .numberPad)
                .onChange(of: booking.pincode) { _, value in
                    booking.pincode = String(value.filter(\.isNumber).prefix(6))
                }
            DirectBookingTextField("District *", text: $booking.district, placeholder: "Enter District", icon: "mappin")
            DirectBookingTextField("Address Line 1 *", text: $booking.homeAddressLine1, placeholder: "Enter address line 1", icon: "mappin")
            DirectBookingTextField("Address Line 2", text: $booking.homeAddressLine2, placeholder: "Enter address line 2", icon: "mappin")
            homeAddressMapPreview
        }
    }

    @MainActor
    private func handleClientPhoneChange(_ value: String) {
        let sanitizedPhone = String(value.filter(\.isNumber).prefix(10))
        guard sanitizedPhone == value else {
            booking.phone = sanitizedPhone
            return
        }
        if booking.whatsappSameAsMobile {
            booking.whatsappNumber = sanitizedPhone
        }
        phoneLookupTask?.cancel()
        phoneLookupTask = Task {
            await lookupBookingProfileIfNeeded(phone: sanitizedPhone)
        }
        scheduleBookingTypeAutofill()
    }

    private var homeAddressMapPreview: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Label("Location on map", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x475467))

                if let coordinate = homeAddressCoordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                    ))) {
                        Marker("Home", coordinate: coordinate)
                    }
                    .mapStyle(.standard)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if isGeocodingHomeAddress {
                            Label("Updating", systemImage: "location.magnifyingglass")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x475467))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(8)
                        }
                    }
                    .id("\(coordinate.latitude),\(coordinate.longitude)")
                } else {
                    HStack(spacing: 8) {
                        if isGeocodingHomeAddress {
                            ProgressView().controlSize(.small)
                            Text("Finding this address on the map...")
                        } else {
                            Image(systemName: "map")
                            Text("Fill the address — the map will preview the location once it geocodes.")
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .padding(.horizontal, 12)
                    .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundStyle(Color(hex: 0xD0D5DD))
                    )
                }
            }
        )
    }

    private var homeAddressCoordinate: CLLocationCoordinate2D? {
        guard let latitude = Double(booking.latitude),
              let longitude = Double(booking.longitude),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var clientImageUploadCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Client Image")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))

            if booking.clientImageStorageId.directBookingNilIfBlank != nil {
                HStack(spacing: 12) {
                    Button {
                        guard let clientImageURL else { return }
                        clientImagePreview = DirectBookingClientImagePreviewItem(
                            url: clientImageURL,
                            fileName: booking.clientImageFileName.directBookingNilIfBlank ?? "Client photo"
                        )
                    } label: {
                        clientImageThumbnail
                    }
                    .buttonStyle(.plain)
                    .disabled(clientImageURL == nil)
                    .accessibilityLabel("Preview client image")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(isUploadingClientImage ? "Uploading client image..." : (booking.clientImageFileName.directBookingNilIfBlank ?? "Client photo"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x101828))
                            .lineLimit(1)
                        Text(clientImageURL == nil ? "Preparing preview..." : "Tap the photo to preview")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0x667085))
                            .lineLimit(1)
                    }

                    Spacer()

                    if isUploadingClientImage {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        PhotosPicker(selection: $clientImagePickerItem, matching: .images) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 23, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x0B61CA))
                        }
                        .accessibilityLabel("Replace client image")

                        Button {
                            booking.clientImageStorageId = ""
                            booking.clientImageFileName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x98A2B3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove client image")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
                )
            } else {
                PhotosPicker(selection: $clientImagePickerItem, matching: .images) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isUploadingClientImage ? "Uploading client image..." : "Upload client photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x101828))
                            Text("Optional profile photo for the client")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: 0x667085))
                        }
                        Spacer()
                        if isUploadingClientImage {
                            ProgressView()
                                .controlSize(.small)
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
    }

    @ViewBuilder
    private var clientImageThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0xF2F4F7))

            if let clientImageURL {
                AsyncImage(url: clientImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x98A2B3))
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else if isResolvingClientImageURL {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white, lineWidth: 2)
        )
        .overlay(alignment: .bottomTrailing) {
            if clientImageURL != nil {
                Image(systemName: "eye.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.68), in: Circle())
                    .offset(x: 4, y: 4)
            }
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
            DirectBookingFieldLabel(title)
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
            DirectBookingPicker("Profession *", value: $booking.profession, placeholder: "Select Profession", icon: "briefcase", options: ["Business", "Salaried", "Pension"])
            DirectBookingTextField("Designation *", text: $booking.designation, placeholder: "Enter Designation", icon: "person")
            if booking.profession == "Salaried" {
                DirectBookingPicker("Department *", value: $booking.department, placeholder: "Select Department", icon: "building.2", options: ["Admin", "Sales", "HR", "Software Developer", "Other"])
                if booking.department == "Other" {
                    DirectBookingTextField("Other Department *", text: $booking.otherDepartment, placeholder: "Enter Department", icon: "building.2")
                }
            }
            DirectBookingTextField("Income Per Annum *", text: $booking.incomePerAnnum, placeholder: "Enter Income", icon: "indianrupeesign", keyboard: .decimalPad)
        }
    }

    private var officeDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingTextField("Office Name *", text: $booking.officeName, placeholder: "Enter Name", icon: "building.2")
            DirectBookingTextField("Office Email", text: $booking.officeEmail, placeholder: "Enter Email", icon: "envelope", keyboard: .emailAddress)
            DirectBookingTextField("Office Mobile", text: $booking.officeMobile, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            DirectBookingTextField("Office Phone", text: $booking.officePhone, placeholder: "Enter Number", icon: "phone", keyboard: .phonePad)
            sectionTitle("Office Address")
            DirectBookingTextField("Door No *", text: $booking.officeDoorNo, placeholder: "Enter door / floor number", icon: "door.left.hand.open")
            DirectBookingTextField("Street Name *", text: $booking.officeStreetName, placeholder: "Enter street name", icon: "road.lanes")
            DirectBookingTextField("Address Line 1 *", text: $booking.officeAddressLine1, placeholder: "Enter address line 1", icon: "mappin")
            DirectBookingTextField("Address Line 2", text: $booking.officeAddressLine2, placeholder: "Enter address line 2", icon: "mappin")
            DirectBookingTextField("Office Area", text: $booking.officeArea, placeholder: "Enter Area", icon: "mappin")
            DirectBookingTextField("Office Pincode", text: $booking.officePincode, placeholder: "6-digit pincode", icon: "mappin", keyboard: .numberPad)
        }
    }

    private var bookingDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectBookingPickerShell(title: "Booking Ref No *", value: "Auto", icon: "number")
            DirectBookingPicker(
                "Booking Type *",
                value: Binding(
                    get: { booking.bookingType },
                    set: { selectBookingType($0) }
                ),
                placeholder: "Select Type",
                icon: "briefcase",
                options: ["NEW", "CONVERSION", "EXCHANGE", "INTERNAL EXCHANGE"]
            )
            conversionAndExchangeDetails
            DirectBookingTextField("CEF No *", text: $booking.cefNo, placeholder: "Enter Number", icon: "doc")
            if booking.bookingType == "INTERNAL EXCHANGE", selectedExchangeSource != nil {
                DirectBookingReadOnlyField(
                    "Booking Date *",
                    value: booking.bookingDate,
                    placeholder: "Original booking date",
                    icon: "calendar"
                )
            } else {
                DirectBookingDateField("Booking Date *", text: $booking.bookingDate, defaultsToToday: true)
            }
            DirectBookingPickerButton(title: "Project *", value: selectedProject?.name ?? booking.projectName, placeholder: "Select Project", icon: "briefcase") {
                Task { await loadProjectsThenShowPicker() }
            }
            DirectBookingPickerButton(title: "Plot (available only) *", value: selectedUnit?.unitNumber ?? booking.plotNo, placeholder: "Select Project First", icon: "square") {
                openUnitPicker()
            }
            unitListStatus
            plotPrefillStatus
            DirectBookingPicker("Property Type *", value: $booking.propertyType, placeholder: "Select Type", icon: "building.2", options: ["Plot", "Apartment", "Villa", "Commercial"])
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
                androidCheckRow("Is Against Site Visit? *", isOn: $booking.isAgainstSV, onText: "Yes", offText: "No (Online Sales)")
                siteVisitDetails
            }
        )
    }

    private var siteVisitDetails: AnyView {
        guard booking.isAgainstSV else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                DirectBookingTextField("SV Name *", text: $booking.svName, placeholder: "Enter Site Visit Name", icon: "person")
                DirectBookingTextField("SV Mobile No. *", text: $booking.svMobileNo, placeholder: "Enter Mobile Number", icon: "phone", keyboard: .phonePad)
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
        AnyView(
            VStack(alignment: .leading, spacing: 10) {
                bookingCheckboxRow(
                    "Manual conversion entry",
                    isOn: Binding(
                        get: { booking.conversionManualEntry },
                        set: { setConversionManualEntry($0) }
                    )
                )

                if booking.conversionManualEntry {
                    DirectBookingTextField("Previous Project *", text: $booking.manualConversionProjectName, placeholder: "Enter previous project name", icon: "building.2")
                    DirectBookingTextField("Previous Plot *", text: $booking.manualConversionPlotNo, placeholder: "Enter previous plot number", icon: "square")
                    DirectBookingTextField("Conversion Credit *", text: $booking.manualConversionCredit, placeholder: "Amount paid on previous booking", icon: "indianrupeesign", keyboard: .decimalPad)
                    DirectBookingTextField("Conversion Notes", text: $booking.conversionNotes, placeholder: "Details about the previous booking", icon: "doc", axis: .vertical)
                } else {
                    DirectBookingReadOnlyField(
                        "Previous Project",
                        value: booking.linkedConversionProjectName ?? "",
                        placeholder: conversionAutofillPlaceholder,
                        icon: "building.2"
                    )
                    DirectBookingReadOnlyField(
                        "Previous Plot",
                        value: booking.linkedConversionPlotNo ?? "",
                        placeholder: conversionAutofillPlaceholder,
                        icon: "square"
                    )
                    DirectBookingReadOnlyField(
                        "Total Amount Paid",
                        value: booking.linkedConversionCredit?.directBookingNilIfBlank.map {
                            AppModuleFormatters.rupees(Double($0) ?? 0)
                        } ?? "",
                        placeholder: isLoadingBookingTypeAutofill ? "Loading..." : "",
                        icon: "indianrupeesign"
                    )
                    bookingTypeAutofillStatus
                }
            }
        )
    }

    private var exchangeDetails: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 10) {
                bookingCheckboxRow(
                    "Manual old property entry",
                    isOn: Binding(
                        get: { booking.exchangeManualEntry },
                        set: { setExchangeManualEntry($0) }
                    )
                )
                exchangeSourceDetails

                if booking.exchangeManualEntry {
                    DirectBookingTextField(
                        booking.bookingType == "EXCHANGE" ? "Exchange Value *" : "Exchange Value",
                        text: $booking.exchangeOldRegisteredValue,
                        placeholder: "Old property value",
                        icon: "indianrupeesign",
                        keyboard: .decimalPad
                    )
                }

                exchangePropertySummary

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
                    DirectBookingTextField("Old Project Name *", text: $booking.manualExchangeProjectName, placeholder: "Enter old project name", icon: "building.2")
                    DirectBookingTextField("Old Plot Number *", text: $booking.manualExchangePlotNo, placeholder: "Enter old plot number", icon: "square")
                    DirectBookingTextField("Extent (Sq. Ft.)", text: $booking.manualExchangeExtentSqft, placeholder: "Old property extent", icon: "ruler", keyboard: .decimalPad)
                }
            )
        }
        if booking.bookingType == "INTERNAL EXCHANGE" {
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    DirectBookingPickerButton(
                        title: "Old Project Name *",
                        value: exchangeLookupProject?.name ?? "",
                        placeholder: "Select old project",
                        icon: "building.2"
                    ) {
                        Task { await loadProjectsThenShowExchangeProjectPicker() }
                    }
                    DirectBookingPickerButton(
                        title: "Old Plot Number *",
                        value: booking.exchangeLookupPlotNo,
                        placeholder: internalExchangePlotPlaceholder,
                        icon: "square"
                    ) {
                        openInternalExchangePlotPicker()
                    }
                    DirectBookingTextField("Connected Mobile Number *", text: $booking.exchangeConnectedMobileNumber, placeholder: "10-digit booked mobile", icon: "phone", keyboard: .phonePad)
                        .onChange(of: booking.exchangeConnectedMobileNumber) { _, value in
                            let sanitizedPhone = String(value.filter(\.isNumber).prefix(10))
                            guard sanitizedPhone == value else {
                                booking.exchangeConnectedMobileNumber = sanitizedPhone
                                return
                            }
                            booking.sourceExchangeBookingId = ""
                            booking.exchangeLookupPlotNo = ""
                            booking.exchangeOldRegisteredValue = ""
                            scheduleBookingTypeAutofill()
                        }
                    bookingTypeAutofillStatus
                }
            )
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                DirectBookingPickerButton(
                    title: "Exchanged Property *",
                    value: selectedExchangeSource.map(exchangeSourceTitle) ?? "",
                    placeholder: exchangeSourcePickerPlaceholder,
                    icon: "arrow.triangle.2.circlepath"
                ) {
                    openExchangeSourcePicker()
                }
                bookingTypeAutofillStatus
            }
        )
    }

    private var selectedExchangeSource: BookingExchangeSource? {
        exchangeSourceCandidates.first { $0.id == booking.sourceExchangeBookingId }
    }

    private var exchangeLookupProject: MarketingProject? {
        projects.first { $0.id == booking.exchangeLookupProjectId }
    }

    private var internalExchangePlotCandidates: [BookingExchangeSource] {
        exchangeSourceCandidates.filter { $0.projectId == booking.exchangeLookupProjectId }
    }

    private var conversionAutofillPlaceholder: String {
        if isLoadingBookingTypeAutofill { return "Loading..." }
        if AppModuleFormatters.normalizePhone(booking.phone).count == 10 {
            return "No previous booking found"
        }
        return "Enter client mobile number"
    }

    private var exchangeSourcePickerPlaceholder: String {
        let phone = AppModuleFormatters.normalizePhone(booking.phone)
        if phone.count != 10 { return "Enter 10-digit client mobile first" }
        if isLoadingBookingTypeAutofill { return "Loading properties..." }
        if exchangeSourceCandidates.isEmpty { return "No confirmed property found" }
        return "Select exchanged property"
    }

    private var internalExchangePlotPlaceholder: String {
        guard booking.exchangeLookupProjectId.directBookingNilIfBlank != nil else {
            return "Pick old project first"
        }
        let phone = AppModuleFormatters.normalizePhone(booking.exchangeConnectedMobileNumber)
        if phone.count != 10 { return "Enter connected mobile first" }
        if isLoadingBookingTypeAutofill { return "Loading old plots..." }
        if internalExchangePlotCandidates.isEmpty { return "No confirmed old plots found" }
        return "Select old plot"
    }

    @ViewBuilder
    private var bookingTypeAutofillStatus: some View {
        if isLoadingBookingTypeAutofill {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(booking.bookingType == "CONVERSION" ? "Finding previous booking..." : "Finding confirmed property...")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: 0x667085))
        } else if let bookingTypeAutofillError {
            Label(bookingTypeAutofillError, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
        } else if booking.bookingType == "CONVERSION",
                  !booking.conversionManualEntry,
                  conversionPrefill != nil {
            Label("Previous booking details auto-filled", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x187A2F))
        } else if booking.bookingType == "EXCHANGE",
                  !booking.exchangeManualEntry,
                  AppModuleFormatters.normalizePhone(booking.phone).count == 10,
                  exchangeSourceCandidates.isEmpty {
            Label("No confirmed property found for this mobile", systemImage: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
        } else if booking.bookingType == "INTERNAL EXCHANGE",
                  !booking.exchangeManualEntry,
                  AppModuleFormatters.normalizePhone(booking.exchangeConnectedMobileNumber).count == 10,
                  internalExchangePlotCandidates.isEmpty {
            Label("No available confirmed booking matches these details", systemImage: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
        }
    }

    private var exchangePropertySummary: AnyView {
        if let source = selectedExchangeSource {
            if booking.bookingType == "INTERNAL EXCHANGE" {
                return AnyView(
                    DirectBookingTypeSummaryCard(items: [
                        .init(label: "Booking", value: source.bookingRefNo),
                        .init(label: "Customer", value: source.clientName),
                        .init(label: "Property", value: exchangeSourceTitle(source)),
                        .init(label: "Original Booking Date", value: source.bookingDate)
                    ])
                )
            }
            return AnyView(
                DirectBookingTypeSummaryCard(items: [
                    .init(label: "Project Name", value: source.projectName?.directBookingNilIfBlank ?? "—"),
                    .init(label: "Plot Number", value: source.plotNo?.directBookingNilIfBlank ?? "—"),
                    .init(label: "Extent (Sq. Ft. / Acres)", value: exchangeExtentText(source.extentSqft)),
                    .init(label: "Exchange Value", value: AppModuleFormatters.rupees(source.resolvedExchangeValue))
                ])
            )
        }

        if booking.bookingType == "EXCHANGE", booking.exchangeManualEntry {
            return AnyView(
                DirectBookingTypeSummaryCard(items: [
                    .init(label: "Project Name", value: booking.manualExchangeProjectName.directBookingNilIfBlank ?? "—"),
                    .init(label: "Plot Number", value: booking.manualExchangePlotNo.directBookingNilIfBlank ?? "—"),
                    .init(label: "Extent (Sq. Ft. / Acres)", value: exchangeExtentText(Double(booking.manualExchangeExtentSqft))),
                    .init(label: "Exchange Value", value: AppModuleFormatters.rupees(Double(booking.exchangeOldRegisteredValue) ?? 0))
                ])
            )
        }

        return AnyView(EmptyView())
    }

    private func exchangeSourceTitle(_ source: BookingExchangeSource) -> String {
        let project = source.projectName?.directBookingNilIfBlank ?? "Project"
        let plot = source.plotNo?.directBookingNilIfBlank ?? "Plot"
        return "\(project) / \(plot)"
    }

    private func exchangeExtentText(_ extent: Double?) -> String {
        guard let extent, extent > 0 else { return "—" }
        return "\(extent.formatted(.number.precision(.fractionLength(0...2)))) / \((extent / 43_560).formatted(.number.precision(.fractionLength(3))))"
    }

    private var chargesDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Financial Details")
            DirectBookingTextField("Booking Cost *", text: $booking.bookingCost, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("Guideline Value *", text: $booking.guidelineValue, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("Special Consideration", text: $booking.specialConsideration, placeholder: "Discount amount", icon: "indianrupeesign", keyboard: .decimalPad)
            bookingHelperText("Enter the amount to deduct from the booking cost.")
            if (Double(booking.specialConsideration) ?? 0) > 0 {
                DirectBookingTextField("Discount Approved By *", text: $booking.discountApprovedBy, placeholder: "AVP or GM name", icon: "person")
                DirectBookingTextField("SC Reason *", text: $booking.specialConsiderationReason, placeholder: "Enter Details", icon: "doc", axis: .vertical)
                DirectBookingTextField("SC Validity *", text: $booking.specialConsiderationValidity, placeholder: "Enter Days", icon: "calendar", keyboard: .numberPad)
            }
            if let agreedAmount = booking.agreedAmount {
                DirectBookingPickerShell(title: "Agreed Amount", value: AppModuleFormatters.rupees(agreedAmount), icon: "indianrupeesign")
            }
            DirectBookingTextField("Promotional Offer *", text: $booking.promotionalOffers, placeholder: "Enter promotional offer", icon: "tag")
            DirectBookingTextField("Offer Value *", text: $booking.promotionalOfferValue, placeholder: "0.00", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingOptionPicker("Terms & Conditions *", value: $booking.promotionalOffersTnC, placeholder: "Select timeline...", icon: "doc", options: Self.promotionalTermsOptions)
                .onChange(of: booking.promotionalOffersTnC) { _, value in
                    booking.offerValidityPeriod = String(value.filter(\.isNumber))
                }
        }
    }

    private var chargesAndAdvanceDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            bookingChargeFields
            customerFundingFields
        }
    }

    private var bookingChargeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Charges & Advance")
            DirectBookingTextField("Registration Charges *", text: $booking.registrationCharges, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingTextField("GST Amount *", text: $booking.gstAmount, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            bookingApplicabilityControl(isOn: $booking.gstApplicable)
            DirectBookingTextField("Document Charges *", text: $booking.documentCharges, placeholder: "Enter Cost", icon: "doc", keyboard: .decimalPad)
            DirectBookingTextField("Patta Charges *", text: $booking.pattaCharges, placeholder: "Enter Cost", icon: "doc", keyboard: .decimalPad)
            DirectBookingTextField("Other Charges *", text: $booking.otherCharges, placeholder: "Enter Value", icon: "indianrupeesign", keyboard: .decimalPad)
            bookingApplicabilityControl(isOn: $booking.otherChargesApplicable)
        }
    }

    private var customerFundingFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Customer Funding")
            DirectBookingOptionPicker("Customer Payment Category *", value: $booking.customerPaymentCategory, placeholder: "Select category", icon: "creditcard", options: Self.customerPaymentCategoryOptions)
            customerLoanDetails
            payableSummaryCard
            DirectBookingPicker("Advance Booking Payment *", value: $booking.bookingMode, placeholder: "Select...", icon: "creditcard", options: ["CASH", "UPI", "NEFT", "RTGS", "CHEQUE", "DD"])
            DirectBookingTextField("Advance Amount *", text: $booking.advanceAmount, placeholder: "Enter Amount", icon: "indianrupeesign", keyboard: .decimalPad)
            bookingHelperText("Project minimum: \(AppModuleFormatters.rupees(configuredMinimumAdvance ?? 0)). Higher advance is allowed.")
            advancePaymentDetails
        }
    }

    private func bookingHelperText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Color(hex: 0x667085))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var unitListStatus: some View {
        if isLoadingUnits {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading available plots...")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: 0x667085))
        } else if selectedUnit == nil, let unitLoadError {
            Label(unitLoadError, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var plotPrefillStatus: some View {
        if isLoadingPlotPrefill {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading plot pricing...")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: 0x667085))
        } else if plotPrefill?.plot.id == selectedUnit?.id {
            Label("Plot pricing filled from project settings", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x187A2F))
        } else if let plotPrefillError {
            Label(plotPrefillError, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

    private var payableSummaryCard: AnyView {
        guard selectedUnit != nil,
              let totalPayableAmount = booking.payableAmountForBooking else {
            return AnyView(EmptyView())
        }

        return AnyView(
            DirectBookingPayableSummaryCard(
                landCost: booking.agreedAmount ?? 0,
                gst: booking.gstApplicable ? booking.numericAmount(booking.gstAmount) : 0,
                registrationCharges: booking.numericAmount(booking.registrationCharges),
                documentCharges: booking.numericAmount(booking.documentCharges),
                pattaCharges: booking.numericAmount(booking.pattaCharges),
                otherCharges: booking.otherChargesApplicable ? booking.numericAmount(booking.otherCharges) : 0,
                grossBookingValue: booking.totalPayableAmount ?? 0,
                exchangeValue: booking.bookingType == "EXCHANGE" ? booking.numericAmount(booking.exchangeOldRegisteredValue) : nil,
                totalPayable: totalPayableAmount,
                minimumAdvance: configuredMinimumAdvance ?? 0,
                advanceEntered: booking.numericAmount(booking.advanceAmount),
                customerPayable: booking.customerPaymentCategory == "B" ? booking.customerPayableAmount : nil,
                bankLoanAmount: booking.customerPaymentCategory == "B" ? booking.numericAmount(booking.loanAmountRequested) : nil,
                balanceAfterAdvance: booking.balanceAfterAdvance ?? totalPayableAmount,
                isExchange: booking.bookingType == "EXCHANGE"
            )
        )
    }

    private var configuredMinimumAdvance: Double? {
        selectedProject?.minimumAdvanceAmount ?? plotPrefill?.fields.advanceAmount
    }

    private func bookingApplicabilityControl(isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .semibold))
                Text("Applicable")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .foregroundStyle(isOn.wrappedValue ? Color(hex: 0x218C54) : Color(hex: 0x667085))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }

    private var customerLoanDetails: AnyView {
        guard booking.customerPaymentCategory == "B" else { return AnyView(EmptyView()) }
        return AnyView(
            DirectBookingTextField("Bank Loan Amount *", text: $booking.loanAmountRequested, placeholder: "Enter approved/requested loan amount", icon: "doc", keyboard: .decimalPad)
        )
    }

    private var advancePaymentDetails: AnyView {
        if ["UPI", "NEFT", "RTGS"].contains(booking.bookingMode) {
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    DirectBookingTextField("Transaction ID *", text: $booking.advanceTransactionId, placeholder: "UTR / Ref no", icon: "number")
                    bookingDocumentUploadCard(
                        title: "Payment Proof *",
                        fileName: booking.advancePaymentProofFileName,
                        isUploaded: booking.advancePaymentProofStorageId.directBookingNilIfBlank != nil,
                        onSelect: { presentDocumentImporter(for: .advanceProof) },
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
                    DirectBookingTextField(booking.bookingMode == "DD" ? "DD No *" : "Cheque No *", text: $booking.advanceInstrumentNo, placeholder: "Enter instrument number", icon: "number")
                    DirectBookingTextField("Bank *", text: $booking.advanceBankName, placeholder: "Enter bank", icon: "building.columns")
                    DirectBookingTextField("Branch *", text: $booking.advanceBankBranch, placeholder: "Enter branch", icon: "building.2")
                    DirectBookingDateField("Instrument Date *", text: $booking.advanceInstrumentDate)
                    if booking.bookingMode == "CHEQUE" {
                        bookingDocumentUploadCard(
                            title: "Cheque Attachment",
                            fileName: booking.advancePaymentProofFileName,
                            isUploaded: booking.advancePaymentProofStorageId.directBookingNilIfBlank != nil,
                            onSelect: { presentDocumentImporter(for: .advanceProof) },
                            onRemove: {
                                booking.advancePaymentProofStorageId = ""
                                booking.advancePaymentProofFileName = ""
                            }
                        )
                    }
                }
            )
        }
        return AnyView(EmptyView())
    }

    private var paymentDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Payment Schedule")
            DirectBookingOptionPicker("Payment Plan *", value: $booking.paymentPlan, placeholder: "Select Plan", icon: "calendar", options: paymentPlanOptions)
            DirectBookingTextField("Allotment Due Amount *", text: $booking.allotmentDueAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
            DirectBookingDateField("Allotment Due Date *", text: $booking.allotmentDueDate, maxDate: paymentDateLimit(days: 10))
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
                            "\(ordinalPaymentLabel(index + 2)) Payment Amount *",
                            text: Binding(
                                get: { booking.flexiPaymentRows[index].amount },
                                set: { booking.flexiPaymentRows[index].amount = $0 }
                            ),
                            placeholder: "Enter Cost",
                            icon: "indianrupeesign",
                            keyboard: .decimalPad
                        )
                        DirectBookingDateField(
                            "\(ordinalPaymentLabel(index + 2)) Payment Date *",
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
                DirectBookingTextField("2nd Payment Amount *", text: $booking.secondPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
                DirectBookingDateField("2nd Payment Date *", text: $booking.secondPaymentDate, maxDate: paymentDateLimit(days: paymentPlanDays))
                DirectBookingTextField("3rd Payment Amount *", text: $booking.thirdPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
                DirectBookingDateField("3rd Payment Date *", text: $booking.thirdPaymentDate, maxDate: paymentDateLimit(days: paymentPlanDays))
                DirectBookingTextField("4th Payment Amount *", text: $booking.fourthPaymentAmount, placeholder: "Enter Cost", icon: "indianrupeesign", keyboard: .decimalPad)
                DirectBookingDateField("4th Payment Date *", text: $booking.fourthPaymentDate, maxDate: paymentDateLimit(days: paymentPlanDays))
            }
            DirectBookingDateField("Preferred Registration Date *", text: $booking.preferredRegistrationDate)
        }
    }

    private var staffDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            staffPicker(.avp)
            staffPicker(.generalManager)
            staffPicker(.seniorManager)
            staffPicker(.bdo)
            staffPicker(.telecaller)
            DirectBookingTextField("Aadhaar Details *", text: $booking.aadhaar, placeholder: "Enter Details", icon: "doc", keyboard: .numberPad)
                .onChange(of: booking.aadhaar) { _, value in
                    booking.aadhaar = String(value.filter(\.isNumber).prefix(12))
                }
            bookingDocumentUploadCard(
                title: "Aadhaar Upload *",
                fileName: booking.aadhaarDocumentFileName,
                isUploaded: booking.aadhaarDocumentStorageId.directBookingNilIfBlank != nil,
                onSelect: { presentDocumentImporter(for: .aadhaar) },
                onRemove: {
                    booking.aadhaarDocumentStorageId = ""
                    booking.aadhaarDocumentFileName = ""
                }
            )
            DirectBookingTextField("PAN Details *", text: $booking.pan, placeholder: "Enter Details", icon: "doc")
                .onChange(of: booking.pan) { _, value in
                    booking.pan = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(10))
                }
            bookingDocumentUploadCard(
                title: "PAN Upload *",
                fileName: booking.panDocumentFileName,
                isUploaded: booking.panDocumentStorageId.directBookingNilIfBlank != nil,
                onSelect: { presentDocumentImporter(for: .pan) },
                onRemove: {
                    booking.panDocumentStorageId = ""
                    booking.panDocumentFileName = ""
                }
            )
            DirectBookingTextField("Reference Name 1 *", text: $booking.referenceName1, placeholder: "Enter Name", icon: "person")
            DirectBookingTextField("Reference Mobile 1 *", text: $booking.referenceMobile1, placeholder: "Enter No", icon: "phone", keyboard: .phonePad)
            DirectBookingPicker("Reference Relation 1 *", value: $booking.referenceProfession1, placeholder: "Select Relation", icon: "person.2", options: Self.referenceRelationOptions)
            DirectBookingTextField("Reference Name 2 *", text: $booking.referenceName2, placeholder: "Enter Name", icon: "person")
            DirectBookingTextField("Reference Mobile 2 *", text: $booking.referenceMobile2, placeholder: "Enter No", icon: "phone", keyboard: .phonePad)
            DirectBookingPicker("Reference Relation 2 *", value: $booking.referenceProfession2, placeholder: "Select Relation", icon: "person.2", options: Self.referenceRelationOptions)
            DirectBookingPicker("Document to be prepared in *", value: $booking.docPreparedIn, placeholder: "Select", icon: "doc", options: ["English", "Kannada", "Tamil", "Telugu", "Hindi"])
        }
    }

    private var leadLookupStatus: some View {
        DirectBookingLeadLookupStatus(
            isSearching: isSearchingLead,
            matchedClientName: matchedClient.map {
                $0.clientName?.directBookingNilIfBlank ?? $0.mobileNumber ?? booking.phone
            },
            linkedLeadName: selectedLead?.displayName,
            canChooseLinkedLead: leadMatches.count > 1,
            onChooseLinkedLead: {
                showLeadPicker = true
            }
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(hex: 0x101828))
            .padding(.top, 10)
    }

    private func bookingCheckboxRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? Color(hex: 0x0B8F43) : Color(hex: 0x667085))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn.wrappedValue ? "Selected" : "Not selected")
    }

    private func androidCheckRow(_ title: String, isOn: Binding<Bool>, onText: String, offText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DirectBookingFieldLabel(title)
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
            Task { await loadStaffThenShowPicker(field) }
        } label: {
            DirectBookingPickerShell(
                title: "\(field.title) *",
                value: isLoadingStaff
                    ? "Loading staff..."
                    : (staff.first { $0.id == staffSelection(for: field) }?.displayName ?? "Select"),
                icon: "person"
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoadingStaff)
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
                unitListTask?.cancel()
                plotPrefillTask?.cancel()
                selectedProject = project
                selectedProjectSpecialPaymentEnabled = project.specialPaymentEnabled
                booking.projectId = project.id
                booking.projectName = project.name ?? ""
                applyProjectOffer(
                    name: project.promoOffer,
                    value: project.projectOfferValue,
                    terms: project.projectOfferTerms,
                    validityDays: project.projectOfferValidityDays
                )
                selectedUnit = nil
                availableUnits = []
                unitsProjectId = nil
                unitLoadError = nil
                isLoadingUnits = false
                plotPrefill = nil
                lastAutoFilledPlotId = nil
                plotPrefillError = nil
                isLoadingPlotPrefill = false
                booking.plotId = ""
                booking.plotNo = ""
                if booking.paymentPlan == "Special", project.specialPaymentEnabled == false {
                    booking.paymentPlan = "Regular"
                }
                showProjectPicker = false
                Task {
                    await resolveSelectedProjectSpecialPaymentIfNeeded(
                        overwriteProjectOffer: true
                    )
                }
                startUnitLoad(for: project, presentWhenReady: false)
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
                guard isAvailableForBooking(unit) else {
                    errorMessage = "Unit is no longer available"
                    return
                }
                selectedUnit = unit
                booking.plotId = unit.id
                booking.plotNo = unit.unitNumber ?? ""
                // Offers are configured on the project, not on a plot. Put
                // the cached project values back immediately on every plot
                // change; the plot-prefill response can then refine them.
                reapplySelectedProjectOffer()
                showUnitPicker = false
                plotPrefillTask?.cancel()
                plotPrefillTask = Task {
                    await loadPlotPrefill(for: unit)
                }
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

    private var exchangeProjectPickerSheet: some View {
        NativeSearchableSelectionSheet(
            title: "Select Old Project",
            prompt: "Search projects",
            items: projects,
            selectedId: booking.exchangeLookupProjectId.directBookingNilIfBlank,
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
                booking.exchangeLookupProjectId = project.id
                booking.exchangeLookupPlotNo = ""
                booking.sourceExchangeBookingId = ""
                booking.exchangeOldRegisteredValue = ""
                showExchangeProjectPicker = false
                scheduleBookingTypeAutofill()
            }
        )
        .appLibraryNativeSheet([.medium, .large])
    }

    private var exchangeSourcePickerSheet: some View {
        NativeSearchableSelectionSheet(
            title: "Select Exchanged Property",
            prompt: "Search booking or property",
            items: exchangeSourceCandidates,
            selectedId: booking.sourceExchangeBookingId.directBookingNilIfBlank,
            searchText: { source in
                [
                    source.bookingRefNo,
                    source.projectName,
                    source.plotNo,
                    source.clientName,
                    source.mobileNumber
                ]
                    .compactMap(\.self)
                    .joined(separator: " ")
            },
            rowContent: { source, isSelected in
                selectionRow(
                    title: exchangeSourceTitle(source),
                    subtitle: "\(source.bookingRefNo) • \(AppModuleFormatters.rupees(source.resolvedExchangeValue))",
                    isSelected: isSelected
                )
            },
            onSelect: { source in
                applyExchangeSource(source)
                showExchangeSourcePicker = false
            }
        )
        .appLibraryNativeSheet([.medium, .large])
    }

    private var internalExchangePlotPickerSheet: some View {
        NativeSearchableSelectionSheet(
            title: "Select Old Plot",
            prompt: "Search old plots",
            items: internalExchangePlotCandidates,
            selectedId: booking.sourceExchangeBookingId.directBookingNilIfBlank,
            searchText: { source in
                [
                    source.plotNo,
                    source.bookingRefNo,
                    source.clientName,
                    source.mobileNumber
                ]
                    .compactMap(\.self)
                    .joined(separator: " ")
            },
            rowContent: { source, isSelected in
                selectionRow(
                    title: source.plotNo?.directBookingNilIfBlank ?? "Plot",
                    subtitle: "\(source.bookingRefNo) • \(source.clientName) • \(source.mobileNumber)",
                    isSelected: isSelected
                )
            },
            onSelect: { source in
                applyExchangeSource(source)
                showInternalExchangePlotPicker = false
            }
        )
        .appLibraryNativeSheet([.medium, .large])
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
        guard initialProject == nil,
              booking.projectId.directBookingNilIfBlank != nil else { return }
        await loadProjects()
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
    private func loadStaffIfNeeded() async {
        guard staff.isEmpty, !isLoadingStaff else { return }
        isLoadingStaff = true
        await loadStaff()
        isLoadingStaff = false
    }

    @MainActor
    private func loadStaffThenShowPicker(_ field: DirectBookingStaffField) async {
        await loadStaffIfNeeded()
        guard !staff.isEmpty else {
            errorMessage = "No active staff available"
            return
        }
        activeStaffPicker = field
    }

    @MainActor
    private func loadProjectsThenShowPicker() async {
        if projects.isEmpty { await loadProjects() }
        showProjectPicker = !projects.isEmpty
        if projects.isEmpty { errorMessage = "No projects available" }
    }

    @MainActor
    private func loadProjectsThenShowExchangeProjectPicker() async {
        if projects.isEmpty { await loadProjects() }
        showExchangeProjectPicker = !projects.isEmpty
        if projects.isEmpty { errorMessage = "No projects available" }
    }

    @MainActor
    private func selectBookingType(_ type: String) {
        guard booking.bookingType != type else {
            scheduleBookingTypeAutofill()
            return
        }
        bookingTypeAutofillTask?.cancel()
        booking.bookingType = type
        booking.conversionManualEntry = false
        booking.manualConversionProjectName = ""
        booking.manualConversionPlotNo = ""
        booking.manualConversionCredit = ""
        booking.conversionNotes = ""
        clearLinkedConversionAutofill()

        booking.exchangeManualEntry = false
        booking.exchangeLookupProjectId = ""
        booking.exchangeLookupPlotNo = ""
        booking.exchangeConnectedMobileNumber = ""
        booking.manualExchangeProjectName = ""
        booking.manualExchangePlotNo = ""
        booking.manualExchangeExtentSqft = ""
        booking.exchangeOldRegisteredValue = ""
        booking.exchangeNotes = ""
        booking.sourceExchangeBookingId = ""
        exchangeSourceCandidates = []
        bookingTypeAutofillError = nil
        isLoadingBookingTypeAutofill = false
        scheduleBookingTypeAutofill()
    }

    @MainActor
    private func setConversionManualEntry(_ isManual: Bool) {
        guard booking.conversionManualEntry != isManual else { return }
        booking.conversionManualEntry = isManual
        booking.manualConversionProjectName = ""
        booking.manualConversionPlotNo = ""
        booking.manualConversionCredit = ""
        booking.conversionNotes = ""
        clearLinkedConversionAutofill()
        bookingTypeAutofillError = nil
        if isManual {
            bookingTypeAutofillTask?.cancel()
            isLoadingBookingTypeAutofill = false
        } else {
            scheduleBookingTypeAutofill()
        }
    }

    @MainActor
    private func setExchangeManualEntry(_ isManual: Bool) {
        guard booking.exchangeManualEntry != isManual else { return }
        booking.exchangeManualEntry = isManual
        booking.sourceExchangeBookingId = ""
        booking.exchangeOldRegisteredValue = ""
        bookingTypeAutofillError = nil
        if isManual {
            bookingTypeAutofillTask?.cancel()
            isLoadingBookingTypeAutofill = false
            exchangeSourceCandidates = []
            booking.exchangeLookupProjectId = ""
            booking.exchangeLookupPlotNo = ""
            booking.exchangeConnectedMobileNumber = ""
        } else {
            booking.manualExchangeProjectName = ""
            booking.manualExchangePlotNo = ""
            booking.manualExchangeExtentSqft = ""
            scheduleBookingTypeAutofill()
        }
    }

    @MainActor
    private func clearLinkedConversionAutofill() {
        conversionPrefill = nil
        booking.linkedConversionBookingId = nil
        booking.linkedConversionBookingRefNo = nil
        booking.linkedConversionProjectName = nil
        booking.linkedConversionPlotNo = nil
        booking.linkedConversionCredit = nil
    }

    @MainActor
    private func scheduleBookingTypeAutofill() {
        bookingTypeAutofillTask?.cancel()
        bookingTypeAutofillError = nil
        isLoadingBookingTypeAutofill = false

        let bookingType = booking.bookingType
        switch bookingType {
        case "CONVERSION" where !booking.conversionManualEntry:
            let phone = AppModuleFormatters.normalizePhone(booking.phone)
            guard phone.count == 10 else {
                clearLinkedConversionAutofill()
                return
            }
            bookingTypeAutofillTask = Task {
                await loadConversionPrefill(phone: phone)
            }

        case "EXCHANGE" where !booking.exchangeManualEntry:
            let phone = AppModuleFormatters.normalizePhone(booking.phone)
            guard phone.count == 10 else {
                exchangeSourceCandidates = []
                booking.sourceExchangeBookingId = ""
                booking.exchangeOldRegisteredValue = ""
                return
            }
            bookingTypeAutofillTask = Task {
                await loadExchangeSources(phone: phone, bookingType: bookingType)
            }

        case "INTERNAL EXCHANGE" where !booking.exchangeManualEntry:
            let phone = AppModuleFormatters.normalizePhone(booking.exchangeConnectedMobileNumber)
            guard phone.count == 10 else {
                exchangeSourceCandidates = []
                booking.sourceExchangeBookingId = ""
                booking.exchangeLookupPlotNo = ""
                booking.exchangeOldRegisteredValue = ""
                return
            }
            bookingTypeAutofillTask = Task {
                await loadExchangeSources(phone: phone, bookingType: bookingType)
            }

        default:
            break
        }
    }

    @MainActor
    private func loadConversionPrefill(phone: String) async {
        guard let token = authStore.currentSession?.token else { return }
        isLoadingBookingTypeAutofill = true
        defer {
            if booking.bookingType == "CONVERSION",
               !booking.conversionManualEntry,
               AppModuleFormatters.normalizePhone(booking.phone) == phone {
                isLoadingBookingTypeAutofill = false
            }
        }

        do {
            let prefill = try await MarketingConvexAPIService.getBookingConversionPrefill(
                token: token,
                mobileNumber: phone
            )
            guard !Task.isCancelled,
                  booking.bookingType == "CONVERSION",
                  !booking.conversionManualEntry,
                  AppModuleFormatters.normalizePhone(booking.phone) == phone else { return }
            conversionPrefill = prefill
            booking.linkedConversionBookingId = prefill?.bookingId
            booking.linkedConversionBookingRefNo = prefill?.bookingRefNo
            booking.linkedConversionProjectName = prefill?.previousProject
            booking.linkedConversionPlotNo = prefill?.previousPlot
            booking.linkedConversionCredit = prefill.map {
                DirectBookingDraft.amountInputText($0.totalAmountPaid)
            } ?? ""
        } catch {
            guard !Task.isCancelled,
                  booking.bookingType == "CONVERSION",
                  !booking.conversionManualEntry,
                  AppModuleFormatters.normalizePhone(booking.phone) == phone else { return }
            clearLinkedConversionAutofill()
            bookingTypeAutofillError = "Could not load the previous booking. Tap the booking type to retry."
        }
    }

    @MainActor
    private func loadExchangeSources(phone: String, bookingType: String) async {
        guard let token = authStore.currentSession?.token else { return }
        isLoadingBookingTypeAutofill = true
        defer {
            let currentPhone = bookingType == "INTERNAL EXCHANGE"
                ? AppModuleFormatters.normalizePhone(booking.exchangeConnectedMobileNumber)
                : AppModuleFormatters.normalizePhone(booking.phone)
            if booking.bookingType == bookingType, currentPhone == phone {
                isLoadingBookingTypeAutofill = false
            }
        }

        do {
            let sources = try await MarketingConvexAPIService.listBookingExchangeSourceCandidates(
                token: token,
                mobileNumber: phone
            )
            let currentPhone = bookingType == "INTERNAL EXCHANGE"
                ? AppModuleFormatters.normalizePhone(booking.exchangeConnectedMobileNumber)
                : AppModuleFormatters.normalizePhone(booking.phone)
            guard !Task.isCancelled,
                  booking.bookingType == bookingType,
                  !booking.exchangeManualEntry,
                  currentPhone == phone else { return }

            exchangeSourceCandidates = sources
            if let selected = sources.first(where: { $0.id == booking.sourceExchangeBookingId }) {
                applyExchangeSource(selected)
                return
            }

            booking.sourceExchangeBookingId = ""
            booking.exchangeOldRegisteredValue = ""
            if bookingType == "INTERNAL EXCHANGE" {
                booking.exchangeLookupPlotNo = ""
                let matchingProjectSources = sources.filter {
                    $0.projectId == booking.exchangeLookupProjectId
                }
                if matchingProjectSources.count == 1, let onlySource = matchingProjectSources.first {
                    applyExchangeSource(onlySource)
                }
            }
        } catch {
            let currentPhone = bookingType == "INTERNAL EXCHANGE"
                ? AppModuleFormatters.normalizePhone(booking.exchangeConnectedMobileNumber)
                : AppModuleFormatters.normalizePhone(booking.phone)
            guard !Task.isCancelled,
                  booking.bookingType == bookingType,
                  currentPhone == phone else { return }
            exchangeSourceCandidates = []
            booking.sourceExchangeBookingId = ""
            booking.exchangeOldRegisteredValue = ""
            if bookingType == "INTERNAL EXCHANGE" {
                booking.exchangeLookupPlotNo = ""
            }
            bookingTypeAutofillError = "Could not load confirmed properties. Check the mobile number and retry."
        }
    }

    @MainActor
    private func applyExchangeSource(_ source: BookingExchangeSource) {
        booking.sourceExchangeBookingId = source.id
        booking.exchangeOldRegisteredValue = DirectBookingDraft.amountInputText(
            source.resolvedExchangeValue
        )
        if booking.bookingType == "INTERNAL EXCHANGE" {
            booking.exchangeLookupProjectId = source.projectId ?? booking.exchangeLookupProjectId
            booking.exchangeLookupPlotNo = source.plotNo?.uppercased() ?? ""
            booking.bookingDate = source.bookingDate
        }
        bookingTypeAutofillError = nil
    }

    @MainActor
    private func openExchangeSourcePicker() {
        let phone = AppModuleFormatters.normalizePhone(booking.phone)
        guard phone.count == 10 else {
            bookingTypeAutofillError = "Enter the 10-digit client mobile number in Client Details first."
            return
        }
        guard !exchangeSourceCandidates.isEmpty else {
            scheduleBookingTypeAutofill()
            return
        }
        showExchangeSourcePicker = true
    }

    @MainActor
    private func openInternalExchangePlotPicker() {
        guard booking.exchangeLookupProjectId.directBookingNilIfBlank != nil else {
            bookingTypeAutofillError = "Select the old project first."
            return
        }
        let phone = AppModuleFormatters.normalizePhone(booking.exchangeConnectedMobileNumber)
        guard phone.count == 10 else {
            bookingTypeAutofillError = "Enter the 10-digit connected mobile number first."
            return
        }
        guard !internalExchangePlotCandidates.isEmpty else {
            scheduleBookingTypeAutofill()
            return
        }
        showInternalExchangePlotPicker = true
    }

    @MainActor
    private func openUnitPicker() {
        guard let project = selectedProject else {
            errorMessage = "Pick a project first"
            return
        }

        if unitsProjectId == project.id, !availableUnits.isEmpty {
            showUnitPicker = true
            return
        }

        startUnitLoad(for: project, presentWhenReady: true)
    }

    @MainActor
    private func startUnitLoad(for project: MarketingProject, presentWhenReady: Bool) {
        unitListTask?.cancel()
        unitLoadGeneration += 1
        let generation = unitLoadGeneration
        unitListTask = Task {
            await loadUnits(
                for: project,
                generation: generation,
                presentWhenReady: presentWhenReady
            )
        }
    }

    @MainActor
    private func loadUnits(
        for project: MarketingProject,
        generation: Int,
        presentWhenReady: Bool
    ) async {
        guard let token = authStore.currentSession?.token else { return }
        guard selectedProject?.id == project.id else { return }

        isLoadingUnits = true
        unitLoadError = nil
        if unitsProjectId != project.id {
            availableUnits = []
            unitsProjectId = nil
        }

        defer {
            if unitLoadGeneration == generation, selectedProject?.id == project.id {
                isLoadingUnits = false
            }
        }

        do {
            let loadedUnits = try await MarketingConvexAPIService.listInventoryUnits(
                token: token,
                projectId: project.id,
                status: "available"
            )
                .filter(isAvailableForBooking)
                .sorted {
                    ($0.unitNumber ?? $0.id).localizedStandardCompare($1.unitNumber ?? $1.id) == .orderedAscending
                }

            guard !Task.isCancelled,
                  unitLoadGeneration == generation,
                  selectedProject?.id == project.id else { return }

            availableUnits = loadedUnits
            unitsProjectId = project.id
            if loadedUnits.isEmpty {
                unitLoadError = "No available plots found for \(project.name ?? "this project")."
            } else if presentWhenReady {
                showUnitPicker = true
            }
        } catch {
            guard !Task.isCancelled,
                  unitLoadGeneration == generation,
                  selectedProject?.id == project.id else { return }
            unitsProjectId = nil
            availableUnits = []
            unitLoadError = "Could not load plots. Tap the plot field to retry."
        }
    }

    private func isAvailableForBooking(_ unit: InventoryUnit) -> Bool {
        let publicStatus = unit.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawStatus = unit.rawStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return publicStatus == "available" || rawStatus == "available"
    }

    @MainActor
    private func loadPlotPrefill(for unit: InventoryUnit) async {
        guard lastAutoFilledPlotId != unit.id else { return }
        guard let token = authStore.currentSession?.token else { return }

        isLoadingPlotPrefill = true
        plotPrefillError = nil
        defer {
            if selectedUnit?.id == unit.id {
                isLoadingPlotPrefill = false
            }
        }

        do {
            let prefill = try await MarketingConvexAPIService.getBookingPlotPrefill(
                token: token,
                plotId: unit.id,
                bookingDate: booking.bookingDate.directBookingNilIfBlank
            )
            guard !Task.isCancelled, selectedUnit?.id == unit.id else { return }
            applyPlotPrefill(prefill)
            plotPrefill = prefill
            lastAutoFilledPlotId = unit.id
        } catch {
            guard !Task.isCancelled, selectedUnit?.id == unit.id else { return }
            plotPrefill = nil
            plotPrefillError = "Could not load plot pricing. You can still enter it manually."
        }
    }

    @MainActor
    private func applyPlotPrefill(_ prefill: BookingPlotPrefill) {
        if let project = prefill.project,
           project.promoOffer?.directBookingNilIfBlank != nil
            || project.projectOfferValue != nil
            || project.projectOfferTerms?.directBookingNilIfBlank != nil
            || project.projectOfferValidityDays != nil {
            applyProjectOffer(
                name: project.promoOffer ?? selectedProject?.promoOffer,
                value: project.projectOfferValue ?? selectedProject?.projectOfferValue,
                terms: project.projectOfferTerms ?? selectedProject?.projectOfferTerms,
                validityDays: project.projectOfferValidityDays
                    ?? selectedProject?.projectOfferValidityDays
            )
        }

        let fields = prefill.fields
        if let propertyType = normalizedPropertyType(prefill.plot.plotType),
           !propertyType.isEmpty {
            booking.propertyType = propertyType
        }
        booking.bookingCost = fields.bookingCost.map(DirectBookingDraft.amountInputText) ?? booking.bookingCost
        booking.guidelineValue = fields.guidelineValue.map(DirectBookingDraft.amountInputText) ?? booking.guidelineValue
        booking.registrationCharges = fields.registrationCharges.map(DirectBookingDraft.amountInputText) ?? booking.registrationCharges
        booking.gstAmount = fields.gstAmount.map(DirectBookingDraft.amountInputText) ?? booking.gstAmount
        booking.documentCharges = fields.documentCharges.map(DirectBookingDraft.amountInputText) ?? booking.documentCharges
        booking.pattaCharges = fields.pattaCharges.map(DirectBookingDraft.amountInputText) ?? booking.pattaCharges
        booking.otherCharges = fields.otherCharges.map(DirectBookingDraft.amountInputText) ?? booking.otherCharges
        booking.advanceAmount = fields.advanceAmount.map(DirectBookingDraft.amountInputText) ?? booking.advanceAmount
        booking.allotmentDueAmount = fields.allotmentDueAmount.map(DirectBookingDraft.amountInputText) ?? booking.allotmentDueAmount
        booking.allotmentDueDate = fields.allotmentDueDate?.directBookingNilIfBlank ?? booking.allotmentDueDate

        let schedules = prefill.schedules
        booking.secondPaymentAmount = ""
        booking.secondPaymentDate = schedules[safe: 0]?.dueDate?.directBookingNilIfBlank ?? ""
        booking.thirdPaymentAmount = ""
        booking.thirdPaymentDate = schedules[safe: 1]?.dueDate?.directBookingNilIfBlank ?? ""
        booking.fourthPaymentAmount = ""
        booking.fourthPaymentDate = schedules[safe: 2]?.dueDate?.directBookingNilIfBlank ?? ""
        booking.flexiPaymentRows = [
            DirectBookingPaymentDraft(
                amount: "",
                dueDate: schedules.first?.dueDate?.directBookingNilIfBlank ?? ""
            )
        ]
    }

    @MainActor
    private func applyProjectOffer(
        name: String?,
        value: Double?,
        terms: String?,
        validityDays: Double?
    ) {
        booking.promotionalOffers = name?.directBookingNilIfBlank ?? ""
        booking.promotionalOfferValue = value.map(DirectBookingDraft.amountInputText) ?? ""
        booking.promotionalOffersTnC = terms?.directBookingNilIfBlank ?? ""
        booking.offerValidityPeriod = validityDays.map(DirectBookingDraft.amountInputText) ?? ""
    }

    @MainActor
    private func reapplySelectedProjectOffer() {
        guard let project = selectedProject else { return }
        applyProjectOffer(
            name: project.promoOffer,
            value: project.projectOfferValue,
            terms: project.projectOfferTerms,
            validityDays: project.projectOfferValidityDays
        )
    }

    private func normalizedPropertyType(_ value: String?) -> String? {
        guard let value = value?.directBookingNilIfBlank else { return nil }
        switch value.lowercased() {
        case "plot", "plots", "plot only", "plots only", "plots_only": return "Plot"
        case "apartment", "flat", "flats": return "Apartment"
        case "villa": return "Villa"
        case "commercial": return "Commercial"
        default: return value
        }
    }

    @MainActor
    private func scheduleClientImageURLResolution(for storageId: String) {
        clientImageURLTask?.cancel()
        clientImageURL = nil
        clientImagePreview = nil

        guard let storageId = storageId.directBookingNilIfBlank,
              let token = authStore.currentSession?.token else {
            isResolvingClientImageURL = false
            return
        }

        isResolvingClientImageURL = true
        clientImageURLTask = Task {
            defer {
                if booking.clientImageStorageId == storageId {
                    isResolvingClientImageURL = false
                }
            }

            do {
                let urlString = try await HRConvexAPIService.getFileURL(
                    token: token,
                    storageId: storageId
                )
                guard !Task.isCancelled,
                      booking.clientImageStorageId == storageId else { return }
                clientImageURL = URL(string: urlString)
            } catch {
                guard !Task.isCancelled,
                      booking.clientImageStorageId == storageId else { return }
                clientImageURL = nil
            }
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
    private func presentDocumentImporter(for kind: DirectBookingUploadKind) {
        guard !isUploadingDocument else { return }
        pendingDocumentUploadKind = kind
        showDocumentImporter = true
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
    private func resolveSelectedProjectSpecialPaymentIfNeeded(
        overwriteProjectOffer: Bool = false
    ) async {
        guard let token = authStore.currentSession?.token, let project = selectedProject else { return }
        do {
            let detail = try await MarketingConvexAPIService.getMarketingProject(
                token: token,
                id: project.id
            )
            guard selectedProject?.id == project.id else { return }
            selectedProject = detail
            selectedProjectSpecialPaymentEnabled = detail.specialPaymentEnabled
            let offerFieldsAreEmpty =
                booking.promotionalOffers.directBookingNilIfBlank == nil &&
                booking.promotionalOfferValue.directBookingNilIfBlank == nil &&
                booking.promotionalOffersTnC.directBookingNilIfBlank == nil &&
                booking.offerValidityPeriod.directBookingNilIfBlank == nil
            if overwriteProjectOffer || offerFieldsAreEmpty {
                applyProjectOffer(
                    name: detail.promoOffer,
                    value: detail.projectOfferValue,
                    terms: detail.projectOfferTerms,
                    validityDays: detail.projectOfferValidityDays
                )
            }
            if booking.paymentPlan == "Special", detail.specialPaymentEnabled != true {
                booking.paymentPlan = "Regular"
            }
        } catch {
            // Keep the trimmed project response behavior if the detail fallback is unavailable.
        }
    }

    @MainActor
    private func lookupBookingProfileIfNeeded(phone: String) async {
        guard phone.count == 10 else {
            selectedLead = nil
            matchedClient = nil
            leadMatches = []
            isSearchingLead = false
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        selectedLead = nil
        matchedClient = nil
        leadMatches = []
        isSearchingLead = true
        defer { isSearchingLead = false }

        var matches: [TelecallerLeadSearchData] = []
        do {
            matches = try await MarketingConvexAPIService.searchTelecallerLeadsByPhone(token: token, phone: phone)
            guard AppModuleFormatters.normalizePhone(booking.phone) == phone else { return }
            leadMatches = matches
            selectedLead = nil
            if let first = matches.first { applyLead(first) }
        } catch {
            // Lead lookup is helpful, but manual booking entry must stay usable.
        }

        guard !Task.isCancelled,
              AppModuleFormatters.normalizePhone(booking.phone) == phone else { return }
        do {
            let client = try await MarketingConvexAPIService.searchClientByPhone(token: token, phone: phone)
            guard !Task.isCancelled,
                  AppModuleFormatters.normalizePhone(booking.phone) == phone else { return }
            matchedClient = client
            if let client {
                applyClientProfile(client)
            }
        } catch {
            // Client-master lookup supplements lead data. Keep manual entry usable.
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
        booking.homeDoorNo = lead.latestAnalysisProfile?.doorNo?.directBookingNilIfBlank
            ?? lead.clientPlaceProfile?.doorNo?.directBookingNilIfBlank
            ?? lead.manualProfile?.doorNo?.directBookingNilIfBlank
            ?? booking.homeDoorNo
        booking.homeStreetName = lead.latestAnalysisProfile?.street?.directBookingNilIfBlank
            ?? lead.clientPlaceProfile?.street?.directBookingNilIfBlank
            ?? lead.manualProfile?.street?.directBookingNilIfBlank
            ?? booking.homeStreetName
        booking.homeAddressLine1 = lead.latestAnalysisProfile?.address?.directBookingNilIfBlank
            ?? lead.clientPlaceProfile?.address?.directBookingNilIfBlank
            ?? lead.manualProfile?.address?.directBookingNilIfBlank
            ?? booking.homeAddressLine1
        booking.homeAddress = lead.suggestedVisitAddress?.directBookingNilIfBlank ?? booking.homeAddress
        booking.migrateLegacyHomeAddressIfNeeded()
        booking.pincode = lead.latestAnalysisProfile?.pincode?.directBookingNilIfBlank ?? booking.pincode
        booking.state = lead.latestAnalysisProfile?.state?.directBookingNilIfBlank ?? booking.state
        booking.district = lead.latestAnalysisProfile?.district?.directBookingNilIfBlank ?? booking.district
        booking.location = lead.locationPreferred?.directBookingNilIfBlank ?? booking.location
        booking.latitude = lead.suggestedVisitLat.map { String($0) } ?? booking.latitude
        booking.longitude = lead.suggestedVisitLng.map { String($0) } ?? booking.longitude
        booking.googleMapsLink = lead.suggestedGoogleMapsLink?.directBookingNilIfBlank ?? booking.googleMapsLink
        if homeAddressCoordinate != nil {
            homeCoordinateAddressQuery = booking.homeAddressSearchText
        }
        booking.propertyType = lead.latestAnalysisProfile?.propertyType?.directBookingNilIfBlank ?? booking.propertyType
        if booking.isAgainstSV {
            booking.svName = booking.svName.directBookingNilIfBlank ?? lead.displayName
            booking.svMobileNo = booking.svMobileNo.directBookingNilIfBlank ?? AppModuleFormatters.normalizePhone(lead.mobileNumber ?? "")
        }
    }

    @MainActor
    private func applyClientProfile(_ client: BookingClientProfile) {
        booking.title.directBookingFillIfBlank(with: client.title)
        booking.name.directBookingFillIfBlank(with: client.clientName?.directBookingNormalizedPersonName)
        booking.clientImageStorageId.directBookingFillIfBlank(with: client.clientImageStorageId)
        booking.clientImageFileName.directBookingFillIfBlank(with: client.clientImageFileName)
        booking.fatherSpouseName.directBookingFillIfBlank(with: client.fatherSpouseName?.directBookingNormalizedPersonName)
        booking.dateOfBirth.directBookingFillIfBlank(with: client.dateOfBirth)
        booking.anniversaryDate.directBookingFillIfBlank(with: client.anniversaryDate)
        booking.nationality.directBookingFillIfBlank(with: client.nationality)
        booking.alternateNumbers.directBookingFillIfBlank(with: client.alternateNumbers)
        booking.whatsappNumber.directBookingFillIfBlank(with: client.whatsappNumber)
        booking.email.directBookingFillIfBlank(with: client.email)

        booking.homeDoorNo.directBookingFillIfBlank(with: client.doorNo)
        booking.homeStreetName.directBookingFillIfBlank(
            with: client.addressLine1 ?? client.homeAddress ?? client.formattedAddress
        )
        booking.homeAddressLine1.directBookingFillIfBlank(
            with: client.addressLine2 ?? client.landmark ?? client.location ?? client.district
        )
        booking.homeAddressLine2.directBookingFillIfBlank(
            with: client.landmark ?? client.addressLine2
        )
        booking.pincode.directBookingFillIfBlank(with: client.pincode)
        booking.state.directBookingFillIfBlank(with: client.state)
        booking.district.directBookingFillIfBlank(with: client.district)
        booking.location.directBookingFillIfBlank(with: client.location)
        booking.latitude.directBookingFillIfBlank(with: client.lat.map { String($0) })
        booking.longitude.directBookingFillIfBlank(with: client.lng.map { String($0) })
        booking.googleMapsLink.directBookingFillIfBlank(with: client.googleMapsLink)
        if booking.googleMapsLink.directBookingNilIfBlank == nil,
           let lat = client.lat,
           let lng = client.lng {
            booking.googleMapsLink = "https://www.google.com/maps?q=\(lat),\(lng)"
        }
        if homeAddressCoordinate != nil {
            homeCoordinateAddressQuery = booking.homeAddressSearchText
        }

        booking.profession.directBookingFillIfBlank(with: client.profession)
        booking.designation.directBookingFillIfBlank(with: client.designation)
        if booking.profession == "Salaried",
           booking.department.directBookingNilIfBlank == nil,
           let department = client.department?.directBookingNilIfBlank {
            let standardDepartments = ["Admin", "Sales", "HR", "Software Developer"]
            if standardDepartments.contains(department) {
                booking.department = department
            } else {
                booking.department = "Other"
                booking.otherDepartment = department
            }
        }
        booking.incomePerAnnum.directBookingFillIfBlank(with: client.incomePerAnnum)

        booking.officeName.directBookingFillIfBlank(with: client.officeName)
        booking.officeAddress.directBookingFillIfBlank(with: client.officeAddress)
        booking.migrateLegacyOfficeAddressIfNeeded()
        booking.officeArea.directBookingFillIfBlank(with: client.officeArea)
        booking.officePincode.directBookingFillIfBlank(with: client.officePincode)
        booking.officeMobile.directBookingFillIfBlank(with: client.officeMobile)
        booking.officePhone.directBookingFillIfBlank(with: client.officePhone)
        booking.officeEmail.directBookingFillIfBlank(with: client.officeEmail)

        booking.aadhaar.directBookingFillIfBlank(
            with: client.aadhaar.map { String($0.filter(\.isNumber).prefix(12)) }
        )
        booking.pan.directBookingFillIfBlank(with: client.pan?.uppercased())
        booking.referenceName1.directBookingFillIfBlank(with: client.referenceName1)
        booking.referenceMobile1.directBookingFillIfBlank(with: client.referenceMobile1)
        booking.referenceProfession1.directBookingFillIfBlank(with: client.referenceProfession1)
        booking.referenceName2.directBookingFillIfBlank(with: client.referenceName2)
        booking.referenceMobile2.directBookingFillIfBlank(with: client.referenceMobile2)
        booking.referenceProfession2.directBookingFillIfBlank(with: client.referenceProfession2)

        if booking.isAgainstSV {
            booking.svName.directBookingFillIfBlank(with: client.clientName)
            booking.svMobileNo.directBookingFillIfBlank(with: client.mobileNumber)
        }
    }

    private func scheduleHomeAddressGeocode() {
        homeGeocodeTask?.cancel()
        guard booking.hasMinimumHomeAddressForGeocoding else {
            isGeocodingHomeAddress = false
            if booking.homeAddressSearchText.isEmpty {
                booking.latitude = ""
                booking.longitude = ""
                booking.googleMapsLink = ""
                homeCoordinateAddressQuery = nil
            }
            return
        }

        let query = booking.homeAddressSearchText
        guard homeAddressCoordinate == nil || homeCoordinateAddressQuery != query else {
            isGeocodingHomeAddress = false
            return
        }
        homeGeocodeTask = Task {
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            await geocodeHomeAddress(query)
        }
    }

    @MainActor
    private func geocodeHomeAddress(_ query: String) async {
        isGeocodingHomeAddress = true
        defer { isGeocodingHomeAddress = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled,
                  booking.homeAddressSearchText == query,
                  let coordinate = response.mapItems.first?.placemark.coordinate else { return }
            booking.latitude = String(coordinate.latitude)
            booking.longitude = String(coordinate.longitude)
            booking.googleMapsLink = "https://www.google.com/maps?q=\(coordinate.latitude),\(coordinate.longitude)"
            homeCoordinateAddressQuery = query
        } catch {
            // Keep the last known client pin if MapKit cannot resolve the edited address.
        }
    }

    @MainActor
    private func submit(as saveAs: DirectBookingSaveAs) async {
        booking.saveAs = saveAs
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
            switch saveAs {
            case .confirmed:
                successMessage = "Booking saved and sent for approval"
            case .draft:
                successMessage = "Booking saved as draft"
            case .cancelled:
                successMessage = "Booking saved as cancelled"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private typealias BookingValidationIssue = (message: String, tab: DirectBookingTab)

    private func bookingValidationError(mobile: String) -> BookingValidationIssue? {
        // Keep these stages small. A single all-fields tuple made the Debug device build
        // reserve more than the iOS main-thread stack before validation could begin.
        if let issue = requiredClientIdentityValidation(mobile: mobile) { return issue }
        if let issue = requiredClientAddressValidation() { return issue }
        if let issue = requiredClientWorkValidation() { return issue }
        if let issue = requiredBookingDetailsValidation() { return issue }
        if let issue = requiredFinanceDetailsValidation() { return issue }
        if let issue = requiredPaymentStaffValidation() { return issue }
        if let issue = requiredIdentityDocumentsValidation() { return issue }
        if let issue = requiredReferencesValidation() { return issue }

        if let issue = clientConditionalValidation(mobile: mobile) { return issue }
        if let issue = bookingTypeConditionalValidation() { return issue }
        if let issue = financeConditionalValidation() { return issue }
        if let issue = paymentAmountValidation() { return issue }
        return paymentScheduleValidation()
    }

    private func firstMissingRequired(
        _ fields: [(label: String, value: String)],
        tab: DirectBookingTab
    ) -> BookingValidationIssue? {
        guard let missing = fields.first(where: { $0.value.directBookingNilIfBlank == nil }) else {
            return nil
        }
        return ("\(missing.label) is required", tab)
    }

    private func requiredClientIdentityValidation(mobile: String) -> BookingValidationIssue? {
        firstMissingRequired([
            ("Mobile Number", mobile),
            ("Title", booking.title),
            ("Client Name", booking.name),
            ("Father / Spouse Name", booking.fatherSpouseName),
            ("Date of Birth", booking.dateOfBirth),
            ("Alternate Numbers", booking.alternateNumbers),
            ("WhatsApp Number", booking.whatsappNumber),
            ("Email", booking.email),
            ("Nationality", booking.nationality)
        ], tab: .client)
    }

    private func requiredClientAddressValidation() -> BookingValidationIssue? {
        firstMissingRequired([
            ("Home Address — Door No", booking.homeDoorNo),
            ("Home Address — Street Name", booking.homeStreetName),
            ("Pincode", booking.pincode),
            ("District", booking.district),
            ("Home Address — Address Line 1", booking.homeAddressLine1)
        ], tab: .client)
    }

    private func requiredClientWorkValidation() -> BookingValidationIssue? {
        firstMissingRequired([
            ("Profession", booking.profession),
            ("Designation", booking.designation),
            ("Income Per Annum", booking.incomePerAnnum),
            ("Office Name", booking.officeName),
            ("Office Door No", booking.officeDoorNo),
            ("Office Street Name", booking.officeStreetName),
            ("Office Address Line 1", booking.officeAddressLine1)
        ], tab: .client)
    }

    private func requiredBookingDetailsValidation() -> BookingValidationIssue? {
        firstMissingRequired([
            ("Booking Type", booking.bookingType),
            ("CEF No", booking.cefNo),
            ("Booking Date", booking.bookingDate),
            ("Project", selectedProject?.id ?? booking.projectId),
            ("Plot", selectedUnit?.id ?? booking.plotId),
            ("Property Type", booking.propertyType),
            ("Booking Cost", booking.bookingCost),
            ("Guideline Value", booking.guidelineValue)
        ], tab: .bookingFinance)
    }

    private func requiredFinanceDetailsValidation() -> BookingValidationIssue? {
        firstMissingRequired([
            ("Promotional Offer", booking.promotionalOffers),
            ("Offer Value", booking.promotionalOfferValue),
            ("Terms & Conditions", booking.promotionalOffersTnC),
            ("Registration Charges", booking.registrationCharges),
            ("GST Amount", booking.gstAmount),
            ("Document Charges", booking.documentCharges),
            ("Patta Charges", booking.pattaCharges),
            ("Other Charges", booking.otherCharges),
            ("Customer Payment Category", booking.customerPaymentCategory),
            ("Advance Booking Payment", booking.bookingMode),
            ("Advance Amount", booking.advanceAmount)
        ], tab: .bookingFinance)
    }

    private func requiredPaymentStaffValidation() -> BookingValidationIssue? {
        firstMissingRequired([
            ("Allotment Due Amount", booking.allotmentDueAmount),
            ("Allotment Due Date", booking.allotmentDueDate),
            ("Preferred Registration Date", booking.preferredRegistrationDate),
            ("AVP", booking.originalAvpStaffId),
            ("General Manager", booking.originalGmStaffId),
            ("Senior Manager", booking.originalSeniorManagerStaffId),
            ("BDO", booking.originalBdoStaffId),
            ("Telecaller", booking.originalTelecallerStaffId)
        ], tab: .paymentStaff)
    }

    private func requiredIdentityDocumentsValidation() -> BookingValidationIssue? {
        firstMissingRequired([
            ("Aadhaar Number", booking.aadhaar),
            ("Aadhaar Upload", booking.aadhaarDocumentStorageId),
            ("PAN Number", booking.pan),
            ("PAN Upload", booking.panDocumentStorageId)
        ], tab: .paymentStaff)
    }

    private func requiredReferencesValidation() -> BookingValidationIssue? {
        firstMissingRequired([
            ("Reference 1 — Name", booking.referenceName1),
            ("Reference 1 — Relation", booking.referenceProfession1),
            ("Reference 1 — Mobile", booking.referenceMobile1),
            ("Reference 2 — Name", booking.referenceName2),
            ("Reference 2 — Relation", booking.referenceProfession2),
            ("Reference 2 — Mobile", booking.referenceMobile2),
            ("Document to be Prepared In", booking.docPreparedIn)
        ], tab: .paymentStaff)
    }

    private func clientConditionalValidation(mobile: String) -> BookingValidationIssue? {
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
        if booking.pincode.filter(\.isNumber).count != 6 {
            return ("Pincode must be exactly 6 digits", .client)
        }
        if booking.aadhaar.filter(\.isNumber).count != 12 { return ("Aadhaar Number must be exactly 12 digits", .paymentStaff) }
        return nil
    }

    private func bookingTypeConditionalValidation() -> BookingValidationIssue? {
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
        return nil
    }

    private func financeConditionalValidation() -> BookingValidationIssue? {
        if (Double(booking.specialConsideration) ?? 0) > 0 {
            if booking.discountApprovedBy.directBookingNilIfBlank == nil { return ("Discount Approved By is required", .bookingFinance) }
            if booking.specialConsiderationReason.directBookingNilIfBlank == nil { return ("SC Reason is required", .bookingFinance) }
            if (Double(booking.specialConsiderationValidity) ?? 0) <= 0 { return ("SC Validity is required", .bookingFinance) }
        }
        if (Double(booking.specialConsideration) ?? 0) > (Double(booking.bookingCost) ?? 0) {
            return ("Special Consideration cannot exceed the Booking Cost", .bookingFinance)
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
        return nil
    }

    private func paymentAmountValidation() -> BookingValidationIssue? {
        let advanceAmount = Double(booking.advanceAmount) ?? 0
        if let minimumAdvanceAmount = configuredMinimumAdvance,
           advanceAmount < minimumAdvanceAmount {
            return ("Advance must be at least \(AppModuleFormatters.rupees(minimumAdvanceAmount)) as set in Project Details", .bookingFinance)
        }
        let totalPayableAmount = booking.bookingType == "EXCHANGE"
            ? booking.exchangeBalancePayable
            : (booking.totalPayableAmount ?? 0)
        if advanceAmount > totalPayableAmount {
            return ("Advance cannot exceed the total payable amount", .bookingFinance)
        }
        if booking.customerPaymentCategory == "B" {
            let bankLoanAmount = Double(booking.loanAmountRequested) ?? 0
            if bankLoanAmount > totalPayableAmount {
                return ("Bank Loan Amount cannot exceed the Total Property Cost", .bookingFinance)
            }
            if advanceAmount > max(totalPayableAmount - bankLoanAmount, 0) {
                return ("Advance cannot exceed the Customer Payable Amount after excluding the bank loan", .bookingFinance)
            }
        }
        return nil
    }

    private func paymentScheduleValidation() -> BookingValidationIssue? {
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
        unitListTask?.cancel()
        unitLoadGeneration += 1
        plotPrefillTask?.cancel()
        bookingTypeAutofillTask?.cancel()
        booking = DirectBookingDraft()
        selectedProject = initialProject
        selectedProjectSpecialPaymentEnabled = initialProject?.specialPaymentEnabled
        selectedUnit = initialUnit
        availableUnits = []
        unitsProjectId = nil
        unitLoadError = nil
        isLoadingUnits = false
        showUnitPicker = false
        plotPrefill = nil
        lastAutoFilledPlotId = nil
        plotPrefillError = nil
        isLoadingPlotPrefill = false
        conversionPrefill = nil
        exchangeSourceCandidates = []
        bookingTypeAutofillError = nil
        isLoadingBookingTypeAutofill = false
        showExchangeProjectPicker = false
        showExchangeSourcePicker = false
        showInternalExchangePlotPicker = false
        selectedLead = nil
        matchedClient = nil
        leadMatches = []
        if let initialProject {
            booking.projectId = initialProject.id
            booking.projectName = initialProject.name ?? ""
            applyProjectOffer(
                name: initialProject.promoOffer,
                value: initialProject.projectOfferValue,
                terms: initialProject.projectOfferTerms,
                validityDays: initialProject.projectOfferValidityDays
            )
        }
        if let initialUnit {
            booking.plotId = initialUnit.id
            booking.plotNo = initialUnit.unitNumber ?? ""
        }
        clearDraft()
        if let initialProject {
            startUnitLoad(for: initialProject, presentWhenReady: false)
            Task {
                await resolveSelectedProjectSpecialPaymentIfNeeded(
                    overwriteProjectOffer: true
                )
            }
        }
        if let initialUnit {
            plotPrefillTask = Task {
                await loadPlotPrefill(for: initialUnit)
            }
        }
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
        booking.migrateLegacyHomeAddressIfNeeded()
        booking.migrateLegacyOfficeAddressIfNeeded()
        if homeAddressCoordinate != nil {
            homeCoordinateAddressQuery = booking.homeAddressSearchText
        }
        scheduleHomeAddressGeocode()
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

    private static let promotionalTermsOptions = [
        DirectBookingOption(value: "7days", label: "Registration within 7 days"),
        DirectBookingOption(value: "15days", label: "Registration within 15 days"),
        DirectBookingOption(value: "30days", label: "Registration within 30 days")
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
}

private struct DirectBookingPaymentDraft: Codable, Equatable, Sendable {
    var amount = ""
    var dueDate = ""
}

private struct DirectBookingFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(title.directBookingFieldTitle)
            if title.directBookingFieldIsRequired {
                Text("*")
                    .foregroundStyle(Color.red)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color(hex: 0x475467))
    }
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
    var homeDoorNo = ""
    var homeStreetName = ""
    var homeAddressLine1 = ""
    var homeAddressLine2 = ""
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
    var conversionManualEntry = false
    var manualConversionProjectName = ""
    var manualConversionPlotNo = ""
    var manualConversionCredit = ""
    var conversionNotes = ""
    var linkedConversionBookingId: String?
    var linkedConversionBookingRefNo: String?
    var linkedConversionProjectName: String?
    var linkedConversionPlotNo: String?
    var linkedConversionCredit: String?
    var sourceExchangeBookingId = ""
    var exchangeManualEntry = false
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

    var composedHomeAddress: String? {
        let composed = [
            ("Door No", homeDoorNo),
            ("Street Name", homeStreetName),
            ("Address Line 1", homeAddressLine1),
            ("Address Line 2", homeAddressLine2)
        ]
            .compactMap { label, value -> String? in
                guard let value = value.directBookingNilIfBlank else { return nil }
                return "\(label): \(value)"
            }
            .joined(separator: ", ")
        return composed.directBookingNilIfBlank ?? homeAddress.directBookingNilIfBlank
    }

    var homeAddressSearchText: String {
        [homeDoorNo, homeStreetName, homeAddressLine1, homeAddressLine2, district, pincode]
            .compactMap(\.directBookingNilIfBlank)
            .joined(separator: ", ")
    }

    var hasMinimumHomeAddressForGeocoding: Bool {
        homeDoorNo.directBookingNilIfBlank != nil
            && homeStreetName.directBookingNilIfBlank != nil
            && homeAddressLine1.directBookingNilIfBlank != nil
            && district.directBookingNilIfBlank != nil
            && pincode.filter(\.isNumber).count == 6
    }

    mutating func migrateLegacyHomeAddressIfNeeded() {
        guard let legacyAddress = homeAddress.directBookingNilIfBlank else { return }

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
            case "door no", "door number":
                if homeDoorNo.directBookingNilIfBlank == nil { homeDoorNo = value }
            case "street", "street name":
                if homeStreetName.directBookingNilIfBlank == nil { homeStreetName = value }
            case "address", "address line 1":
                if homeAddressLine1.directBookingNilIfBlank == nil { homeAddressLine1 = value }
            case "floor", "area", "address line 2":
                if homeAddressLine2.directBookingNilIfBlank == nil { homeAddressLine2 = value }
            default:
                continue
            }
            foundLabel = true
        }
        if !foundLabel {
            if homeDoorNo.directBookingNilIfBlank == nil, parts.indices.contains(0) { homeDoorNo = parts[0] }
            if homeStreetName.directBookingNilIfBlank == nil, parts.indices.contains(1) { homeStreetName = parts[1] }
            if homeAddressLine1.directBookingNilIfBlank == nil, parts.indices.contains(2) { homeAddressLine1 = parts[2] }
            if homeAddressLine2.directBookingNilIfBlank == nil, parts.indices.contains(3) { homeAddressLine2 = parts[3] }
        }
        homeAddress = ""
    }

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

    static func amountInputText(_ amount: Double) -> String {
        guard amount.isFinite else { return "" }
        if amount.rounded() == amount,
           amount >= Double(Int64.min),
           amount <= Double(Int64.max) {
            return String(Int64(amount))
        }
        return String(amount)
    }

    func numericAmount(_ value: String) -> Double {
        let amount = Double(value) ?? 0
        return amount.isFinite ? amount : 0
    }

    var totalPayableAmount: Double? {
        guard let agreedAmount else { return nil }
        let registration = Double(registrationCharges) ?? 0
        let gst = gstApplicable ? (Double(gstAmount) ?? 0) : 0
        let document = Double(documentCharges) ?? 0
        let patta = Double(pattaCharges) ?? 0
        let other = otherChargesApplicable ? (Double(otherCharges) ?? 0) : 0
        return agreedAmount + registration + gst + document + patta + other
    }

    var exchangeBalancePayable: Double {
        max((totalPayableAmount ?? 0) - (Double(exchangeOldRegisteredValue) ?? 0), 0)
    }

    var payableAmountForBooking: Double? {
        guard let totalPayableAmount else { return nil }
        return bookingType == "EXCHANGE" ? exchangeBalancePayable : totalPayableAmount
    }

    var customerPayableAmount: Double? {
        guard let payableAmountForBooking else { return nil }
        let bankLoan = customerPaymentCategory == "B" ? numericAmount(loanAmountRequested) : 0
        return max(payableAmountForBooking - bankLoan, 0)
    }

    var balanceAfterAdvance: Double? {
        guard let payableAmountForBooking else { return nil }
        let conversionCredit = bookingType == "CONVERSION"
            ? numericAmount(conversionManualEntry ? manualConversionCredit : (linkedConversionCredit ?? ""))
            : 0
        return max(payableAmountForBooking - numericAmount(advanceAmount) - conversionCredit, 0)
    }

    var isEmpty: Bool {
        [
            phone, name, projectName, plotNo, bookingCost, advanceAmount, email, homeAddress,
            homeDoorNo, homeStreetName, homeAddressLine1, homeAddressLine2,
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
        let includesPaymentProof = isOnlinePayment || bookingMode == "CHEQUE"
        let flexiSchedule = freePayment
            ? flexiPaymentRows.compactMap { row -> BookingPaymentScheduleItem? in
                guard let amount = Double(row.amount), let dueDate = row.dueDate.directBookingNilIfBlank else { return nil }
                return BookingPaymentScheduleItem(amount: amount, dueDate: dueDate)
            }
            : []
        let total = bookingType == "EXCHANGE" ? exchangeBalancePayable : totalPayableAmount
        let conversionCredit = bookingType == "CONVERSION"
            ? (Double(conversionManualEntry ? manualConversionCredit : (linkedConversionCredit ?? "")) ?? 0)
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
            advancePaymentProofStorageId: includesPaymentProof ? advancePaymentProofStorageId.directBookingNilIfBlank : nil,
            advancePaymentProofFileName: includesPaymentProof ? advancePaymentProofFileName.directBookingNilIfBlank : nil,
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
            homeAddress: composedHomeAddress,
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

private struct DirectBookingClientImagePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
}

private struct DirectBookingClientImagePreview: View {
    let preview: DirectBookingClientImagePreviewItem

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var restingScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                AsyncImage(url: preview.url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .gesture(zoomGesture)
                            .onTapGesture(count: 2) {
                                withAnimation(.snappy(duration: 0.22)) {
                                    let nextScale: CGFloat = scale > 1 ? 1 : 2.5
                                    scale = nextScale
                                    restingScale = nextScale
                                }
                            }
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 42, weight: .semibold))
                            Text("Unable to load client photo")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.72))
                    case .empty:
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    @unknown default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 12)
            }
            .navigationTitle(preview.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel("Close preview")
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(restingScale * value.magnification, 1), 5)
            }
            .onEnded { value in
                let finalScale = min(max(restingScale * value.magnification, 1), 5)
                scale = finalScale
                restingScale = finalScale
            }
    }
}

private struct DirectBookingPayableSummaryCard: View {
    let landCost: Double
    let gst: Double
    let registrationCharges: Double
    let documentCharges: Double
    let pattaCharges: Double
    let otherCharges: Double
    let grossBookingValue: Double
    let exchangeValue: Double?
    let totalPayable: Double
    let minimumAdvance: Double
    let advanceEntered: Double
    let customerPayable: Double?
    let bankLoanAmount: Double?
    let balanceAfterAdvance: Double
    let isExchange: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Client Payable Summary", systemImage: "list.bullet.rectangle.portrait")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            VStack(spacing: 10) {
                DirectBookingMoneySummaryRow(label: "Total land cost", value: landCost)
                DirectBookingMoneySummaryRow(label: "GST", value: gst)
                DirectBookingMoneySummaryRow(label: "Registration charges", value: registrationCharges)
                DirectBookingMoneySummaryRow(label: "Document charges", value: documentCharges)
                DirectBookingMoneySummaryRow(label: "Patta charges", value: pattaCharges)
                DirectBookingMoneySummaryRow(label: "Other charges", value: otherCharges)

                Divider()

                if isExchange {
                    DirectBookingMoneySummaryRow(label: "Total booking value", value: grossBookingValue)
                    DirectBookingMoneySummaryRow(label: "Less: Exchange value", value: -(exchangeValue ?? 0))
                }
                DirectBookingMoneySummaryRow(
                    label: isExchange ? "Balance payable" : "Total amount payable",
                    value: totalPayable,
                    isStrong: true
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("PAYMENT POSITION")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color(hex: 0x667085))

                Text("Enter the advance below. The client may pay more than the project minimum.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: 0x667085))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    DirectBookingMoneySummaryRow(label: "Minimum advance", value: minimumAdvance)
                    DirectBookingMoneySummaryRow(label: "Advance entered", value: advanceEntered)
                    if let customerPayable, let bankLoanAmount {
                        DirectBookingMoneySummaryRow(label: "Customer payable amount", value: customerPayable)
                        DirectBookingMoneySummaryRow(label: "Final bank loan payment", value: bankLoanAmount)
                    }
                    Divider()
                    DirectBookingMoneySummaryRow(
                        label: "Balance after advance",
                        value: balanceAfterAdvance,
                        isStrong: true
                    )
                }
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xDDE3EA), lineWidth: 1))
    }
}

private struct DirectBookingMoneySummaryRow: View {
    let label: String
    let value: Double
    var isStrong = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(isStrong ? Color(hex: 0x101828) : Color(hex: 0x667085))
            Spacer(minLength: 12)
            Text(AppModuleFormatters.rupees(value))
                .foregroundStyle(Color(hex: 0x101828))
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: isStrong ? 14 : 13, weight: isStrong ? .bold : .medium))
    }
}

private struct DirectBookingReadOnlyField: View {
    let title: String
    let value: String
    let placeholder: String
    let icon: String

    init(
        _ title: String,
        value: String,
        placeholder: String = "",
        icon: String = "doc.text"
    ) {
        self.title = title
        self.value = value
        self.placeholder = placeholder
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DirectBookingFieldLabel(title)
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color(hex: 0x98A2B3))
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18)
                Text(value.directBookingNilIfBlank ?? placeholder)
                    .foregroundStyle(value.directBookingNilIfBlank == nil ? Color(hex: 0x98A2B3) : Color(hex: 0x475467))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(Color(hex: 0xF2F4F7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }
}

private struct DirectBookingTypeSummaryItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct DirectBookingLeadLookupStatus: View {
    let isSearching: Bool
    let matchedClientName: String?
    let linkedLeadName: String?
    let canChooseLinkedLead: Bool
    let onChooseLinkedLead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching client details...")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color(hex: 0x667085))
            }

            if let matchedClientName {
                Label(
                    "Existing client details auto-filled for \(matchedClientName)",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x187A2F))
            }

            if let linkedLeadName {
                VStack(alignment: .leading, spacing: 6) {
                    DirectBookingFieldLabel("Linked Lead *")
                    Button {
                        guard canChooseLinkedLead else { return }
                        onChooseLinkedLead()
                    } label: {
                        Label(linkedLeadName, systemImage: "person.badge.checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(hex: 0x2DAE12))
                }
            }
        }
    }
}

private struct DirectBookingTypeSummaryCard: View {
    let items: [DirectBookingTypeSummaryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.label)
                        .foregroundStyle(Color(hex: 0x667085))
                    Spacer(minLength: 12)
                    Text(item.value)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(hex: 0x101828))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(14)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xDDE3EA), lineWidth: 1))
    }
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
            DirectBookingFieldLabel(title)
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
            DirectBookingFieldLabel(title)
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
                        DatePicker(title.directBookingFieldTitle, selection: $date, in: Date.distantPast...maxDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                    } else {
                        DatePicker(title.directBookingFieldTitle, selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                    }
                }
                .navigationTitle(title.directBookingFieldTitle)
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
    var directBookingFieldIsRequired: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("*")
    }

    var directBookingFieldTitle: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("*") else { return trimmed }
        return String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var directBookingNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var directBookingNormalizedPersonName: String {
        split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .uppercased()
    }

    mutating func directBookingFillIfBlank(with candidate: String?) {
        guard directBookingNilIfBlank == nil,
              let candidate = candidate?.directBookingNilIfBlank else { return }
        self = candidate
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
