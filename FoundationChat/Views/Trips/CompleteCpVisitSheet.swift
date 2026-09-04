import CoreLocation
import SwiftUI
import UIKit

// MARK: - CompleteCpVisitSheet

struct CompleteCpVisitSheet: View {
    let cpVisitId: String
    let initialOutcome: String?
    let cpType: String?
    let jointCtaMode: String?
    let jointOutcomeSummary: String?
    let onTerminalClosed: () -> Void
    let onCompleted: (CpRevisitInfo?) -> Void

    init(
        cpVisitId: String,
        initialOutcome: String?,
        cpType: String?,
        jointCtaMode: String? = nil,
        jointOutcomeSummary: String? = nil,
        onTerminalClosed: @escaping () -> Void = {},
        onCompleted: @escaping (CpRevisitInfo?) -> Void
    ) {
        self.cpVisitId = cpVisitId
        self.initialOutcome = initialOutcome
        self.cpType = cpType
        self.jointCtaMode = jointCtaMode
        self.jointOutcomeSummary = jointOutcomeSummary
        self.onTerminalClosed = onTerminalClosed
        self.onCompleted = onCompleted
    }

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedOutcome: CpVisitOutcome?
    @State private var budgetConcern = ""
    @State private var timingNotes = ""
    @State private var projectDetails = ""
    @State private var postponeFollowUpDate = Date()
    @State private var postponeReason = ""
    @State private var selectedNotInterestedReasons: Set<CpNotInterestedReason> = []
    @State private var notInterestedReasonDetails: [CpNotInterestedReason: String] = [:]
    @State private var otherRemarks = ""
    @State private var cancelReason = ""
    @State private var referralName = ""
    @State private var referralPhone = ""
    @State private var referralAddress = ""
    @State private var referralDecisionTaken = false
    @State private var showReferralQuestion = false
    @State private var showReferralForm = false
    @State private var notInterestedBudgetConcern = ""
    @State private var notInterestedTimingNotes = ""
    @State private var notInterestedProjectDetails = ""
    @State private var notInterestedOtherNotes = ""
    @State private var bookingSub: BookingSub = .client
    @State private var bookingStep: BookingStep = .findMobile
    @State private var bookingClientMobile = ""
    @State private var booking = BookingDraft()
    @State private var cpVisitDetail: CpVisitDetail?
    @State private var selectedBookingLead: TelecallerLeadSearchData?
    @State private var bookingLeadMatches: [TelecallerLeadSearchData] = []
    @State private var isSearchingBookingLead = false

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
    @State private var pickupLatitude: Double?
    @State private var pickupLongitude: Double?
    @State private var pickupGoogleMapsLink: String?
    @State private var visitorCount = ""
    @State private var visitors: [CpVisitorDraft] = []
    @State private var foodPreferences = ""

    @State private var isLoadingProjects = false
    @State private var isLoadingStaff = false
    @State private var isSaving = false
    @State private var hasFixedSiteVisit = false
    @State private var isLockedSvMode = false
    @State private var isDetectingLockedSvMode = false
    @State private var showRejectReasonSheet = false
    @State private var showCancelReasonSheet = false
    @State private var showPickupMapPin = false
    @State private var errorMessage: String?

    // Booking-form draft auto-save / resume (mirrors Android BookingDraftManager,
    // debounced against bookings/draft/{save,get,clear} keyed on "cp:<cpVisitId>").
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var hasRestoredDraft = false

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
            VStack(spacing: 0) {
                completionHeader

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if hasFixedSiteVisit && selectedOutcome == nil {
                            lockedSvDecisionChooser
                        } else if isLockedSvMode {
                            lockedSvConfirmationBanner
                        } else {
                            outcomeChips
                        }

                        if selectedOutcome != nil {
                            VStack(alignment: .leading, spacing: 14) {
                                completionFormContent
                            }
                            .padding(16)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }

                        if selectedOutcome == .other {
                            otherSection
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color(hex: 0xB42318))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: 0xB42318).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
                .background(Color(.systemGroupedBackground))

