import SwiftUI

struct BookingsListView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var bookings: [AppBooking] = []
    @State private var selectedStatus: BookingStatusFilter = .all
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var selectedBooking: AppBooking?

    private var canCreateBooking: Bool {
        authStore.hasPermission("marketing.bookings.create")
    }

    private var filteredBookings: [AppBooking] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bookings.filter { booking in
            guard !query.isEmpty else { return true }
            return [
                booking.bookingRefNo,
                booking.clientName,
                booking.mobileNumber,
                booking.projectName,
                booking.plotNo,
                booking.source,
                booking.displayStatus
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            content
        }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("Booking")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Bookings"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Booking")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
            }

            if canCreateBooking {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .accessibilityLabel("Create booking")
                }
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: {
            Task { await load() }
        }) {
            BookingCreateView()
            .appLibraryNativeSheet([.height(720), .large])
            .presentationBackground(Color.white)
        }
        .sheet(item: $selectedBooking, onDismiss: {
            Task { await load() }
        }) { booking in
            BookingDetailView(bookingId: booking.id) {
                Task { await load() }
            }
            .appLibraryNativeSheet([.medium, .large])
        }
        .task { if !hasLoaded { await load() } }
        .onChange(of: selectedStatus) { _, _ in
            Task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && bookings.isEmpty {
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    BookingSkeletonCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if let errorMessage, bookings.isEmpty {
            BookingEmptyState(
                title: "Unable to load bookings",
                message: errorMessage,
                systemImage: "exclamationmark.triangle"
            )
        } else if filteredBookings.isEmpty {
            BookingEmptyState(
                title: "No Booking Yet",
                message: "Stay organized by creating bookings. They will appear here for review, confirmation, and tracking.",
                systemImage: "doc.text.magnifyingglass"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredBookings) { booking in
                        Button {
                            selectedBooking = booking
                        } label: {
                            BookingRow(booking: booking)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .refreshable { await load() }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BookingStatusFilter.allCases) { status in
                    Button {
                        guard selectedStatus != status else { return }
                        selectedStatus = status
                    } label: {
                        Text(status.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedStatus == status ? .white : Color(hex: 0x475467))
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(selectedStatus == status ? Color(hex: 0x0B61CA) : Color.white, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color(hex: 0xE5E7EB), lineWidth: selectedStatus == status ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(hex: 0xF1F3F8))
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
            bookings = try await MarketingConvexAPIService.listBookings(
                token: token,
                status: selectedStatus.apiValue
            )
                .sorted { ($0.bookingDate ?? "") > ($1.bookingDate ?? "") }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BookingEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(Color(hex: 0x98A2B3))
                .frame(width: 112, height: 96)
                .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x667085))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private enum BookingDrawerTab: String, CaseIterable, Identifiable {
    case approval
    case client
    case bookingFinance
    case paymentStaff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approval: return "Approval"
        case .client: return "Client Details"
        case .bookingFinance: return "Booking & Finance"
        case .paymentStaff: return "Payment & Staff"
        }
    }
}

private struct BookingDrawerGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        }
    }
}

