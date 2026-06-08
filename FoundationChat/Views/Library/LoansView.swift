import SwiftUI

struct LoansView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var active: [AppLoan] = []
    @State private var previous: [AppLoan] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showingLoanRequest = false
    @State private var showingSalaryAdvance = false
    @State private var selectedTab: LoansScreenTab = .loans

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                loansContent
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Loans")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .sheet(isPresented: $showingLoanRequest) {
            LoanRequestSheet {
                await load()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSalaryAdvance) {
            SalaryAdvanceRequestSheet {
                await load()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Couldn't load loans", isPresented: Binding(
            get: { errorMessage != nil && active.isEmpty && previous.isEmpty && hasLoaded },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x02499D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("My Loans")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Manage salary advances and loan repayments")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "indianrupeesign.circle.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(.white)
                    .opacity(0.9)
            }
            .padding(.horizontal, 24)
            .padding(.top, 42)
        }
        .frame(height: 212)
    }

    private var loansContent: some View {
        VStack(spacing: 16) {
            if selectedTab == .loans, let hero = active.first {
                NavigationLink {
                    RepaymentHistoryView(loanId: hero.id, status: hero.status)
                } label: {
                    LoanHeroCard(loan: hero)
                }
                .buttonStyle(.plain)
            } else {
                emptyHeroCard
            }

            loanTabs
            actionButtons

            if selectedTab == .salary {
                salaryAdvanceInfo
            } else if isLoading && !hasLoaded {
                AppModuleLoadingRows()
                    .padding(.horizontal)
            } else if active.isEmpty && previous.isEmpty {
                ContentUnavailableView(
                    "No Loans",
                    systemImage: "indianrupeesign.circle",
                    description: Text(errorMessage ?? "When your finance team disburses a loan, you'll see it grouped here with EMI dates and repayment history.")
                )
                .padding(.vertical, 34)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal)
            } else {
                if active.count > 1 {
                    loanSectionTitle("Active Loans", count: active.count - 1)
                    LazyVStack(spacing: 12) {
                        ForEach(Array(active.dropFirst())) { loan in
                            NavigationLink {
                                RepaymentHistoryView(loanId: loan.id, status: loan.status)
                            } label: {
                                PreviousLoanRow(loan: loan)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                if !previous.isEmpty {
                    loanSectionTitle("Previous Loans", count: previous.count)
                    LazyVStack(spacing: 12) {
                        ForEach(previous) { loan in
                            NavigationLink {
                                RepaymentHistoryView(loanId: loan.id, status: loan.status)
                            } label: {
                                PreviousLoanRow(loan: loan)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, -64)
    }

    private var emptyHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "banknote.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0xEAF3FF), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTab == .salary ? "Salary Advance" : "No Active Loan")
                        .font(.system(size: 18, weight: .bold))
                    Text(selectedTab == .salary ? "Request advance from this tab" : "Active loan card appears here")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
            }
            Divider()
            HStack(spacing: 12) {
                metricTile("Outstanding", "₹0")
                metricTile("Next EMI", "—")
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }

    private func loanSectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
            Spacer()
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x667085))
        }
        .padding(.horizontal, 20)
    }

    private func metricTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12))
    }

    private var loanTabs: some View {
        Picker("Loan type", selection: $selectedTab) {
            ForEach(LoansScreenTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if selectedTab == .loans {
                Button {
                    showingLoanRequest = true
                } label: {
                    Label("Create Loan", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(hex: 0x0B61CA))
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    showingSalaryAdvance = true
                } label: {
                    Label("Create Salary Advance", systemImage: "indianrupeesign.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(hex: 0x0B61CA))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    private var salaryAdvanceInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Salary Advance")
                .font(AppModuleFont.rowTitle)
                .foregroundStyle(Color(hex: 0x101828))
            Text("Use this tab to request an advance against salary. Submitted requests are handled through the same loan approval flow.")
                .font(AppModuleFont.rowBody)
                .foregroundStyle(Color(hex: 0x667085))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
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
            let page = try await MarketingConvexAPIService.getMyLoans(
                token: token,
                staffId: authStore.currentSession?.user.staffId
            )
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                active = page.active
                previous = page.previous
            }
            errorMessage = nil
        } catch {
            if Self.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as NSError).code == NSURLErrorCancelled
    }
}

private enum LoansScreenTab: String, CaseIterable, Identifiable {
    case loans
    case salary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loans: return "Loans"
        case .salary: return "Salary"
        }
    }
}