                fixedSubmitFooter
            }
            .background(Color(.systemGroupedBackground))
            .appCompactSheetCTAContainer()
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(isSaving)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                let startingOutcome = CpVisitOutcome(rawValue: normalizedServerValue(initialOutcome))
                // Nothing pre-selected unless the caller (or locked-SV mode) supplies one.
                selectedOutcome = startingOutcome
                if startingOutcome == .siteVisit || initialOutcomeMarksFixedSiteVisit || isSvCumCp {
                    hasFixedSiteVisit = true
                    selectedOutcome = nil
                }
                // Restore any in-progress booking BEFORE prefill runs, so the
                // operator's last manual edits win over the CP-visit prefill
                // (which only fills blank fields). Mirrors Android's ordering.
                await restoreBookingDraftIfNeeded()
                await loadInitialData()
                await detectAndApplyLockedSvMode()
            }
            .onChange(of: booking) { _, _ in scheduleBookingDraftAutosave() }
            .sheet(isPresented: $showRejectReasonSheet) {
                CpActionReasonSheet(
                    title: "Reject SV",
                    subtitle: "Add the reason for rejecting this fixed site visit.",
                    fieldLabel: "Rejection reason",
                    placeholder: "Why is this site visit being rejected?",
                    submitTitle: "Reject SV",
                    isSaving: isSaving,
                    onSubmit: { reason in
                        await submitLockedRejection(reason: reason)
                    }
                )
                .appLibraryNativeSheet([.medium, .large])
            }
            .sheet(isPresented: $showCancelReasonSheet) {
                CpActionReasonSheet(
                    title: "Cancel SV",
                    subtitle: "Cancellation closes the linked CP, site visit, field visit, and task.",
                    fieldLabel: "Cancellation remarks",
                    placeholder: "Why is this site visit being cancelled?",
                    submitTitle: "Cancel SV",
                    isSaving: isSaving,
                    onSubmit: { reason in
                        await submitLockedCancellation(reason: reason)
                    }
                )
                .appLibraryNativeSheet([.medium, .large])
            }
            .sheet(isPresented: $showPickupMapPin) {
                CpMapPinPicker(
                    initialCoordinate: pickupCoordinate,
                    initialAddress: pickupAddress.nilIfBlank
                ) { result in
                    pickupLatitude = result.latitude
                    pickupLongitude = result.longitude
                    pickupGoogleMapsLink = result.googleMapsLink
                    if let address = result.address.nilIfBlank {
                        pickupAddress = address
                    }
                    showPickupMapPin = false
                }
                .appLibraryNativeSheet([.large])
            }
            .alert("Any referrals?", isPresented: $showReferralQuestion) {
                Button("Yes") {
                    DispatchQueue.main.async {
                        showReferralForm = true
                    }
                }
                Button("No") {
                    referralDecisionTaken = true
                    Task { await submit() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Did this client refer another person?")
            }
            .sheet(isPresented: $showReferralForm) {
                NewClientReferralSheet { name, phone, address in
                    referralName = name
                    referralPhone = phone
                    referralAddress = address
                    referralDecisionTaken = true
                    showReferralForm = false
                    Task { await submit() }
                }
                .appLibraryNativeSheet([.medium, .large])
            }
        }
        .appFormActivity()
    }

    private var completionHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .disabled(isSaving)
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 2) {
                Text(isLockedSvMode ? "Confirm Site Visit" : "Complete CP Visit")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: dismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.body.weight(.medium))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: 0x0B61CA))
            .accessibilityLabel("Dismiss keyboard")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var completionFormContent: some View {
        switch selectedOutcome {
        case .booking: bookingSection
        case .siteVisit: siteVisitSection
        case .postponed: postponeSection
        case .notInterested: notInterestedSection
        case .other: EmptyView()
        case .referral: referralSection
        case .cancel: cancelSection
        case nil:
            ContentUnavailableView("Choose an outcome", systemImage: "checklist")
        }
    }

    private var lockedSvConfirmationBanner: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 46, height: 46)
                .background(Color(hex: 0x0B61CA).opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Site visit proposed")
                    .font(.headline)
                Text("Verify the schedule, assigned staff and visitor information. You can correct any detail before confirming.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x0B61CA).opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0xB9D8FF), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var fixedSubmitFooter: some View {
        VStack(spacing: 10) {
            if isLockedSvMode && selectedOutcome == .siteVisit {
                lockedSvFooter
            } else if selectedOutcome != nil {
                Button {
                    Task { await submit() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    } else {
                        Text(ctaTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(hex: 0x2DAE12))
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    /// SV-cum-CP completions use the SV-style outcome set (which retains "Others").
    /// Mirrors Android `svStyle = isSiteVisitMode || cpType == "sv_cum_cp"`.
    private var svStyle: Bool {
        isLockedSvMode || effectiveCpType.normalizedCpMarker == "sv_cum_cp"
    }

    private var effectiveCpType: String? {
        cpType ?? cpVisitDetail?.cpType
    }

    /// Physical "new client" CP. Referral is asked separately after the real
    /// outcome form is valid; it never replaces the operational outcome.
    private var isNewClientCp: Bool {
        effectiveCpType.normalizedCpMarker == "new_client_cp"
    }

    /// SV-cum-CP completions add a "Cancel" outcome (cancels the CP via a
    /// separate endpoint). Mirrors Android's sv_cum_cp cancel affordance.
    private var isSvCumCp: Bool {
        effectiveCpType.normalizedCpMarker == "sv_cum_cp"
    }

    /// Booking CP postpone offers a "site visit instead" shortcut into the
    /// convert-to-SV flow. Mirrors Android's booking_cp postpone affordance.
    private var isBookingCp: Bool {
        effectiveCpType.normalizedCpMarker == "booking_cp"
    }

    /// Selectable range for the postpone / next-visit date. VP follow-up window
    /// caps: a collection follow-up lands within 5 days, a booking-CP postpone
    /// within 7. Other cpTypes are effectively uncapped. Mirrors the setOutcome
    /// server-side check so the picker can't offer an invalid date.
    private var postponeDateRange: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let capDays: Int?
        switch effectiveCpType.normalizedCpMarker {
        case "collection_cp": capDays = 5
        case "booking_cp": capDays = 7
        default: capDays = nil
        }
        let end = cal.date(byAdding: .day, value: capDays ?? 365 * 5, to: start) ?? start
        return start...end
    }

    /// The outcome tabs to render. "Others" is gated to SV-style rows and the
    /// approved CP types (mirror Android CompleteCpVisitBottomSheet.kt:961-963).
    /// Historical `.referral` remains decodable but is no longer selectable.
    private var visibleOutcomes: [CpVisitOutcome] {
        if isNewClientCp {
            return [.booking, .siteVisit, .postponed, .notInterested]
        }
        var list = CpVisitOutcome.allCases.filter { $0 != .other && $0 != .referral && $0 != .cancel }
        if isSvCumCp {
            list.append(.cancel)
        }
        if svStyle || cpTypeSupportsOtherOutcome(effectiveCpType) {
            list.append(.other)
        }
        return list
    }

    /// Per-context outcome relabels. new_client_cp reuses existing outcomes under
    /// field-friendly names; every other CP type keeps the canonical title.
    private func displayTitle(for outcome: CpVisitOutcome) -> String {
        guard isNewClientCp else { return outcome.title }
        switch outcome {
        case .booking: return "Booking"
        case .siteVisit: return "Site Visit"
        case .postponed: return "Follow-up"
        default: return outcome.title
        }
    }

    private var outcomeChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What happened with the client?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(Array(visibleOutcomes.enumerated()), id: \.element.id) { index, outcome in
                    Button {
                        guard !isLockedSvMode || outcome == .siteVisit else { return }
                        selectedOutcome = outcome
                        errorMessage = nil
                        if outcome == .booking {
                            bookingSub = .client
                            bookingStep = .findMobile
                        }
                    } label: {
                        OutcomeTabView(
                            outcome: outcome,
                            isSelected: selectedOutcome == outcome,
                            titleOverride: displayTitle(for: outcome)
                        )
                        .frame(maxWidth: .infinity)
                        .opacity(isLockedSvMode && outcome != .siteVisit ? 0.35 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLockedSvMode && outcome != .siteVisit)
                    .accessibilityLabel(displayTitle(for: outcome))
                    .accessibilityAddTraits(selectedOutcome == outcome ? .isSelected : [])

                    if index < visibleOutcomes.count - 1 {
                        Rectangle()
                            .fill(Color(hex: 0xE4E7EC))
                            .frame(width: 1, height: 32)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var headerSubtitle: String {
        if jointCtaMode == "complete_review", let summary = jointOutcomeSummary?.nilIfBlank {
            return "BDO submitted: \(summary)"
        }
        return isLockedSvMode
            ? "Review the visit details before confirming"
            : "Select the client outcome and enter the details"
    }

    private var lockedSvDecisionChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happened with the client?")
                .font(.headline)
            Text("Choose an action to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            lockedDecisionButton("Converted as Booking", icon: "checkmark.seal", tint: Color(hex: 0x0B61CA)) {
                selectedOutcome = .booking
                isLockedSvMode = false
                bookingSub = .client
                bookingStep = .findMobile
                errorMessage = nil
            }
            lockedDecisionButton("Site Visit", icon: "mappin.and.ellipse", tint: Color(hex: 0x0B61CA)) {
                selectedOutcome = .siteVisit
                isLockedSvMode = true
                errorMessage = nil
            }
            lockedDecisionButton("Follow-up", icon: "calendar.badge.clock", tint: Color(hex: 0x0B61CA)) {
                selectedOutcome = .postponed
                isLockedSvMode = false
                errorMessage = nil
            }
            lockedDecisionButton("Client Not Interested", icon: "nosign", tint: Color(hex: 0x0B61CA)) {
                selectedOutcome = .notInterested
                isLockedSvMode = false
                errorMessage = nil
            }
            lockedDecisionButton("Reject SV", icon: "xmark.circle", tint: Color(hex: 0xB42318)) {
                errorMessage = nil
                showRejectReasonSheet = true
            }
            lockedDecisionButton("Cancel SV", icon: "xmark.bin", tint: Color(hex: 0xB42318)) {
                errorMessage = nil
                showCancelReasonSheet = true
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func lockedDecisionButton(
        _ title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
        .disabled(isSaving)
    }

    private var lockedSvFooter: some View {
        Button {
            Task { await submit() }
        } label: {
            if isSaving {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Label("Confirm Site Visit", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Color(hex: 0x2DAE12))
        .disabled(isSaving)
    }

    private func resetOutcomeToBookingFindClient() {
        dismissKeyboard()
        selectedOutcome = .booking
        bookingSub = .client
        bookingStep = .findMobile
        errorMessage = nil
    }

    private var siteVisitSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            completionSectionCard(title: "Visit schedule", subtitle: "Project, date and pickup", icon: "calendar.badge.clock") {
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
                            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 14))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("Time")
                        DatePicker("", selection: $siteVisitTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 48)
                            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                HStack(spacing: 10) {
                    SegmentButton(title: "Own Vehicle", isSelected: travelMode == .ownVehicle) {
                        travelMode = .ownVehicle
                    }
                    SegmentButton(title: "Cab Vehicle", isSelected: travelMode == .cab) {
                        travelMode = .cab
                    }
                }
                fieldEditor("Enter pickup address", text: $pickupAddress, minLines: 2, label: "Pickup address (if needed)")
                Button {
                    showPickupMapPin = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: pickupCoordinate == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .frame(width: 42, height: 42)
                            .background(Color(hex: 0x0B61CA).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pickupCoordinate == nil ? "Pin pickup location" : "Change pinned location")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(pickupCoordinate.map(coordinateDescription) ?? "Save exact coordinates and a Google Maps link")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            completionSectionCard(title: "Sales ownership", subtitle: "Confirm the responsible team", icon: "person.3.fill") {
                Label("Original BDO hierarchy will be retained", systemImage: "arrow.triangle.branch")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x2563EB).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

                if isLoadingStaff {
                    FieldShell {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading staff…").font(.system(size: 13, weight: .medium))
                        }
                    }
                } else {
                    staffPicker("Select Site Incharge", selection: $selectedIncharge)
                    staffPicker("Select HOD", selection: $selectedHod)
                    staffPicker("Select AVP", selection: $selectedAvp)
                    staffPicker("Select GM", selection: $selectedGm)
                    staffPicker("Select Senior Manager", selection: $selectedSeniorManager)
                }
            }

            completionSectionCard(title: "Visitors", subtitle: "People attending the site visit", icon: "person.2.fill") {
                TextField("Number of visitors", text: $visitorCount)
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
        }
    }

    private func completionSectionCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0x0B61CA).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.45), lineWidth: 1)
        }
    }

    private var bookingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if bookingStep == .clientForm {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(BookingSub.allCases) { sub in
                            Button {
                                bookingSub = sub
                                errorMessage = nil
                            } label: {
                                BookingSubTab(title: sub.title, isSelected: bookingSub == sub)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
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
                    .foregroundStyle(.primary)
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
                .onChange(of: bookingClientMobile) { _, _ in
                    selectedBookingLead = nil
                    bookingLeadMatches = []
                }

            Button {
                Task { await searchBookingLead() }
            } label: {
                HStack {
                    if isSearchingBookingLead {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text("Find Client")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(hex: 0x0B61CA))
            .disabled(isSearchingBookingLead || AppModuleFormatters.normalizePhone(bookingClientMobile).count != 10)

            if let selectedBookingLead {
                FieldShell {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Linked client")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(selectedBookingLead.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }

            ForEach(bookingLeadMatches) { lead in
                Button {
                    applyBookingLead(lead)
                } label: {
                    FieldShell {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lead.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(lead.mobileNumber ?? "No mobile")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2DAE12))
                Text("We will fetch and auto-fill client details from the project.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x2DAE12))
            }
            .padding(12)
            .background(Color(hex: 0x027A48).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
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
            BookingTextField("Patta Charges", text: $booking.pattaCharges, placeholder: "Enter Cost", icon: "briefcase", keyboard: .decimalPad)
            BookingTextField("Other Charges", text: $booking.otherCharges, keyboard: .decimalPad)
            Toggle("Other Charges If Applicable", isOn: $booking.otherChargesApplicable)
                .font(.system(size: 13, weight: .medium))
            BookingTextField("Advance Amount", text: $booking.advanceAmount, keyboard: .decimalPad)
            BookingPickerTextField("Payment Mode", text: $booking.paymentMode, placeholder: "Select Mode", icon: "info.circle", options: paymentModeOptions)
            Toggle("Flexi Payment", isOn: $booking.flexiPayment)
                .font(.system(size: 13, weight: .medium))
            BookingTextField("Allotment Due Amount", text: $booking.allotmentDueAmount, keyboard: .decimalPad)
            BookingDateTextField("Allotment Due Date", text: $booking.allotmentDueDate)
            BookingTextField("2nd Payment Amount", text: $booking.secondPaymentAmount, placeholder: "Enter Cost", icon: "briefcase", keyboard: .decimalPad)
            BookingDateTextField("2nd Payment Date", text: $booking.secondPaymentDate)
            BookingTextField("3rd Payment Amount", text: $booking.thirdPaymentAmount, placeholder: "Enter Cost", icon: "briefcase", keyboard: .decimalPad)
            BookingDateTextField("3rd Payment Date", text: $booking.thirdPaymentDate)
            BookingTextField("4th Payment Amount", text: $booking.fourthPaymentAmount, placeholder: "Enter Cost", icon: "briefcase", keyboard: .decimalPad)
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
            sectionLabel("Follow-up date")
            Text("When should the client be followed up?")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                DatePicker(
                    "Follow-up date",
                    selection: $postponeFollowUpDate,
                    in: postponeDateRange,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Follow-up date")

            sectionLabel("Reason")
                .padding(.top, 6)
            Text("Why does this client need a follow-up?")
                .font(.caption)
                .foregroundStyle(.secondary)
            fieldEditor("Reason for follow-up", text: $postponeReason, minLines: 2)

            if isBookingCp {
                Button {
                    selectedOutcome = .siteVisit
                } label: {
                    Label("Offer a site visit instead", systemImage: "building.2")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color(hex: 0x0B61CA))
                .padding(.top, 4)
            }
        }
        .padding(.top, 4)
    }

    private var notInterestedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Reason")
            ForEach(CpNotInterestedReason.allCases) { reason in
                VStack(alignment: .leading, spacing: 8) {
                    ReasonToggleRow(
                        title: reason.title,
                        isSelected: selectedNotInterestedReasons.contains(reason)
                    ) {
                        toggleNotInterestedReason(reason)
                    }
                    if selectedNotInterestedReasons.contains(reason) {
                        fieldEditor(
                            "Add \(reason.title.lowercased()) detail",
                            text: bindingForNotInterestedReason(reason),
                            minLines: 2
                        )
                        .padding(.leading, 10)
                    }
                }
            }
            fieldEditor("Add notes", text: $notInterestedOtherNotes, minLines: 3)
        }
        .padding(.top, 4)
    }

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Remarks")
            fieldEditor("Explain why this visit is being closed", text: $otherRemarks, minLines: 3)
        }
        .padding(.top, 4)
    }

    private var cancelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This cancels the CP visit. Cancellation remarks are required.")
                .font(.caption)
                .foregroundStyle(.secondary)
            sectionLabel("Reason")
            fieldEditor("Reason for cancelling", text: $cancelReason, minLines: 3)
        }
        .padding(.top, 4)
    }

    private var referralSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capture the person this client referred. Their name and phone are recorded on this visit.")
                .font(.caption)
                .foregroundStyle(.secondary)
            sectionLabel("Referral name")
            TextField("Enter referral name", text: $referralName)
                .cpFieldStyle(icon: "person")
            sectionLabel("Referral phone")
            TextField("Enter referral phone", text: $referralPhone)
                .keyboardType(.phonePad)
                .cpFieldStyle(icon: "phone")
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
            if bookingSub == .staff, let jointFinalTitle { return jointFinalTitle }
            return bookingSub == .staff ? "Create \(booking.saveAs.title) Booking" : "Next"
        case .siteVisit, .postponed, .notInterested, .other, .referral:
            return jointFinalTitle ?? "Save"
        case .cancel:
            return "Cancel Visit"
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
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func labeledEditor(_ title: String, text: Binding<String>, minLines: Int = 2) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
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
                .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func fieldText(_ text: String) -> some View {
        FieldShell {
            HStack {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleNotInterestedReason(_ reason: CpNotInterestedReason) {
        if selectedNotInterestedReasons.contains(reason) {
            selectedNotInterestedReasons.remove(reason)
            notInterestedReasonDetails[reason] = nil
        } else {
            selectedNotInterestedReasons.insert(reason)
        }
    }

    private func bindingForNotInterestedReason(_ reason: CpNotInterestedReason) -> Binding<String> {
        Binding(
            get: { notInterestedReasonDetails[reason] ?? "" },
            set: { notInterestedReasonDetails[reason] = $0 }
        )
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
        // Android loads the complete active staff directory here. Restricting
        // this to Sales hid the CP-assigned field staff and made the Site
        // Incharge default silently fail.
        salesStaff = staff.filter { ($0.status ?? "active").lowercased() == "active" }
    }

    @MainActor
    private func detectAndApplyLockedSvMode() async {
        guard !isDetectingLockedSvMode else { return }
        guard let token = authStore.currentSession?.token else { return }
        isDetectingLockedSvMode = true
        defer { isDetectingLockedSvMode = false }

        do {
            let visit = try await loadCpVisitDetailForLockedDetection(token: token)
            cpVisitDetail = visit
            prefillBookingFromCpVisit(visit)

            let proposed = visit.proposedSiteVisit
            guard isLockedSvMode || visit.hasFixedSiteVisitSignal(initialOutcome: initialOutcome) else { return }
            applyLockedSvMode(visit: visit, proposed: proposed)
        } catch {
            // Locked mode is progressive enhancement. If detection fails, keep the normal CP flow usable.
        }
    }

    private func loadCpVisitDetailForLockedDetection(token: String) async throws -> CpVisitDetail {
        do {
            return try await MarketingConvexAPIService.getCpVisitDetail(token: token, id: cpVisitId)
        } catch {
            let visits = try await MarketingConvexAPIService.getMyMarketingCpVisits(token: token)
            guard let visit = visits.first(where: { $0.id == cpVisitId }) else { throw error }
            return visit
        }
    }

    @MainActor
    private func prefillBookingFromCpVisit(_ visit: CpVisitDetail) {
        if bookingClientMobile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bookingClientMobile = visit.lead?.mobileNumber?.nilIfBlank
                ?? visit.client?.mobileNumber?.nilIfBlank
                ?? visit.clientPlace?.contactPhone?.nilIfBlank
                ?? ""
        }
        if booking.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            booking.phone = AppModuleFormatters.normalizePhone(bookingClientMobile)
        }
        if booking.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            booking.name = visit.lead?.contactName?.nilIfBlank
                ?? visit.client?.clientName?.nilIfBlank
                ?? visit.clientPlace?.contactPerson?.nilIfBlank
                ?? ""
        }
        if booking.homeAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            booking.homeAddress = visit.clientPlace?.address?.nilIfBlank
                ?? visit.clientPlace?.formattedAddress?.nilIfBlank
                ?? visit.lead?.preferredArea?.nilIfBlank
                ?? ""
        }
    }

    @MainActor
    private func searchBookingLead() async {
        let mobile = AppModuleFormatters.normalizePhone(bookingClientMobile)
        guard mobile.count == 10 else {
            errorMessage = "Enter a valid mobile number"
            return
        }
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in"
            return
        }

        isSearchingBookingLead = true
        defer { isSearchingBookingLead = false }

        do {
            bookingLeadMatches = try await MarketingConvexAPIService.searchTelecallerLeadsByPhone(token: token, phone: mobile)
            if bookingLeadMatches.count == 1, let lead = bookingLeadMatches.first {
                applyBookingLead(lead)
            } else if bookingLeadMatches.isEmpty {
                booking.phone = mobile
                bookingStep = .clientForm
            }
        } catch {
            errorMessage = userFacingCompletionError(error)
        }
    }

    @MainActor
    private func applyBookingLead(_ lead: TelecallerLeadSearchData) {
        selectedBookingLead = lead
        bookingLeadMatches = []
        booking.phone = AppModuleFormatters.normalizePhone(lead.mobileNumber ?? bookingClientMobile)
        bookingClientMobile = booking.phone
        booking.name = lead.displayName
        booking.homeAddress = lead.suggestedVisitAddress?.nilIfBlank
            ?? lead.latestAnalysisProfile?.address?.nilIfBlank
            ?? booking.homeAddress
        booking.pincode = lead.latestAnalysisProfile?.pincode?.nilIfBlank ?? booking.pincode
        booking.state = lead.latestAnalysisProfile?.state?.nilIfBlank ?? booking.state
        booking.district = lead.latestAnalysisProfile?.district?.nilIfBlank ?? booking.district
        booking.location = lead.locationPreferred?.nilIfBlank ?? booking.location
        bookingStep = .clientForm
    }

    @MainActor
    private func applyLockedSvMode(visit: CpVisitDetail, proposed: ProposedSiteVisit?) {
        hasFixedSiteVisit = true
        errorMessage = nil

        if let projectId = proposed?.projectId?.nilIfBlank {
            selectedProject = projects.first { $0.id == projectId }
        }
        if let date = parseServerDate(proposed?.scheduledDate ?? visit.scheduledDate) {
            siteVisitDate = date
        }
        if let time = parseServerTime(proposed?.scheduledTime ?? visit.scheduledTime) {
            siteVisitTime = time
        }

        selectedIncharge = staff(with: proposed?.inchargeStaffId)
            ?? staff(with: visit.assignedStaffId)
        selectedHod = staff(with: proposed?.hodStaffId)
        selectedAvp = staff(with: proposed?.avpStaffId)
        selectedGm = staff(with: proposed?.gmStaffId)
        selectedSeniorManager = staff(with: proposed?.seniorManagerStaffId)

        let count = max(visit.expectedAttendeeCount ?? visit.attendees?.count ?? 0, 1)
        visitorCount = "\(count)"
        syncVisitorRows(count: count)
        if let attendees = visit.attendees, !attendees.isEmpty {
            for (index, attendee) in attendees.prefix(visitors.count).enumerated() {
                visitors[index].name = attendee.name ?? ""
                visitors[index].relation = attendee.relation ?? ""
                visitors[index].age = attendee.age ?? ""
                visitors[index].isVeg = attendee.isVeg ?? true
            }
        } else if let first = visitors.indices.first {
            let fallbackName = visit.lead?.contactName?.nilIfBlank
                ?? visit.lead?.manualProfile?.clientName?.nilIfBlank
                ?? visit.client?.clientName?.nilIfBlank
                ?? visit.clientPlace?.contactPerson?.nilIfBlank
                ?? visit.clientPlace?.name?.nilIfBlank
                ?? ""
            if visitors[first].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                visitors[first].name = fallbackName
            }
            if visitors[first].relation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                visitors[first].relation = "Self"
            }
        }
        foodPreferences = visit.foodPreferences ?? ""
        pickupAddress = visit.clientPlace?.address?.nilIfBlank
            ?? visit.clientPlace?.formattedAddress?.nilIfBlank
            ?? visit.lead?.preferredArea?.nilIfBlank
            ?? pickupAddress
        pickupLatitude = visit.clientPlace?.lat
        pickupLongitude = visit.clientPlace?.lng
        pickupGoogleMapsLink = visit.clientPlace?.googleMapsLink?.nilIfBlank
        if let vehicle = visit.vehiclePreference?.nilIfBlank {
            travelMode = vehicle.lowercased().contains("own") ? .ownVehicle : .cab
        }
    }

    private func staff(with id: String?) -> ConvexStaffListItem? {
        guard let id = id?.nilIfBlank else { return nil }
        return salesStaff.first { $0.id == id }
    }

    private func syncVisitorRows(count rawCount: Int) {
        let count = min(max(rawCount, 0), 12)
        if visitors.count < count {
            visitors.append(contentsOf: (visitors.count..<count).map { _ in CpVisitorDraft() })
        } else if visitors.count > count {
            visitors.removeLast(visitors.count - count)
        }
    }

    // MARK: - Booking draft (auto-save / resume / clear)

    private var draftSourceKey: String { "cp:\(cpVisitId)" }

    private var draftStorageKey: String {
        let subject = authStore.currentSession?.user._id ?? "anonymous"
        return "booking.draft.cp.\(cpVisitId).\(subject)"
    }

    private var draftUpdatedAtKey: String { "\(draftStorageKey).updatedAt" }

    @MainActor
    private func restoreBookingDraftIfNeeded() async {
        guard !hasRestoredDraft else { return }
        defer { hasRestoredDraft = true }

        let decoder = JSONDecoder()

        // Local snapshot — survives crash + immediate relaunch, always wins on
        // the current device's timeline.
        let localData = UserDefaults.standard.data(forKey: draftStorageKey)
        let localUpdatedAt = UserDefaults.standard.double(forKey: draftUpdatedAtKey)
        let localDraft = localData.flatMap { try? decoder.decode(BookingDraft.self, from: $0) }

        // Cloud snapshot — survives signing in from another phone. Best-effort.
        var cloudDraft: BookingDraft?
        var cloudUpdatedAt: Double = 0
        if let token = authStore.currentSession?.token,
           let payload = try? await MarketingConvexAPIService.getBookingDraft(token: token, sourceKey: draftSourceKey),
           let json = payload.draftJson?.data(using: .utf8),
           let decoded = try? decoder.decode(BookingDraft.self, from: json) {
            cloudDraft = decoded
            cloudUpdatedAt = payload.updatedAt ?? 0
        }

        // Prefer whichever copy is newer; cloud wins ties so a fresh cross-device
        // draft isn't shadowed by a stale local one (mirror BookingDraftManager.restore).
        let restored: BookingDraft?
        if let cloudDraft, cloudUpdatedAt >= localUpdatedAt {
            restored = cloudDraft
        } else {
            restored = localDraft ?? cloudDraft
        }

        guard let restored, !restored.isEmpty else { return }
        booking = restored
        if !booking.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bookingClientMobile = booking.phone
        }
    }

    private func scheduleBookingDraftAutosave() {
        guard hasRestoredDraft, !booking.isEmpty else { return }
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await saveBookingDraftNow()
        }
    }

    @MainActor
    private func saveBookingDraftNow() async {
        guard let data = try? JSONEncoder().encode(booking) else { return }
        UserDefaults.standard.set(data, forKey: draftStorageKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000, forKey: draftUpdatedAtKey)
        guard let token = authStore.currentSession?.token else { return }
        let payload = BookingDraftSaveRequest(
            sourceKey: draftSourceKey,
            sourceCpVisitId: cpVisitId,
            sourceSiteVisitId: nil,
            draftJson: String(data: data, encoding: .utf8) ?? "{}"
        )
        try? await MarketingConvexAPIService.saveBookingDraft(token: token, payload: payload)
    }

    @MainActor
    private func clearBookingDraft() {
        draftSaveTask?.cancel()
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
        UserDefaults.standard.removeObject(forKey: draftUpdatedAtKey)
        guard let token = authStore.currentSession?.token else { return }
        Task { try? await MarketingConvexAPIService.clearBookingDraft(token: token, sourceKey: draftSourceKey) }
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
                let mobile = AppModuleFormatters.normalizePhone(bookingClientMobile)
                guard mobile.count == 10 else {
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
        if selectedOutcome == .postponed && postponeReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Enter a reason for follow-up"
            return
        }
        if selectedOutcome == .notInterested && selectedNotInterestedReasons.isEmpty {
            errorMessage = "Please share at least one reason"
            return
        }
        if selectedOutcome == .other && otherRemarks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please add remarks to explain this outcome"
            return
        }
        if selectedOutcome == .cancel && cancelReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Cancellation remarks are required"
            return
        }
        let confirmsExistingLockedSiteVisit = isLockedSvMode && cpVisitDetail?.convertedSiteVisitId?.nilIfBlank != nil
        if selectedOutcome == .siteVisit && selectedProject == nil && !confirmsExistingLockedSiteVisit {
            errorMessage = "Please select a project"
            return
        }
        let requiresSiteVisitConversion = selectedOutcome == .siteVisit && !confirmsExistingLockedSiteVisit
        let sessionStaffId = authStore.currentSession?.user.staffId?.nilIfBlank
            ?? authStore.currentSession?.user._id.nilIfBlank
        let inchargeStaffId = selectedIncharge?.id.nilIfBlank
            ?? cpVisitDetail?.assignedStaffId?.nilIfBlank
        if requiresSiteVisitConversion && inchargeStaffId == nil {
            errorMessage = "Site incharge is required"
            return
        }
        if requiresSiteVisitConversion && sessionStaffId == nil {
            errorMessage = "Assign a BDO before fixing this Site Visit"
            return
        }
        if requiresSiteVisitConversion {
            let hasNamedVisitor = visitors.contains {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !hasNamedVisitor {
                errorMessage = "Add at least one visitor (name) before fixing this Site Visit"
                return
            }
            // The SV inherits the CP's client identity — block it when there's no
            // client name (renders as "—"). The backend enforces this too.
            let svClientName = cpVisitDetail?.lead?.contactName?.nilIfBlank
                ?? cpVisitDetail?.lead?.manualProfile?.clientName?.nilIfBlank
                ?? cpVisitDetail?.client?.clientName?.nilIfBlank
                ?? cpVisitDetail?.clientPlace?.contactPerson?.nilIfBlank
                ?? cpVisitDetail?.clientPlace?.name?.nilIfBlank
            if svClientName == nil {
                errorMessage = "This client has no name. Add the client's name before fixing a Site Visit."
                return
            }
        }

        if isNewClientCp && !referralDecisionTaken {
            showReferralQuestion = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if selectedOutcome == .cancel {
                try await MarketingConvexAPIService.cancelCpVisit(
                    token: token,
                    id: cpVisitId,
                    reason: cancelReason.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                onTerminalClosed()
                dismiss()
                return
            }

            if isNewClientCp, !referralName.isEmpty {
                try await MarketingConvexAPIService.recordCpReferral(
                    token: token,
                    request: RecordCpReferralRequest(
                        id: cpVisitId,
                        clientName: referralName,
                        mobileNumber: referralPhone,
                        address: referralAddress
                    )
                )
            }

            try await MarketingConvexAPIService.markClientMet(
                token: token,
                request: MarkClientMetRequest(id: cpVisitId, clientMet: true)
            )

            var revisit: CpRevisitInfo?
            if selectedOutcome == .booking {
                _ = try await MarketingConvexAPIService.createBooking(
                    token: token,
                    request: booking.createRequest(
                        cpVisitId: cpVisitId,
                        leadId: selectedBookingLead?.id ?? cpVisitDetail?.leadId,
                        projects: projects,
                        staff: salesStaff
                    )
                )
                // The booking create route receives the CP source IDs and marks
                // the CP converted atomically. A second setOutcome call can fail
                // after the booking already succeeded because the CP is terminal.
                // Booking landed — wipe the local + cloud draft so the next
                // form open for a different source starts clean.
                clearBookingDraft()
            } else if selectedOutcome == .siteVisit {
                if isLockedSvMode, cpVisitDetail?.convertedSiteVisitId?.nilIfBlank != nil {
                    _ = try await MarketingConvexAPIService.setCpVisitOutcome(
                        token: token,
                        request: SetCpVisitOutcomeRequest(
                            id: cpVisitId,
                            outcome: "interested",
                            postponeReasons: nil,
                            notes: "Confirmed by field staff"
                        )
                    )
                } else {
                    guard let selectedProject else { return }
                    _ = try await MarketingConvexAPIService.convertCpVisitToSiteVisit(
                        token: token,
                        request: ConvertCpVisitToSiteVisitRequest(
                            id: cpVisitId,
                            projectId: selectedProject.id,
                            scheduledDate: dateString(siteVisitDate),
                            scheduledTime: timeString(siteVisitTime),
                            telecallerId: sessionStaffId,
                            convertedByStaffId: sessionStaffId,
                            inchargeStaffId: inchargeStaffId,
                            hodStaffId: selectedHod?.id,
                            avpStaffId: selectedAvp?.id,
                            gmStaffId: selectedGm?.id,
                            seniorManagerStaffId: selectedSeniorManager?.id,
                            expectedAttendeeCount: Int(visitorCount.trimmingCharacters(in: .whitespacesAndNewlines)),
                            attendees: visitorPayload.nilIfEmpty,
                            pickupAddress: pickupAddress.nilIfBlank,
                            pickupLat: pickupLatitude,
                            pickupLng: pickupLongitude,
                            pickupGoogleMapsLink: pickupGoogleMapsLink?.nilIfBlank,
                            travelMode: travelMode.rawValue,
                            foodPreferences: foodPreferences.nilIfBlank,
                            notes: "Created from iOS CP visit"
                        )
                    )
                }
            } else {
                // Android sends only the selected follow-up date. Keep iOS on
                // the same contract instead of deriving a time from Date().
                let isPostpone = selectedOutcome == .postponed
                revisit = try await MarketingConvexAPIService.setCpVisitOutcome(
                    token: token,
                    request: SetCpVisitOutcomeRequest(
                        id: cpVisitId,
                        outcome: selectedOutcome.rawValue,
                        postponeReasons: isPostpone ? [postponeReason.trimmingCharacters(in: .whitespacesAndNewlines)] : nil,
                        notes: buildOutcomeNotes(for: selectedOutcome),
                        arrivalPhotoStorageId: nil,
                        followUpDate: isPostpone
                            ? AppModuleFormatters.ymd.string(from: postponeFollowUpDate)
                            : nil,
                        followUpTime: nil
                    )
                )
            }

            onCompleted(revisit)
            dismiss()
        } catch {
            errorMessage = userFacingCompletionError(error)
        }
    }

    private var pickupCoordinate: CLLocationCoordinate2D? {
        guard let pickupLatitude, let pickupLongitude,
              (-90...90).contains(pickupLatitude),
              (-180...180).contains(pickupLongitude)
        else { return nil }
        return CLLocationCoordinate2D(latitude: pickupLatitude, longitude: pickupLongitude)
    }

    private func coordinateDescription(_ coordinate: CLLocationCoordinate2D) -> String {
        "\(coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(5))))"
    }

    private func submitLockedRejection(reason: String) async {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please share a reason for the rejection"
            return
        }
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in"
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await MarketingConvexAPIService.rejectCpVisitOutcome(
                token: token,
                request: SetCpVisitOutcomeRequest(
                    id: cpVisitId,
                    outcome: "rejected",
                    postponeReasons: nil,
                    notes: trimmed
                )
            )
            showRejectReasonSheet = false
            onTerminalClosed()
            dismiss()
        } catch {
            errorMessage = userFacingCompletionError(error)
        }
    }

    private func submitLockedCancellation(reason: String) async {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Cancellation remarks are required"
            return
        }
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in"
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await MarketingConvexAPIService.cancelCpVisit(
                token: token,
                id: cpVisitId,
                reason: trimmed
            )
            showCancelReasonSheet = false
            onTerminalClosed()
            dismiss()
        } catch {
            errorMessage = userFacingCompletionError(error)
        }
    }

    private var jointFinalTitle: String? {
        switch jointCtaMode {
        case "send_review": return "Send Review"
        case "complete_review": return "Complete"
        default: return nil
        }
    }

    private func userFacingCompletionError(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("selfie with the client") {
            return "The arrival selfie was not linked to this visit. Please return to the trip and capture it again."
        }
        let firstLine = raw.components(separatedBy: "\n").first ?? raw
        return firstLine
            .replacingOccurrences(of: "Uncaught Error:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        case .other:
            return otherRemarks.nilIfBlank
        case .referral:
            let trimmedName = referralName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPhone = referralPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Referral: \(trimmedName) · \(trimmedPhone)"
        case .siteVisit:
            return nil
        case .cancel:
            return nil
        }
    }

    private var postponeNotesPayload: String? {
        let nextVisit = DateFormatter.cpOutcomeDate.string(from: postponeFollowUpDate)
        let reason = postponeReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Next visit: \(nextVisit) — \(reason)"
    }

    private var notInterestedNotesPayload: String? {
        let reasonRows = selectedNotInterestedReasons
            .sorted { $0.title < $1.title }
            .map { reason -> String in
                if let detail = notInterestedReasonDetails[reason]?.nilIfBlank {
                    return "\(reason.title): \(detail)"
                }
                return reason.title
            }
        let rows = reasonRows + [
            notInterestedOtherNotes.nilIfBlank.map { "Notes: \($0)" }
        ].compactMap { $0 }
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

    private func parseServerDate(_ raw: String?) -> Date? {
        guard let raw = raw?.nilIfBlank else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    private func parseServerTime(_ raw: String?) -> Date? {
        guard let raw = raw?.nilIfBlank else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["HH:mm", "HH:mm:ss", "h:mm a", "hh:mm a"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private var initialOutcomeMarksFixedSiteVisit: Bool {
        normalizedServerValue(initialOutcome).isFixedSiteVisitMarker
    }

    private func normalizedServerValue(_ raw: String?) -> String {
        raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        ?? ""
    }
}

private extension CpVisitDetail {
    func hasFixedSiteVisitSignal(initialOutcome: String?) -> Bool {
        if proposedSiteVisit?.isMeaningful == true { return true }
        if convertedSiteVisitId?.nilIfBlank != nil { return true }
        if (expectedAttendeeCount ?? 0) > 0 { return true }
        if attendees?.isEmpty == false { return true }
        if foodPreferences?.nilIfBlank != nil { return true }
        if vehiclePreference?.nilIfBlank != nil { return true }

        return [
            initialOutcome,
            outcome,
            status,
            lead?.followUpStatus
        ]
        .contains { $0.normalizedCpMarker.isFixedSiteVisitMarker }
    }
}

private extension Optional where Wrapped == String {
    var normalizedCpMarker: String {
        self?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        ?? ""
    }
}

private extension String {
    var isFixedSiteVisitMarker: Bool {
        self == "converted_to_site_visit"
            || self == "site_visit"
            || self == "sitevisit"
            || self == "sv_fixed"
            || self == "sv_fix"
            || self == "svfixed"
            || self.contains("site_visit_fixed")
            || self.contains("fixed_site_visit")
            || self.contains("sv_fixed")
    }
}

private struct NewClientReferralSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var errorMessage: String?

    let onSave: (String, String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Client name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                    TextField("Client number", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Client address", text: $address, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                        .lineLimit(3...6)
                } header: {
                    Text("Referred client")
                } footer: {
                    Text("This person will appear in Clients with the referring client tagged.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add referral")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { validateAndSave() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func validateAndSave() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = phone.filter(\.isNumber)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Client name is required"
            return
        }
        guard digits.count >= 10 else {
            errorMessage = "Enter a valid client number"
            return
        }
        guard !trimmedAddress.isEmpty else {
            errorMessage = "Client address is required"
            return
        }
        onSave(trimmedName, String(digits.suffix(10)), trimmedAddress)
    }
}

private enum CpVisitOutcome: String, CaseIterable, Identifiable {
    case booking = "converted_to_booking"
    case siteVisit = "converted_to_site_visit"
    case postponed
    case notInterested = "not_interested"
    case other = "other"
    case referral = "referral"
    // UI-only tab identity. Cancel is NOT a setOutcome value; submit() branches
    // it to the separate clientPlaceVisits/cancel endpoint (SV-cum-CP only).
    case cancel = "__cancel__"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .booking: return "Booking"
        case .siteVisit: return "Site Visit"
        case .postponed: return "Follow-up"
        case .notInterested: return "Not Interested"
        case .other: return "Others"
        case .referral: return "Referral"
        case .cancel: return "Cancel"
        }
    }

    var icon: String {
        switch self {
        case .booking: return "checkmark.seal.fill"
        case .siteVisit: return "building.2.fill"
        case .postponed: return "calendar.badge.clock"
        case .notInterested: return "xmark.circle.fill"
        case .other: return "ellipsis.circle.fill"
        case .referral: return "person.crop.circle.badge.plus"
        case .cancel: return "xmark.bin"
        }
    }
}

private enum CpNotInterestedReason: String, CaseIterable, Identifiable {
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

private enum BookingSaveAs: String, CaseIterable, Identifiable, Hashable, Codable {
    case draft
    case confirmed

    var id: String { rawValue }
    var title: String { self == .draft ? "Draft" : "Confirmed" }
}

private struct BookingDraft: Codable, Equatable {
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
    var pattaCharges = ""
    var otherCharges = ""
    var otherChargesApplicable = true
    var advanceAmount = ""
    var paymentMode = ""
    var flexiPayment = true
    var allotmentDueAmount = ""
    var allotmentDueDate = ""
    var secondPaymentAmount = ""
    var secondPaymentDate = ""
    var thirdPaymentAmount = ""
    var thirdPaymentDate = ""
    var fourthPaymentAmount = ""
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

    /// True when nothing has been entered yet — used to skip persisting an empty
    /// form and to ignore an empty restored draft.
    var isEmpty: Bool { self == BookingDraft() }

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
            ("Document Charges", documentCharges), ("Patta Charges", pattaCharges),
            ("Other Charges", otherCharges),
            ("Other Charges If Applicable", otherChargesApplicable ? "Yes" : "No"),
            ("Advance Amount", advanceAmount), ("Payment Mode", paymentMode),
            ("Flexi Payment", flexiPayment ? "Yes" : "No"),
            ("Allotment Due Amount", allotmentDueAmount),
            ("Allotment Due Date", allotmentDueDate),
            ("2nd Payment Amount", secondPaymentAmount), ("2nd Payment Date", secondPaymentDate),
            ("3rd Payment Amount", thirdPaymentAmount), ("3rd Payment Date", thirdPaymentDate),
            ("4th Payment Amount", fourthPaymentAmount), ("4th Payment Date", fourthPaymentDate),
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

    func createRequest(
        cpVisitId: String,
        leadId: String?,
        projects: [MarketingProject],
        staff: [ConvexStaffListItem]
    ) -> CreateBookingRequest {
        let normalizedPhone = AppModuleFormatters.normalizePhone(phone)
        let matchedProject = projects.first {
            $0.name?.caseInsensitiveCompare(project) == .orderedSame
                || $0.id.caseInsensitiveCompare(project) == .orderedSame
        }
        func staffID(named name: String) -> String? {
            staff.first { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }?.id
        }
        let bookingDateValue = bookingDate.nilIfBlank ?? AppModuleFormatters.ymd.string(from: Date())
        let cost = Double(bookingCost.trimmingCharacters(in: .whitespacesAndNewlines))
        let advance = Double(advanceAmount.trimmingCharacters(in: .whitespacesAndNewlines))
        let special = Double(specialConsideration.trimmingCharacters(in: .whitespacesAndNewlines))

        return CreateBookingRequest(
            clientName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mobileNumber: normalizedPhone,
            bookingDate: bookingDateValue,
            leadId: leadId,
            title: title.nilIfBlank,
            fatherSpouseName: fatherOrSpouse.nilIfBlank,
            dateOfBirth: dob.nilIfBlank,
            anniversaryDate: anniversary.nilIfBlank,
            alternateNumbers: altNumber.nilIfBlank,
            whatsappNumber: whatsapp.nilIfBlank,
            projectId: matchedProject?.id,
            plotId: nil,
            plotNo: plot.nilIfBlank,
            bookingType: bookingType.nilIfBlank,
            cefNo: cefNo.nilIfBlank,
            isDuplicateBooking: duplicateBookings,
            isAgainstSV: isAgainstClientVisit,
            propertyType: propertyType.nilIfBlank,
            bookingMode: bookingMode.nilIfBlank,
            bookingCost: cost,
            guidelineValue: Double(guidelineValue),
            specialConsideration: special,
            specialConsiderationReason: scReason.nilIfBlank,
            discountApprovedBy: staffID(named: discountApprovedBy) ?? discountApprovedBy.nilIfBlank,
            specialConsiderationValidity: Double(scValidity),
            promotionalOffers: promotionalOffers.nilIfBlank,
            promotionalOffersTnC: promotionalOffersTnc.nilIfBlank,
            promotionalOfferValue: Double(promotionalOffersValue),
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
            paymentMode: paymentMode.nilIfBlank,
            paymentPlan: flexiPayment ? "Flexi" : "Regular",
            freePayment: flexiPayment,
            allotmentDueAmount: Double(allotmentDueAmount),
            allotmentDueDate: allotmentDueDate.nilIfBlank,
            secondPaymentAmount: Double(secondPaymentAmount),
            secondPaymentDate: secondPaymentDate.nilIfBlank,
            thirdPaymentAmount: Double(thirdPaymentAmount),
            thirdPaymentDate: thirdPaymentDate.nilIfBlank,
            fourthPaymentAmount: Double(fourthPaymentAmount),
            fourthPaymentDate: fourthPaymentDate.nilIfBlank,
            preferredRegistrationDate: preferredRegistrationDate.nilIfBlank,
            originalAvpStaffId: staffID(named: avp),
            originalGmStaffId: staffID(named: generalManager),
            originalSeniorManagerStaffId: staffID(named: seniorManager),
            originalBdoStaffId: staffID(named: bdo),
            originalTelecallerStaffId: staffID(named: telecaller),
            aadhaar: aadhar.nilIfBlank,
            pan: pancard.nilIfBlank,
            referenceName1: referenceName1.nilIfBlank,
            referenceMobile1: referenceMobile1.nilIfBlank,
            referenceProfession1: referenceProfession1.nilIfBlank,
            referenceName2: referenceName2.nilIfBlank,
            referenceMobile2: referenceMobile2.nilIfBlank,
            referenceProfession2: referenceProfession2.nilIfBlank,
            docPreparedIn: documentLanguage.nilIfBlank,
            email: email.nilIfBlank,
            pincode: pincode.nilIfBlank,
            homeAddress: homeAddress.nilIfBlank,
            profession: profession.nilIfBlank,
            designation: designation.nilIfBlank,
            incomePerAnnum: incomePerAnnum.nilIfBlank,
            officeName: officeName.nilIfBlank,
            officeAddress: officeAddress.nilIfBlank,
            state: state.nilIfBlank,
            district: district.nilIfBlank,
            location: location.nilIfBlank,
            officeMobile: officeMobile.nilIfBlank,
            officePhone: officePhone.nilIfBlank,
            officeEmail: officeEmail.nilIfBlank,
            nationality: nationality.nilIfBlank,
            cpVisitId: cpVisitId,
            source: "cp_visit",
            status: saveAs == .confirmed ? "pending_confirmation" : "draft",
            sourceType: sourceType.nilIfBlank ?? "cp_visit",
            // Mark the CP the booking's source (mirrors Android) so the backend
            // spawns a booking_cp for the same staff/client on the booking date.
            sourceClientPlaceVisitId: cpVisitId,
            bookingCpDate: bookingDateValue,
            notes: serializedNotes
        )
    }
}

private struct CpVisitorDraft: Identifiable, Hashable {
    let id = UUID()
    var name = ""
    var relation = ""
    var age = ""
    var isVeg = true
}

private struct CpActionReasonSheet: View {
    let title: String
    let subtitle: String
    let fieldLabel: String
    let placeholder: String
    let submitTitle: String
    let isSaving: Bool
    let onSubmit: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(fieldLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    TextField(placeholder, text: $reason, axis: .vertical)
                        .font(.system(size: 13))
                        .lineLimit(3...6)
                        .padding(14)
                        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0xB42318))
                }

                Button {
                    let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        errorMessage = "Remarks are required"
                        return
                    }
                    errorMessage = nil
                    Task { await onSubmit(trimmed) }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(submitTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(hex: 0x2DAE12))
                .disabled(isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .background(Color.appSurface)
        .appCompactSheetCTAContainer()
    }
}