private struct BookingDrawerGridItem: View {
    let title: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x667085))
                .lineLimit(2)
            Text(value?.nilIfBlank ?? "-")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 50, alignment: .topLeading)
        .padding(11)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct BookingDrawerEditDraft {
    var clientName = ""
    var mobileNumber = ""
    var title = ""
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
    var bookingDate = ""
    var bookingType = ""
    var bookingMode = ""
    var bookingCost = ""
    var guidelineValue = ""
    var advanceAmount = ""
    var registrationCharges = ""
    var gstAmount = ""
    var documentCharges = ""
    var pattaCharges = ""
    var otherCharges = ""
    var paymentMode = ""
    var profession = ""
    var designation = ""
    var incomePerAnnum = ""
    var officeName = ""
    var officeEmail = ""
    var officeMobile = ""
    var officePhone = ""
    var officeAddress = ""
    var notes = ""

    init() {}

    init(booking: AppBooking) {
        clientName = booking.clientName ?? ""
        mobileNumber = booking.mobileNumber ?? ""
        title = booking.title ?? ""
        fatherSpouseName = booking.fatherSpouseName ?? ""
        dateOfBirth = booking.dateOfBirth ?? ""
        anniversaryDate = booking.anniversaryDate ?? ""
        alternateNumbers = booking.alternateNumbers ?? ""
        whatsappNumber = booking.whatsappNumber ?? ""
        email = booking.email ?? ""
        nationality = booking.nationality ?? ""
        homeAddress = booking.homeAddress ?? ""
        pincode = booking.pincode ?? ""
        state = booking.state ?? ""
        district = booking.district ?? ""
        location = booking.location ?? ""
        bookingDate = booking.bookingDate ?? ""
        bookingType = booking.bookingType ?? ""
        bookingMode = booking.bookingMode ?? ""
        bookingCost = Self.numberText(booking.bookingCost)
        guidelineValue = Self.numberText(booking.guidelineValue)
        advanceAmount = Self.numberText(booking.advanceAmount)
        registrationCharges = Self.numberText(booking.registrationCharges)
        gstAmount = Self.numberText(booking.gstAmount)
        documentCharges = Self.numberText(booking.documentCharges)
        pattaCharges = Self.numberText(booking.pattaCharges)
        otherCharges = Self.numberText(booking.otherCharges)
        paymentMode = booking.paymentMode ?? booking.bookingMode ?? ""
        profession = booking.profession ?? ""
        designation = booking.designation ?? ""
        incomePerAnnum = booking.incomePerAnnum ?? ""
        officeName = booking.officeName ?? ""
        officeEmail = booking.officeEmail ?? ""
        officeMobile = booking.officeMobile ?? ""
        officePhone = booking.officePhone ?? ""
        officeAddress = booking.officeAddress ?? ""
        notes = booking.notes ?? ""
    }

    func updateRequest(id: String) -> UpdateBookingRequest {
        UpdateBookingRequest(
            id: id,
            clientName: clientName.nilIfBlank,
            mobileNumber: AppModuleFormatters.normalizePhone(mobileNumber).nilIfBlank,
            bookingDate: bookingDate.nilIfBlank,
            bookingCost: Self.doubleValue(bookingCost),
            advanceAmount: Self.doubleValue(advanceAmount),
            notes: notes.nilIfBlank,
            title: title.nilIfBlank,
            fatherSpouseName: fatherSpouseName.nilIfBlank,
            dateOfBirth: dateOfBirth.nilIfBlank,
            anniversaryDate: anniversaryDate.nilIfBlank,
            alternateNumbers: AppModuleFormatters.normalizePhone(alternateNumbers).nilIfBlank,
            whatsappNumber: AppModuleFormatters.normalizePhone(whatsappNumber).nilIfBlank,
            email: email.nilIfBlank,
            nationality: nationality.nilIfBlank,
            homeAddress: homeAddress.nilIfBlank,
            pincode: pincode.nilIfBlank,
            state: state.nilIfBlank,
            district: district.nilIfBlank,
            location: location.nilIfBlank,
            profession: profession.nilIfBlank,
            designation: designation.nilIfBlank,
            incomePerAnnum: incomePerAnnum.nilIfBlank,
            officeName: officeName.nilIfBlank,
            officeEmail: officeEmail.nilIfBlank,
            officeMobile: AppModuleFormatters.normalizePhone(officeMobile).nilIfBlank,
            officePhone: AppModuleFormatters.normalizePhone(officePhone).nilIfBlank,
            officeAddress: officeAddress.nilIfBlank,
            bookingType: bookingType.nilIfBlank,
            bookingMode: bookingMode.nilIfBlank,
            guidelineValue: Self.doubleValue(guidelineValue),
            registrationCharges: Self.doubleValue(registrationCharges),
            gstAmount: Self.doubleValue(gstAmount),
            documentCharges: Self.doubleValue(documentCharges),
            pattaCharges: Self.doubleValue(pattaCharges),
            otherCharges: Self.doubleValue(otherCharges),
            paymentMode: paymentMode.nilIfBlank
        )
    }

    private static func numberText(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(value)
    }

    private static func doubleValue(_ value: String) -> Double? {
        let cleaned = value
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : Double(cleaned)
    }
}

private struct BookingSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                skeleton(width: 160, height: 16)
                Spacer()
                skeleton(width: 72, height: 22)
            }
            skeleton(width: 230, height: 12)
            HStack {
                skeleton(width: 120, height: 14)
                Spacer()
                skeleton(width: 74, height: 14)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
    }

    private func skeleton(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(hex: 0xE5E7EB))
            .frame(width: width, height: height)
            .redacted(reason: .placeholder)
    }
}