private struct LoanRequestSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let onSubmitted: () async -> Void

    @State private var staff: [ConvexStaffListItem] = []
    @State private var selectedStaff: ConvexStaffListItem?
    @State private var selectedNominee1: ConvexStaffListItem?
    @State private var selectedNominee2: ConvexStaffListItem?
    @State private var amount = ""
    @State private var interestType = "Flat"
    @State private var disbursedDate = Date()
    @State private var repaymentStartMonth = Date()
    @State private var tenure = ""
    @State private var submittedDocument = "Aadhaar Card"
    @State private var purpose = ""
    @State private var notes = ""
    @State private var isLoadingStaff = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let interestOptions = ["Flat", "Reducing"]
    private let documentOptions = ["Aadhaar Card", "PAN Card", "Salary Slip", "Bond Certificate", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Staff") {
                    Menu {
                        ForEach(staff) { item in
                            Button {
                                selectedStaff = item
                            } label: {
                                if selectedStaff?.id == item.id {
                                    Label(item.displayName, systemImage: "checkmark")
                                } else {
                                    Text(item.displayName)
                                }
                            }
                        }
                    } label: {
                        pickerRow("Staff", value: selectedStaff?.displayName ?? "Select staff")
                    }

                    nomineePicker(title: "Nominee 1", selection: $selectedNominee1)
                    nomineePicker(title: "Nominee 2", selection: $selectedNominee2)
                }

                Section("Loan") {
                    TextField("Loan amount", text: $amount)
                        .keyboardType(.decimalPad)
                    Menu {
                        ForEach(interestOptions, id: \.self) { option in
                            Button(option) { interestType = option }
                        }
                    } label: {
                        pickerRow("Interest type", value: interestType)
                    }
                    DatePicker("Disbursed date", selection: $disbursedDate, displayedComponents: .date)
                    DatePicker("Repayment start month", selection: $repaymentStartMonth, displayedComponents: .date)
                    TextField("Tenure in months", text: $tenure)
                        .keyboardType(.numberPad)
                    Menu {
                        ForEach(documentOptions, id: \.self) { document in
                            Button(document) { submittedDocument = document }
                        }
                    } label: {
                        pickerRow("Submitted document", value: submittedDocument)
                    }
                    TextField("Purpose", text: $purpose, axis: .vertical)
                        .lineLimit(3...5)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Create Loan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting || isLoadingStaff)
                }
            }
            .task { await loadStaff() }
        }
    }

    private func pickerRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func nomineePicker(title: String, selection: Binding<ConvexStaffListItem?>) -> some View {
        Menu {
            ForEach(staff.filter { $0.id != selectedStaff?.id }) { item in
                Button {
                    selection.wrappedValue = item
                } label: {
                    if selection.wrappedValue?.id == item.id {
                        Label(item.displayName, systemImage: "checkmark")
                    } else {
                        Text(item.displayName)
                    }
                }
            }
        } label: {
            pickerRow(title, value: selection.wrappedValue?.displayName ?? "Select nominee")
        }
    }

    @MainActor
    private func loadStaff() async {
        guard staff.isEmpty, let token = authStore.currentSession?.token else { return }
        isLoadingStaff = true
        defer { isLoadingStaff = false }
            do {
                staff = try await HRConvexAPIService.listAllStaff(token: token).filter(\.isActive)
                if selectedStaff == nil {
                    selectedStaff = staff.first { $0.id == authStore.currentSession?.user.staffId } ?? staff.first
                }
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                errorMessage = error.localizedDescription
            }
    }

    private func submit() {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            return
        }
        guard let selectedStaff else {
            errorMessage = "Select staff."
            return
        }
        guard let nominee1 = selectedNominee1 else {
            errorMessage = "Select Nominee 1."
            return
        }
        guard let nominee2 = selectedNominee2 else {
            errorMessage = "Select Nominee 2."
            return
        }
        guard nominee1.id != nominee2.id else {
            errorMessage = "Nominee 1 and Nominee 2 cannot be the same person."
            return
        }
        let cleanedAmount = amount.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let loanAmount = Double(cleanedAmount), loanAmount > 0 else {
            errorMessage = "Enter a valid loan amount."
            return
        }
        guard let tenureMonths = Int(tenure.trimmingCharacters(in: .whitespacesAndNewlines)), tenureMonths > 0 else {
            errorMessage = "Enter a valid tenure."
            return
        }
        guard tenureMonths <= 6 else {
            errorMessage = "Tenure cannot exceed 6 months."
            return
        }
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPurpose.isEmpty else {
            errorMessage = "Enter purpose."
            return
        }

        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            do {
                try await MarketingConvexAPIService.createLoanRequest(
                    token: token,
                    staffId: selectedStaff.id,
                    nomineeStaffId: nominee1.id,
                    nominee1Id: nominee1.id,
                    nominee1Name: nominee1.displayName,
                    nominee2Id: nominee2.id,
                    nominee2Name: nominee2.displayName,
                    loanAmount: loanAmount,
                    interestType: interestType,
                    disbursedDate: AppModuleFormatters.ymd.string(from: disbursedDate),
                    repaymentStartMonth: monthFormatter.string(from: repaymentStartMonth),
                    tenureMonths: tenureMonths,
                    submittedDocument: submittedDocument,
                    purpose: trimmedPurpose,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForLoan
                )
                await onSubmitted()
                dismiss()
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }
}

private struct SalaryAdvanceRequestSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let onSubmitted: () async -> Void

    @State private var amount = ""
    @State private var purpose = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Salary Advance") {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("Purpose", text: $purpose, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Salary Advance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Submitting..." : "Submit") {
                        submit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            return
        }
        let cleanedAmount = amount.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let advanceAmount = Double(cleanedAmount), advanceAmount > 0 else {
            errorMessage = "Enter a valid amount."
            return
        }
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            do {
                try await MarketingConvexAPIService.createSalaryAdvanceRequest(
                    token: token,
                    amount: advanceAmount,
                    purpose: trimmedPurpose.isEmpty ? nil : trimmedPurpose
                )
                await onSubmitted()
                dismiss()
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct LoanHeroCard: View {
    let loan: AppLoan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: loan.type == .education ? "graduationcap.fill" : "house.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0xEAF3FF), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(loan.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text("Loan ID: \(loan.loanId.isEmpty ? "—" : loan.loanId)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                AppModuleBadge(
                    text: loan.status == .pending ? "Pending" : "Active Loan",
                    tint: loan.status == .pending ? .orange : .blue
                )
            }

            HStack(spacing: 14) {
                metric("Outstanding", AppModuleFormatters.rupees(loan.outstandingBalance))
                metric("Next EMI", loan.nextEmiAmount > 0 ? AppModuleFormatters.rupees(loan.nextEmiAmount) : "—")
                metric("Due Date", loan.nextEmiDueDate.map(AppModuleFormatters.day.string) ?? "—")
            }

            Label("View Repayment History", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(hex: 0xEAF3FF), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PreviousLoanRow: View {
    let loan: AppLoan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: loan.type == .education ? "graduationcap.fill" : "house.fill")
                .font(.headline)
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 38, height: 38)
                .background(Color(hex: 0xEAF3FF), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(loan.title)
                    .font(AppModuleFont.rowTitle)
                Text("Principal \(AppModuleFormatters.rupees(loan.principal))")
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct RepaymentHistoryView: View {
    @Environment(AuthStore.self) private var authStore
    let loanId: String
    let status: AppLoanStatus

    @State private var repayments: [AppRepayment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading && repayments.isEmpty {
                ProgressView("Loading repayments…")
            } else if repayments.isEmpty {
                ContentUnavailableView(
                    "No Repayments",
                    systemImage: "calendar.badge.clock",
                    description: Text(errorMessage ?? "Repayment timeline will appear here.")
                )
            } else {
                ForEach(Array(repayments.enumerated()), id: \.element.id) { index, repayment in
                    RepaymentTimelineRow(
                        repayment: repayment,
                        isFirst: index == 0,
                        isLast: index == repayments.count - 1
                    )
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Repayment History")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loan = try await MarketingConvexAPIService.getLoanDetail(token: token, id: loanId, mappedStatus: status)
            repayments = loan.repayments.sorted {
                ($0.dueDate ?? .distantPast) > ($1.dueDate ?? .distantPast)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RepaymentTimelineRow: View {
    let repayment: AppRepayment
    let isFirst: Bool
    let isLast: Bool

    private var tint: Color {
        switch repayment.status {
        case .paid: return .green
        case .upcoming: return Color(hex: 0x0B61CA)
        case .overdue: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? .clear : Color(.systemGray4)).frame(width: 2, height: 16)
                ZStack {
                    Circle().fill(tint).frame(width: 28, height: 28)
                    Image(systemName: repayment.status == .paid ? "checkmark" : "clock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
                Rectangle().fill(isLast ? .clear : Color(.systemGray4)).frame(width: 2, height: 42)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(repayment.dueDate.map(AppModuleFormatters.day.string) ?? "—")
                            .font(AppModuleFont.rowTitle)
                        Text("EMI #\(repayment.emiIndex)")
                            .font(AppModuleFont.rowMeta)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(AppModuleFormatters.rupees(repayment.amount))
                        .font(AppModuleFont.rowTitle)
                }
                AppModuleBadge(text: repayment.status.rawValue, tint: tint)
                if repayment.status == .paid {
                    Text("Paid via \(repayment.paidVia ?? "Bank") · \(repayment.onTime ? "Payment On Time" : "Late Payment")")
                        .font(AppModuleFont.rowMeta)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private extension String {
    var nilIfBlankForLoan: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