private struct OutcomeTabView: View {
    let outcome: CpVisitOutcome
    let isSelected: Bool
    var titleOverride: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color(hex: 0x0B61CA) : Color.appFieldBackground)
                    .frame(width: 36, height: 36)
                Image(systemName: outcome.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Color(hex: 0x6A6D78))
            }
            Text(titleOverride ?? outcome.title)
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
                        : AnyShapeStyle(Color.appFieldBackground),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? .clear : Color.appSeparator, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ReasonToggleRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: 0x1ECB09) : Color(hex: 0x98A2B3))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(isSelected ? Color(hex: 0x2DAE12).opacity(0.14) : Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(hex: 0x86EFAC) : Color.appSeparator, lineWidth: 1)
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
                    : AnyShapeStyle(Color.appFieldBackground),
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
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
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
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(value.nilIfBlank ?? "-")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
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
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: axis == .vertical ? 72 : 48)
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text.isEmpty ? placeholder : text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(text.isEmpty ? Color(hex: 0x94A3B8) : Color(hex: 0x101828))
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
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
                .foregroundStyle(.secondary)
            Button {
                selectedDate = Self.dateFormatter.date(from: text) ?? Date()
                isPickingDate = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(text.isEmpty ? placeholder : text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(text.isEmpty ? Color(hex: 0x94A3B8) : Color(hex: 0x101828))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
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
            .appLibraryNativeSheet([.medium])
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
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
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
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
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
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Color.appFieldBackground, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
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
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            self
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension DateFormatter {
    static let cpOutcomeDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    static let cpOutcomeDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy hh:mm a"
        return formatter
    }()
}