private struct BookingDetailView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let bookingId: String
    let onChanged: () -> Void

    @State private var booking: AppBooking?
    @State private var selectedTab: BookingDrawerTab = .approval
    @State private var isEditing = false
    @State private var editDraft = BookingDrawerEditDraft()
    @State private var isLoading = false
    @State private var activeLoadID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showReject = false
    @State private var rejectReason = ""

    var body: some View {
        Group {
            if isLoading && booking == nil {
                ProgressView("Loading booking...")
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
            } else if let booking {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        bookingDrawerHeader(booking)
                        bookingDrawerTabs
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .background(Color.white)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(hex: 0xEAECF0))
                            .frame(height: 1)
                    }

                    ScrollView {
                        bookingDrawerBody(booking)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, isEditing ? 104 : 28)
                    }
                    .background(Color(hex: 0xF6F8FB))
                    .refreshable { await load() }

                    fixedSaveFooter
                }
            }
        }
        .background(Color(hex: 0xF6F8FB).ignoresSafeArea())
        .appCompactSheetCTAContainer()
        .task { await load() }
        .alert("Reject Booking", isPresented: $showReject) {
            TextField("Reason", text: $rejectReason)
            Button("Cancel", role: .cancel) { rejectReason = "" }
            Button("Reject", role: .destructive) {
                Task { await reject() }
            }
        } message: {
            Text("Enter reject reason.")
        }
        .alert("Booking", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func bookingDrawerHeader(_ booking: AppBooking) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.bookingRefNo?.nilIfBlank ?? "Booking")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(booking.clientName?.nilIfBlank ?? "Unnamed client")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x475467))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    if !isEditing {
                        editDraft = BookingDrawerEditDraft(booking: booking)
                    }
                    isEditing.toggle()
                } label: {
                    Label(isEditing ? "View" : "Edit", systemImage: isEditing ? "eye" : "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(Color(hex: 0xEFF6FF), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x344054))
                        .frame(width: 34, height: 34)
                        .background(Color(hex: 0xF2F4F7), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            HStack(spacing: 8) {
                BookingStatusPill(status: booking.displayStatus)

                Label(booking.projectName?.nilIfBlank ?? booking.projectId?.nilIfBlank ?? "No project", systemImage: "building.2")
                    .lineLimit(1)

                if let plot = booking.plotNo?.nilIfBlank {
                    Label("Plot \(plot)", systemImage: "square.grid.2x2")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(hex: 0x667085))
        }
    }

    private var bookingDrawerTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BookingDrawerTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? .white : Color(hex: 0x475467))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(selectedTab == tab ? Color(hex: 0x0B61CA) : Color(hex: 0xF8FAFC), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color(hex: 0xEAECF0), lineWidth: selectedTab == tab ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func bookingDrawerBody(_ booking: AppBooking) -> some View {
        switch selectedTab {
        case .approval:
            approvalTab(booking)
        case .client:
            clientTab(booking)
        case .bookingFinance:
            bookingFinanceTab(booking)
        case .paymentStaff:
            paymentStaffTab(booking)
        }
    }

    private func approvalTab(_ booking: AppBooking) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            BookingDrawerGrid {
                BookingDrawerGridItem(title: "Client", value: booking.clientName)
                BookingDrawerGridItem(title: "Mobile", value: booking.mobileNumber)
                BookingDrawerGridItem(title: "Project", value: booking.projectName ?? booking.projectId)
                BookingDrawerGridItem(title: "Plot", value: booking.plotNo)
                BookingDrawerGridItem(title: "Status", value: booking.displayStatus.capitalized)
                BookingDrawerGridItem(title: "Approval Stage", value: booking.approvalStatus)
                BookingDrawerGridItem(title: "Agreed Amount", value: booking.bookingCost.map(AppModuleFormatters.rupees))
                BookingDrawerGridItem(title: "Advance", value: booking.advanceAmount.map(AppModuleFormatters.rupees))
                BookingDrawerGridItem(title: "Telecaller", value: "-")
                BookingDrawerGridItem(title: "Source AVP", value: "-")
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Approval Timeline", systemImage: "checkmark.seal")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                Text(
                    booking.displayStatus.lowercased().contains("draft")
                    ? "Approval starts when the draft is submitted for confirmation."
                    : "Approval status will update as managers review this booking."
                )
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x667085))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
            }

            if !booking.displayStatus.lowercased().contains("draft") {
                HStack(spacing: 10) {
                    Button("Approve") { Task { await approve() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: 0x0B61CA))
                    Button("Reject", role: .destructive) { showReject = true }
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .disabled(isSaving)
            }
        }
    }

    private func clientTab(_ booking: AppBooking) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            drawerSectionHeader("Personal Information", systemImage: "person.text.rectangle")
            drawerField("Mobile Number", text: $editDraft.mobileNumber, value: booking.mobileNumber, keyboard: .phonePad)
            drawerField("Title", text: $editDraft.title, value: booking.title)
            drawerField("Client Name", text: $editDraft.clientName, value: booking.clientName)
            drawerField("Father / Spouse Name", text: $editDraft.fatherSpouseName, value: booking.fatherSpouseName)
            drawerField("Date of Birth", text: $editDraft.dateOfBirth, value: formattedDrawerDate(booking.dateOfBirth))
            drawerField("Anniversary Date", text: $editDraft.anniversaryDate, value: formattedDrawerDate(booking.anniversaryDate))
            drawerField("Nationality", text: $editDraft.nationality, value: booking.nationality)

            drawerSectionHeader("Contact Details", systemImage: "phone")
            drawerField("Alternate Numbers", text: $editDraft.alternateNumbers, value: booking.alternateNumbers, keyboard: .phonePad)
            drawerField("WhatsApp Number", text: $editDraft.whatsappNumber, value: booking.whatsappNumber, keyboard: .phonePad)
            drawerField("Email", text: $editDraft.email, value: booking.email, keyboard: .emailAddress)

            drawerSectionHeader("Home Address", systemImage: "house")
            drawerField("Home Address", text: $editDraft.homeAddress, value: booking.homeAddress, axis: .vertical)
            drawerField("Pincode", text: $editDraft.pincode, value: booking.pincode, keyboard: .numberPad)
            drawerField("State", text: $editDraft.state, value: booking.state)
            drawerField("District", text: $editDraft.district, value: booking.district)
            drawerField("Location", text: $editDraft.location, value: booking.location)
        }
    }

    private func bookingFinanceTab(_ booking: AppBooking) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            drawerSectionHeader("Booking Details", systemImage: "doc.text")
            drawerField("Booking Reference", text: .constant(booking.bookingRefNo ?? ""), value: booking.bookingRefNo, editableOverride: false)
            drawerField("Booking Date", text: $editDraft.bookingDate, value: formattedDrawerDate(booking.bookingDate))
            drawerField("Project", text: .constant(booking.projectName ?? booking.projectId ?? ""), value: booking.projectName ?? booking.projectId, editableOverride: false)
            drawerField("Plot", text: .constant(booking.plotNo ?? ""), value: booking.plotNo, editableOverride: false)
            drawerField("Booking Type", text: $editDraft.bookingType, value: booking.bookingType)
            drawerField("Booking Mode", text: $editDraft.bookingMode, value: booking.bookingMode)

            drawerSectionHeader("Financial Summary", systemImage: "indianrupeesign.circle")
            drawerField("Booking Cost", text: $editDraft.bookingCost, value: booking.bookingCost.map(AppModuleFormatters.rupees), keyboard: .decimalPad)
            drawerField("Guideline Value", text: $editDraft.guidelineValue, value: booking.guidelineValue.map(AppModuleFormatters.rupees), keyboard: .decimalPad)
            drawerField("Advance Amount", text: $editDraft.advanceAmount, value: booking.advanceAmount.map(AppModuleFormatters.rupees), keyboard: .decimalPad)
        }
    }

    private func paymentStaffTab(_ booking: AppBooking) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            drawerSectionHeader("Charges & Payment", systemImage: "creditcard")
            drawerField("Registration Charges", text: $editDraft.registrationCharges, value: booking.registrationCharges.map(AppModuleFormatters.rupees), keyboard: .decimalPad)
            drawerField("GST Amount", text: $editDraft.gstAmount, value: booking.gstAmount.map(AppModuleFormatters.rupees), keyboard: .decimalPad)
            drawerField("Document Charges", text: $editDraft.documentCharges, value: booking.documentCharges.map(AppModuleFormatters.rupees), keyboard: .decimalPad)
            drawerField("Patta Charges", text: $editDraft.pattaCharges, value: booking.pattaCharges.map(AppModuleFormatters.rupees), keyboard: .decimalPad)
            drawerField("Other Charges", text: $editDraft.otherCharges, value: booking.otherCharges.map(AppModuleFormatters.rupees), keyboard: .decimalPad)
            drawerField("Payment Mode", text: $editDraft.paymentMode, value: booking.paymentMode ?? booking.bookingMode)

            drawerSectionHeader("Professional Details", systemImage: "briefcase")
            drawerField("Profession", text: $editDraft.profession, value: booking.profession)
            drawerField("Designation", text: $editDraft.designation, value: booking.designation)
            drawerField("Income Per Annum", text: $editDraft.incomePerAnnum, value: booking.incomePerAnnum, keyboard: .decimalPad)

            drawerSectionHeader("Office Details", systemImage: "building.2")
            drawerField("Office Name", text: $editDraft.officeName, value: booking.officeName)
            drawerField("Office Email", text: $editDraft.officeEmail, value: booking.officeEmail, keyboard: .emailAddress)
            drawerField("Office Mobile", text: $editDraft.officeMobile, value: booking.officeMobile, keyboard: .phonePad)
            drawerField("Office Phone", text: $editDraft.officePhone, value: booking.officePhone, keyboard: .phonePad)
            drawerField("Office Address", text: $editDraft.officeAddress, value: booking.officeAddress, axis: .vertical)

            drawerSectionHeader("Additional Information", systemImage: "note.text")
            drawerField("Notes", text: $editDraft.notes, value: booking.notes, axis: .vertical)
        }
    }

    private func drawerSectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color(hex: 0x344054))
            .padding(.top, 8)
            .padding(.horizontal, 2)
    }

    private func formattedDrawerDate(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.nilIfBlank,
              let date = AppModuleFormatters.ymd.date(from: rawValue) else {
            return rawValue
        }
        return AppModuleFormatters.day.string(from: date)
    }

    private func drawerField(
        _ title: String,
        text: Binding<String>,
        value: String?,
        keyboard: UIKeyboardType = .default,
        axis: Axis = .horizontal,
        editableOverride: Bool? = nil
    ) -> some View {
        let editable = editableOverride ?? isEditing
        let displayValue = value?.nilIfBlank ?? "-"
        return Group {
            if editable {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))

                    TextField(title, text: text, axis: axis)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: 0x1D2939))
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(keyboard == .default ? .words : .never)
                        .autocorrectionDisabled(keyboard != .default)
                        .lineLimit(axis == .vertical ? 3...6 : 1...1)
                        .padding(.horizontal, 14)
                        .frame(minHeight: axis == .vertical ? 78 : 50)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
                        }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))

                    Text(displayValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(displayValue == "-" ? Color(hex: 0x98A2B3) : Color(hex: 0x101828))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var fixedSaveFooter: some View {
        if isEditing {
            VStack(spacing: 0) {
                Divider()
                    .overlay(Color(hex: 0xEAECF0))

                Button {
                    Task { await saveDrawerChanges() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    } else {
                        Text("Save Changes")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                }
                .buttonStyle(.plain)
                .background(Color(hex: 0x0B61CA), in: Capsule())
                .disabled(isSaving)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .background(Color.white)
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        defer {
            if activeLoadID == loadID {
                activeLoadID = nil
                isLoading = false
            }
        }
        do {
            let refreshedBooking = try await MarketingConvexAPIService.getBooking(token: token, id: bookingId)
            guard activeLoadID == loadID, !Task.isCancelled else { return }

            booking = refreshedBooking
            errorMessage = nil
            if !isEditing {
                editDraft = BookingDrawerEditDraft(booking: refreshedBooking)
            }
        } catch {
            guard activeLoadID == loadID, !isCancellationError(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    @MainActor
    private func saveDrawerChanges() async {
        guard let token = authStore.currentSession?.token, let booking else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await MarketingConvexAPIService.updateBooking(
                token: token,
                request: editDraft.updateRequest(id: booking.id)
            )
            isEditing = false
            await load()
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func approve() async {
        guard let token = authStore.currentSession?.token else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await MarketingConvexAPIService.approveBooking(token: token, id: bookingId)
            await load()
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reject() async {
        let reason = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            errorMessage = "Reject reason is required"
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        isSaving = true
        defer { isSaving = false; rejectReason = "" }
        do {
            try await MarketingConvexAPIService.rejectBooking(token: token, id: bookingId, reason: reason)
            await load()
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BookingUpdateSheet: View {
    @Environment(AuthStore.self) private var authStore
    let booking: AppBooking
    let onSaved: () async -> Void

    @State private var clientName: String
    @State private var mobileNumber: String
    @State private var bookingDate: String
    @State private var bookingCost: String
    @State private var advanceAmount: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(booking: AppBooking, onSaved: @escaping () async -> Void) {
        self.booking = booking
        self.onSaved = onSaved
        _clientName = State(initialValue: booking.clientName ?? "")
        _mobileNumber = State(initialValue: booking.mobileNumber ?? "")
        _bookingDate = State(initialValue: booking.bookingDate ?? "")
        _bookingCost = State(initialValue: booking.bookingCost.map { String($0) } ?? "")
        _advanceAmount = State(initialValue: booking.advanceAmount.map { String($0) } ?? "")
        _notes = State(initialValue: booking.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    BookingEditSection(title: "Client") {
                        BookingEditField(title: "Client name", placeholder: "Full name", text: $clientName)
                        BookingEditField(title: "Mobile number", placeholder: "10-digit mobile", text: $mobileNumber, keyboard: .phonePad)
                    }

                    BookingEditSection(title: "Booking") {
                        BookingEditField(title: "Booking date", placeholder: "yyyy-MM-dd", text: $bookingDate)
                        BookingEditField(title: "Booking cost", placeholder: "0", text: $bookingCost, keyboard: .decimalPad)
                        BookingEditField(title: "Advance amount", placeholder: "0", text: $advanceAmount, keyboard: .decimalPad)
                        BookingEditField(title: "Notes", placeholder: "Add notes", text: $notes, axis: .vertical)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save Changes") }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(isSaving)
                }
                .padding(16)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xB42318))
                        .padding(.horizontal, 16)
                }
            }
            .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
            .navigationTitle("Update Booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Task { await onSaved() } }
                }
            }
        }
        .appFormActivity()
    }

    @MainActor
    private func save() async {
        guard let token = authStore.currentSession?.token else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await MarketingConvexAPIService.updateBooking(
                token: token,
                request: UpdateBookingRequest(
                    id: booking.id,
                    clientName: clientName.nilIfBlank,
                    mobileNumber: AppModuleFormatters.normalizePhone(mobileNumber).nilIfBlank,
                    bookingDate: bookingDate.nilIfBlank,
                    bookingCost: Double(bookingCost.trimmingCharacters(in: .whitespacesAndNewlines)),
                    advanceAmount: Double(advanceAmount.trimmingCharacters(in: .whitespacesAndNewlines)),
                    notes: notes.nilIfBlank
                )
            )
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BookingDetailHero: View {
    let booking: AppBooking

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(booking.clientName?.nilIfBlank ?? "Unnamed client")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)

                    Text(booking.bookingRefNo?.nilIfBlank ?? "Reference not available")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineLimit(1)
                }

                Spacer()

                BookingStatusPill(status: booking.displayStatus)
            }

            HStack(spacing: 10) {
                BookingMetricChip(title: "Project", value: booking.projectName ?? booking.projectId)
                BookingMetricChip(title: "Plot", value: booking.plotNo)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
    }
}

private struct BookingMetricChip: View {
    let title: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
            Text(value?.nilIfBlank ?? "-")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: 0xF9FAFB), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct BookingDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            VStack(spacing: 10) {
                content
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
    }
}

private struct BookingDetailLine: View {
    let title: String
    let value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .frame(width: 104, alignment: .leading)

            Text(value?.nilIfBlank ?? "-")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x101828))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct BookingEditSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
    }
}

private struct BookingEditField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x475467))

            TextField(placeholder, text: $text, axis: axis)
                .font(.system(size: 13, weight: .medium))
                .keyboardType(keyboard)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .padding(.horizontal, 14)
                .padding(.vertical, axis == .vertical ? 12 : 0)
                .frame(minHeight: 48)
                .background(Color(hex: 0xF9FAFB), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct BookingRow: View {
    let booking: AppBooking

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Text(clientInitials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(statusTint)
                    .frame(width: 42, height: 42)
                    .background(statusTint.opacity(0.11), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.clientName?.nilIfBlank ?? "Unnamed client")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10, weight: .semibold))
                        Text(referenceText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(hex: 0x667085))
                }

                Spacer(minLength: 6)

                BookingStatusPill(status: booking.displayStatus)
            }

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "building.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PROJECT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0x98A2B3))
                        Text(projectText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x344054))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color(hex: 0xE4E7EC))
                    .frame(width: 1, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("PLOT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                    Text(plotText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x344054))
                        .lineLimit(1)
                }
                .frame(minWidth: 54, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            HStack(alignment: .center, spacing: 10) {
                Label(formattedDate, systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .lineLimit(1)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("BOOKING VALUE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                    Text(amountText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.045), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var clientInitials: String {
        let name = booking.clientName?.nilIfBlank ?? ""
        let initials = name
            .split(whereSeparator: { !$0.isLetter })
            .prefix(2)
            .compactMap(\.first)
        let result = String(initials).uppercased()
        return result.isEmpty ? "B" : result
    }

    private var projectText: String {
        booking.projectName?.nilIfBlank ?? booking.projectId?.nilIfBlank ?? "-"
    }

    private var referenceText: String {
        if let reference = booking.bookingRefNo?.nilIfBlank {
            return reference
        }
        if booking.projectName?.nilIfBlank == nil,
           booking.projectId?.nilIfBlank == nil,
           booking.plotNo?.nilIfBlank == nil {
            return booking.mobileNumber?.nilIfBlank ?? "Reference not available"
        }
        return "Reference not available"
    }

    private var plotText: String {
        booking.plotNo?.nilIfBlank ?? "-"
    }

    private var statusTint: Color {
        switch booking.displayStatus.lowercased().replacingOccurrences(of: "_", with: " ") {
        case "confirmed", "approved":
            return Color(hex: 0x169B2F)
        case "pending", "pending confirmation":
            return Color(hex: 0xD97706)
        case "cancelled", "canceled", "rejected":
            return Color(hex: 0xD92D20)
        case "draft":
            return Color(hex: 0x667085)
        default:
            return Color(hex: 0x0B61CA)
        }
    }

    private var amountText: String {
        if let cost = booking.bookingCost, cost > 0 {
            return AppModuleFormatters.rupees(cost)
        }
        return "-"
    }

    private var formattedDate: String {
        guard let raw = booking.bookingDate?.nilIfBlank else { return "-" }
        guard let date = AppModuleFormatters.ymd.date(from: raw) else { return raw }
        return AppModuleFormatters.day.string(from: date)
    }
}

private struct BookingStatusPill: View {
    let status: String

    private var normalized: String {
        status.lowercased().replacingOccurrences(of: "_", with: " ")
    }

    private var colors: (background: Color, foreground: Color) {
        switch normalized {
        case "draft":
            return (Color(hex: 0xF2F4F7), Color(hex: 0x475467))
        case "pending", "pending confirmation":
            return (Color(hex: 0xFEF0C7), Color(hex: 0xB54708))
        case "confirmed", "approved":
            return (Color(hex: 0xD1FADF), Color(hex: 0x169B2F))
        case "cancelled", "canceled", "rejected":
            return (Color(hex: 0xFEE4E2), Color(hex: 0xB42318))
        default:
            return (Color(hex: 0xF2F4F7), Color(hex: 0x475467))
        }
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(colors.background, in: Capsule())
            .lineLimit(1)
    }

    private var title: String {
        normalized
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private enum BookingStatusFilter: String, CaseIterable, Identifiable {
    case all
    case draft
    case pending
    case confirmed
    case cancelled

    var id: String { rawValue }
    var title: String { rawValue == "all" ? "All" : rawValue.capitalized }

    var apiValue: String? {
        switch self {
        case .all:
            return nil
        case .draft:
            return "draft"
        case .pending:
            return "pending_confirmation"
        case .confirmed:
            return "confirmed"
        case .cancelled:
            return "cancelled"
        }
    }

    func matches(_ status: String) -> Bool {
        let normalized = status.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch self {
        case .all:
            return true
        case .draft:
            return normalized == "draft"
        case .pending:
            return normalized == "pending" || normalized == "pending confirmation"
        case .confirmed:
            return normalized == "confirmed" || normalized == "approved"
        case .cancelled:
            return normalized == "cancelled" || normalized == "canceled" || normalized == "rejected"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
