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
        ZStack {
            Color(hex: 0xF1F3F8)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    loansContent
                }
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(false)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Manage Loans and Advances")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xD9D6FE))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Image("LoansHeaderArt")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 110)
                    .offset(x: 8)
            }
            .padding(.leading, 16)
            .padding(.trailing, 0)
            .padding(.top, 86)
        }
        .frame(height: 236)
        .ignoresSafeArea(edges: .top)
    }

    private var loansContent: some View {
        VStack(spacing: 0) {
            if selectedTab == .loans, let hero = active.first {
                NavigationLink {
                    RepaymentHistoryView(loanId: hero.id, status: hero.status)
                } label: {
                    LoanHeroCard(loan: hero)
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            } else {
                emptyHeroCard
                    .padding(.top, 20)
            }

            loansControlRow
                .padding(.top, 16)

            if selectedTab == .salary {
                salaryAdvanceInfo
                    .padding(.top, 22)
            } else if isLoading && !hasLoaded {
                AppModuleLoadingRows()
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
            } else if active.isEmpty && previous.isEmpty {
                loansEmptyState
                    .padding(.top, 48)
            } else {
                if active.count > 1 {
                    loanSectionTitle("Requested Loans", count: active.count - 1)
                        .padding(.top, 22)
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
                    .padding(.horizontal, 16)
                }

                if !previous.isEmpty {
                    loanSectionTitle("Previous Loans", count: previous.count, showsViewAll: true)
                        .padding(.top, 22)
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
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 32)
        .background(Color.white)
        .clipShape(.rect(topLeadingRadius: 30, topTrailingRadius: 30))
        .padding(.top, -44)
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
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private func loanSectionTitle(_ title: String, count: Int, showsViewAll: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
            Spacer()
            if showsViewAll {
                Text("View All")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            } else {
                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
            }
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

    private var loansControlRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(LoansScreenTab.allCases) { tab in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 15, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundStyle(selectedTab == tab ? .white : Color(hex: 0x475467))
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(selectedTab == tab ? Color(hex: 0x0B61CA) : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .frame(height: 38)
            .background(Color(hex: 0xEAECF0), in: Capsule())

            Button {
                if selectedTab == .loans {
                    showingLoanRequest = true
                } else {
                    showingSalaryAdvance = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .frame(width: 38, height: 38)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private var salaryAdvanceInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Salary Advance")
                .font(AppModuleFont.rowTitle)
                .foregroundStyle(Color(hex: 0x101828))
            Text("Use this tab to request an advance against salary. Submitted requests are handled through the same approval flow.")
                .font(AppModuleFont.rowBody)
                .foregroundStyle(Color(hex: 0x667085))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var loansEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "indianrupeesign.circle")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color(hex: 0x98A2B3))
            Text("No Loans Yet")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
            Text(errorMessage ?? "When your finance team disburses a loan, you'll see it grouped here with EMI dates and a full repayment history.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Capsule()
                        .fill(Color(hex: 0xD9D9D9))
                        .frame(width: 52, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    Text("Request Loan")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text("Information about Loans")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                        .padding(.top, 2)
                        .padding(.bottom, 16)

                    nomineeMenuField(title: "Nominee 1 *", selection: $selectedNominee1)
                    nomineeMenuField(title: "Nominee 2 *", selection: $selectedNominee2)

                    Text("Both Nominee must approve with a digital signature before the request moves to GM->AVP->HR->Accountant.")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color(hex: 0xB1B1B1))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 24)

                    loanTextField(title: "Loan Amount *", placeholder: "Enter Amount", icon: "indianrupeesign.circle", text: $amount, keyboard: .decimalPad)

                    menuField(title: "Interest Type", value: interestType, placeholder: "Select Type", icon: "doc.text") {
                        ForEach(interestOptions, id: \.self) { option in
                            Button(option) { interestType = option }
                        }
                    }

                    dateInputField(title: "Disbursed Date *", value: $disbursedDate, components: .date, placeholder: "Select Date")
                    dateInputField(title: "Repayment Start Month *", value: $repaymentStartMonth, components: .date, placeholder: "Select Month")

                    loanTextField(title: "Tenure (Months) *", placeholder: "Maximum 6", icon: "clock", text: $tenure, keyboard: .numberPad)

                    menuField(title: "Original Document To be Submit *", value: submittedDocument, placeholder: "Select the document", icon: "doc.text") {
                        ForEach(documentOptions, id: \.self) { document in
                            Button(document) { submittedDocument = document }
                        }
                    }

                    loanTextField(title: "Purpose", placeholder: "Enter Details", icon: "doc.text", text: $purpose, keyboard: .default)
                    loanTextField(title: "Notes", placeholder: "Enter Notes", icon: "note.text", text: $notes, keyboard: .default, minHeight: 80, axis: .vertical)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xB42318))
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }

            VStack(spacing: 0) {
                Divider()
                    .overlay(Color(hex: 0xD0D5DD))
                Button {
                    submit()
                } label: {
                    ZStack {
                        Text("Submit Now")
                            .opacity(isSubmitting ? 0 : 1)
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(loanSubmitGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || isLoadingStaff)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.white)
            }
        }
        .task { await loadStaff() }
    }

    private func nomineeMenuField(title: String, selection: Binding<ConvexStaffListItem?>) -> some View {
        menuField(title: title, value: selection.wrappedValue?.displayName ?? "", placeholder: "Select Nominee", icon: "person.crop.circle") {
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
        }
    }

    private func menuField<Content: View>(
        title: String,
        value: String,
        placeholder: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            inputShell(title: title, icon: icon, trailingChevron: true) {
                Text(value.isEmpty ? placeholder : value)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(value.isEmpty ? Color(hex: 0x98A2B3) : Color(hex: 0x101828))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func dateInputField(title: String, value: Binding<Date>, components: DatePickerComponents, placeholder: String) -> some View {
        inputShell(title: title, icon: "calendar", trailingChevron: true) {
            DatePicker(placeholder, selection: value, displayedComponents: components)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Color(hex: 0x0B61CA))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loanTextField(
        title: String,
        placeholder: String,
        icon: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        minHeight: CGFloat = 44,
        axis: Axis = .horizontal
    ) -> some View {
        inputShell(title: title, icon: icon, minHeight: minHeight) {
            TextField(placeholder, text: text, axis: axis)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: 0x101828))
                .keyboardType(keyboard)
                .lineLimit(axis == .vertical ? 3...5 : 1...1)
                .frame(maxWidth: .infinity, minHeight: max(24, minHeight - 20), alignment: .leading)
        }
    }

    private func inputShell<Content: View>(
        title: String,
        icon: String,
        minHeight: CGFloat = 44,
        trailingChevron: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x344054))
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(width: 20)
                content()
                if trailingChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x667085))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, minHeight > 44 ? 10 : 0)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }
        }
        .padding(.bottom, 12)
    }

    private var loanSubmitGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)], startPoint: .leading, endPoint: .trailing)
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
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(Color(hex: 0xD9D9D9))
                    .frame(width: 52, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                Text("Request Advance")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Text("Information about Salary Advance")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: 0x667085))
                    .padding(.top, 2)
                    .padding(.bottom, 16)

                advanceInput(title: "Amount *", placeholder: "Enter Amount", icon: "indianrupeesign.circle", text: $amount, keyboard: .decimalPad)
                advanceInput(title: "Purpose", placeholder: "Enter Details", icon: "doc.text", text: $purpose, keyboard: .default, minHeight: 80, axis: .vertical)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0xB42318))
                        .padding(.top, 4)
                }

                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                Divider()
                    .overlay(Color(hex: 0xD0D5DD))
                Button {
                    submit()
                } label: {
                    ZStack {
                        Text("Submit Now")
                            .opacity(isSubmitting ? 0 : 1)
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(LinearGradient(colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.white)
            }
        }
    }

    private func advanceInput(
        title: String,
        placeholder: String,
        icon: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        minHeight: CGFloat = 44,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x344054))
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(width: 20)
                TextField(placeholder, text: text, axis: axis)
                    .font(.system(size: 14, weight: .regular))
                    .keyboardType(keyboard)
                    .lineLimit(axis == .vertical ? 3...5 : 1...1)
                    .frame(maxWidth: .infinity, minHeight: max(24, minHeight - 20), alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, minHeight > 44 ? 10 : 0)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }
        }
        .padding(.bottom, 12)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: loanIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0xEAF3FF), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(loan.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text("Loan ID: \(loan.loanId.isEmpty ? "—" : loan.loanId)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                Text(loan.status == .pending ? "Pending" : "Active Loan")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(loan.status == .pending ? Color(hex: 0xF79009) : Color(hex: 0x0B61CA))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background((loan.status == .pending ? Color(hex: 0xFFF4E5) : Color(hex: 0xEAF3FF)), in: Capsule())
            }

            Divider()
                .overlay(Color(hex: 0xF2F4F7))

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Outstanding Amount")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x6B7280))
                    Text(AppModuleFormatters.rupees(loan.outstandingBalance))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x111827))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color(hex: 0xE4E7EC))
                    .frame(width: 1, height: 32)
                    .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(loan.status == .pending ? "Next EMI Amount" : "Next EMI Due")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x6B7280))
                    HStack(spacing: 4) {
                        if loan.status != .pending {
                            Image(systemName: "calendar")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x0B61CA))
                        }
                        Text(nextEmiDisplay)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(loan.status == .pending ? Color(hex: 0x111827) : Color(hex: 0x0B61CA))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Label("View Repayment History", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(hex: 0xEAF3FF), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.white)
    }

    private var loanIcon: String {
        switch loan.type {
        case .education: return "graduationcap.fill"
        case .home: return "house.fill"
        case .other: return "indianrupeesign"
        }
    }

    private var nextEmiDisplay: String {
        if loan.status == .pending {
            return loan.nextEmiAmount > 0 ? AppModuleFormatters.rupees(loan.nextEmiAmount) : "—"
        }
        return loan.nextEmiDueDate.map(AppModuleFormatters.day.string) ?? "—"
    }
}

private struct PreviousLoanRow: View {
    let loan: AppLoan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: loan.type == .education ? "graduationcap.fill" : "house.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: 0xF2F4F7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(loan.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text(loan.loanId.isEmpty ? "—" : loan.loanId)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                Text(loan.status == .repaid ? "• REPAID" : "• \(loan.status.rawValue.uppercased())")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(loan.status == .pending ? Color(hex: 0xF79009) : Color(hex: 0x12B76A))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((loan.status == .pending ? Color(hex: 0xFFF4E5) : Color(hex: 0xECFDF3)), in: Capsule())
            }

            Divider()
                .overlay(Color(hex: 0xF2F4F7))

            HStack(spacing: 0) {
                metricColumn("Principal", AppModuleFormatters.rupees(loan.principal))
                Rectangle()
                    .fill(Color(hex: 0xE4E7EC))
                    .frame(width: 1, height: 32)
                    .padding(.horizontal, 8)
                metricColumn("Disbursed", loan.disbursedDate.map(AppModuleFormatters.day.string) ?? "—")
            }

            Text("View Repayment History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(hex: 0x0B61CA), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metricColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
