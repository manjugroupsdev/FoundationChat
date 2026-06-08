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

    private var filteredBookings: [AppBooking] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bookings.filter { booking in
            let statusMatch = selectedStatus.matches(booking.displayStatus)
            guard statusMatch else { return false }
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
            bookingTopBar
            Divider()
                .background(Color(hex: 0xEEF0F5))
            searchBar
            filterBar
            content
        }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCreate, onDismiss: {
            Task { await load() }
        }) {
            NavigationStack {
                BookingCreateView()
            }
        }
        .task { if !hasLoaded { await load() } }
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
                title: "No Bookings",
                message: "Bookings will appear here.",
                systemImage: "doc.text.magnifyingglass"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredBookings) { booking in
                        NavigationLink {
                            BookingDetailView(bookingId: booking.id) {
                                Task { await load() }
                            }
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

    private var bookingTopBar: some View {
        HStack {
            Color.clear
                .frame(width: 44, height: 44)

            Spacer()

            Text("Booking")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            Spacer()

            Button {
                showCreate = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: 0x0B61CA))
            .frame(width: 44, height: 44)
            .accessibilityLabel("Create booking")
        }
        .padding(.horizontal, 4)
        .frame(height: 56)
        .background(Color.white)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            TextField("Search Bookings", text: $searchText)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(hex: 0x9CA3AF))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BookingStatusFilter.allCases) { status in
                    Button {
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
            bookings = try await MarketingConvexAPIService.listBookings(token: token)
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
    let bookingId: String
    let onChanged: () -> Void

    @State private var booking: AppBooking?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showEdit = false
    @State private var showReject = false
    @State private var rejectReason = ""

    var body: some View {
        ScrollView {
            if isLoading && booking == nil {
                ProgressView("Loading booking...")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if let booking {
                VStack(spacing: 14) {
                    BookingDetailHero(booking: booking)

                    BookingDetailSection(title: "Client") {
                        BookingDetailLine(title: "Name", value: booking.clientName)
                        BookingDetailLine(title: "Mobile", value: booking.mobileNumber)
                        BookingDetailLine(title: "Source", value: booking.source)
                        BookingDetailLine(title: "Status", value: booking.displayStatus.capitalized)
                    }

                    BookingDetailSection(title: "Booking") {
                        BookingDetailLine(title: "Reference", value: booking.bookingRefNo)
                        BookingDetailLine(title: "Date", value: booking.bookingDate)
                        BookingDetailLine(title: "Project", value: booking.projectName ?? booking.projectId)
                        BookingDetailLine(title: "Plot", value: booking.plotNo)
                        BookingDetailLine(title: "Type", value: booking.bookingType)
                        BookingDetailLine(title: "Mode", value: booking.bookingMode)
                    }

                    BookingDetailSection(title: "Amount") {
                        BookingDetailLine(title: "Booking cost", value: booking.bookingCost.map(AppModuleFormatters.rupees))
                        BookingDetailLine(title: "Advance", value: booking.advanceAmount.map(AppModuleFormatters.rupees))
                        BookingDetailLine(title: "Balance", value: booking.balanceAmount.map(AppModuleFormatters.rupees))
                    }

                    if let notes = booking.notes?.nilIfBlank {
                        BookingDetailSection(title: "Notes") {
                            Text(notes)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: 0x475467))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    VStack(spacing: 10) {
                        Button("Update Booking") { showEdit = true }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        Button("Approve Booking") { Task { await approve() } }
                            .buttonStyle(.bordered)
                            .disabled(isSaving)
                            .frame(maxWidth: .infinity)
                        Button("Reject Booking", role: .destructive) { showReject = true }
                            .buttonStyle(.bordered)
                            .disabled(isSaving)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .padding(.top, 2)
                }
                .padding(16)
            }
        }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("Booking Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showEdit) {
            if let booking {
                BookingUpdateSheet(booking: booking) {
                    showEdit = false
                    await load()
                    onChanged()
                }
                .environment(authStore)
            }
        }
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

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            booking = try await MarketingConvexAPIService.getBooking(token: token, id: bookingId)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(booking.clientName?.nilIfBlank ?? "Unnamed client")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)

                Spacer()

                BookingStatusPill(status: booking.displayStatus)
            }

            Text(bookingMeta)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x667085))
                .lineLimit(1)
                .padding(.top, 3)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))

                Text(booking.bookingDate?.nilIfBlank ?? "-")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x344054))
                    .lineLimit(1)

                Spacer()

                Text(amountText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, y: 3)
    }

    private var bookingMeta: String {
        let ref = booking.bookingRefNo?.nilIfBlank
        let project = booking.projectName?.nilIfBlank
        let plot = booking.plotNo?.nilIfBlank
        let text = [ref, project, plot].compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? "Reference not available" : text
    }

    private var amountText: String {
        if let cost = booking.bookingCost {
            return AppModuleFormatters.rupees(cost)
        }
        return AppModuleFormatters.rupees(0)
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
