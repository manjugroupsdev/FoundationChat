import SwiftUI

private struct LoansCacheSnapshot: Codable {
    let active: [AppLoan]
    let previous: [AppLoan]
    let pendingApprovals: [AppLoan]
}

struct LoansView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var active: [AppLoan] = []
    @State private var previous: [AppLoan] = []
    @State private var pendingApprovals: [AppLoan] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showingLoanRequest = false
    @State private var showingSalaryAdvance = false
    @State private var selectedTab: LoansScreenTab = .loans
    @State private var loanPendingCancel: AppLoan?
    @State private var isCancellingLoan = false
    @State private var actingLoanId: String?
    @State private var signatureApprovalLoan: AppLoan?
    @State private var didHydrateCache = false

    private var headerHeight: CGFloat {
        selectedTab == .salary ? 174 : 190
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: 0xF1F3F8)
                .ignoresSafeArea()

            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: headerHeight)
                    loansContent
                }
                .padding(.bottom, 40)
            }
            .ignoresSafeArea(edges: .top)

            if let loanPendingCancel {
                cancelLoanDialog(for: loanPendingCancel)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(false)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showingLoanRequest) {
            LoanRequestSheet {
                await load()
            }
            .appFormActivity()
            .appLibraryNativeSheet([.height(720), .large])
            .presentationBackground(Color.white)
        }
        .sheet(isPresented: $showingSalaryAdvance) {
            SalaryAdvanceRequestSheet {
                await load()
            }
            .appFormActivity()
            .appLibraryNativeSheet([.height(520), .large])
            .presentationBackground(Color.white)
        }
        .sheet(item: $signatureApprovalLoan) { loan in
            LoanSignatureApprovalSheet(loan: loan) {
                await load()
            }
            .appLibraryNativeSheet([.height(650), .large])
        }
        .alert("Loans", isPresented: Binding(
            get: { errorMessage != nil && hasLoaded },
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
                    Text(selectedTab == .salary ? "My Advances" : "My Loans")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Manage Loans and Salary\nAdvance")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xD9D6FE))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Image("LoansHeaderArt")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 118, height: 82)
                    .offset(x: 2, y: -2)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.top, 64)
        }
        .frame(height: headerHeight)
        .ignoresSafeArea(edges: .top)
    }

    private var loansContent: some View {
        let visibleActive = activeLoansForSelectedTab
        let visiblePrevious = previousLoansForSelectedTab
        let visibleApprovals = selectedTab == .salary ? pendingSalaryApprovals : pendingLoanApprovals

        return VStack(spacing: 0) {
            if selectedTab == .loans, let hero = visibleActive.first {
                if hero.status == .pending {
                    LoanHeroCard(loan: hero) {
                        loanPendingCancel = hero
                    }
                    .padding(.top, 20)
                } else {
                    NavigationLink {
                        RepaymentHistoryView(loanId: hero.id, status: hero.status)
                    } label: {
                        LoanHeroCard(loan: hero)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                }
            } else if selectedTab == .loans && visiblePrevious.isEmpty {
                emptyHeroCard
                    .padding(.top, 20)
            } else if selectedTab == .salary, let hero = visibleActive.first {
                AdvanceHeroCard(loan: hero) {
                    loanPendingCancel = hero
                }
                .padding(.top, 16)
            }

            loansControlRow
                .padding(.top, 16)

            if isLoading && !hasLoaded {
                AppModuleLoadingRows()
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
            } else if visibleActive.isEmpty && visiblePrevious.isEmpty && visibleApprovals.isEmpty {
                loansEmptyState
                    .padding(.top, 48)
            } else {
                if selectedTab == .salary {
                    salaryAdvanceSections(
                        active: visibleActive,
                        previous: visiblePrevious,
                        approvals: pendingSalaryApprovals
                    )
                } else {
                    loanSections(
                        active: visibleActive,
                        previous: visiblePrevious,
                        approvals: pendingLoanApprovals
                    )
                }
            }
        }
        .padding(.bottom, 32)
        .background(Color.white)
        .clipShape(.rect(topLeadingRadius: 30, topTrailingRadius: 30))
        .padding(.top, selectedTab == .salary ? -36 : -44)
    }

    private var activeLoansForSelectedTab: [AppLoan] {
        switch selectedTab {
        case .loans:
            return active.filter { !$0.isSalaryAdvance }
        case .salary:
            return active.filter(\.isSalaryAdvance)
        }
    }

    private var previousLoansForSelectedTab: [AppLoan] {
        switch selectedTab {
        case .loans:
            return previous.filter { !$0.isSalaryAdvance }
        case .salary:
            return previous.filter(\.isSalaryAdvance)
        }
    }

    private var pendingSalaryApprovals: [AppLoan] {
        pendingApprovals.filter(\.isSalaryAdvance)
    }

    private var pendingLoanApprovals: [AppLoan] {
        pendingApprovals.filter { !$0.isSalaryAdvance }
    }

    @ViewBuilder
    private func loanSections(active: [AppLoan], previous: [AppLoan], approvals: [AppLoan]) -> some View {
        if !approvals.isEmpty {
            loanSectionTitle("Requested Loan Approvals", count: approvals.count)
                .padding(.top, 22)
            LazyVStack(spacing: 12) {
                ForEach(approvals) { loan in
                    SalaryAdvanceRow(
                        loan: loan,
                        isActing: actingLoanId == loan.id,
                        onReject: { Task { await rejectLoanApproval(loan) } },
                        onAccept: { beginLoanApproval(loan) }
                    )
                }
            }
            .padding(.horizontal, 16)
        }

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
            previousLoansTitle
                .padding(.top, 22)
            LazyVStack(spacing: 12) {
                ForEach(previous) { loan in
                    PreviousLoanRow(loan: loan)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func salaryAdvanceSections(active: [AppLoan], previous: [AppLoan], approvals: [AppLoan]) -> some View {
        if !previous.isEmpty {
            advanceSectionTitle("Previous Advances", count: previous.count, showsViewAll: true)
                .padding(.top, 22)
            LazyVStack(spacing: 12) {
                ForEach(previous) { loan in
                    NavigationLink {
                        RepaymentHistoryView(loanId: loan.id, status: loan.status)
                    } label: {
                        AdvanceHistoryRow(loan: loan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }

        let additionalActive = Array(active.dropFirst())
        if !additionalActive.isEmpty {
            advanceSectionTitle("My Advance Requests", count: additionalActive.count)
                .padding(.top, 22)
            LazyVStack(spacing: 12) {
                ForEach(additionalActive) { loan in
                    SalaryAdvanceRow(loan: loan, onCancel: {
                        loanPendingCancel = loan
                    })
                }
            }
            .padding(.horizontal, 16)
        }

        if !approvals.isEmpty {
            advanceSectionTitle("Requested Advances", count: approvals.count)
                .padding(.top, 22)
            LazyVStack(spacing: 12) {
                ForEach(approvals) { loan in
                    SalaryAdvanceRow(
                        loan: loan,
                        isActing: actingLoanId == loan.id,
                        onReject: { Task { await rejectLoanApproval(loan) } },
                        onAccept: { Task { await approveLoanApproval(loan) } }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var previousLoansTitle: some View {
        Text("Previous Loans")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color(hex: 0x101828))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }

    private func advanceSectionTitle(_ title: String, count: Int, showsViewAll: Bool = false) -> some View {
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

    private func cancelLoanDialog(for loan: AppLoan) -> some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.34))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Circle()
                    .fill(Color(hex: 0xEF4444))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "trash")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }

                Text("Are you sure?")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1D2939))
                    .padding(.top, 20)

                Text("This loan request will be cancelled and removed from your visible loan history.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(hex: 0x475467))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 12)

                HStack(spacing: 12) {
                    Button {
                        loanPendingCancel = nil
                    } label: {
                        Text("No, Go Back")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x344054))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCancellingLoan)

                    Button {
                        Task { await cancelLoan(loan) }
                    } label: {
                        Text(isCancellingLoan ? "Cancelling..." : "Confirm")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(hex: 0xEF4444), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isCancellingLoan)
                }
                .padding(.top, 24)
            }
            .padding(24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
        }
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
            Image("LoansEmptyState")
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 148)
                .opacity(0.82)
            Text("No Loans Yet")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(Color(hex: 0x101828))
                .padding(.top, 2)
            Text(errorMessage ?? "Stay organized by creating or joining teams.\nGroups help you manage tasks, track progress,\nand collaborate with your team in one place.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(hex: 0x707070))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 44)
    }

    @MainActor
    private func load() async {
        hydrateCacheIfNeeded()
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
            let approvals = try? await MarketingConvexAPIService.getPendingLoanApprovals(token: token)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                active = page.active
                previous = page.previous
                if let approvals {
                    pendingApprovals = approvals
                }
            }
            if let cacheKey = loansCacheKey {
                LocalCache.put(
                    cacheKey,
                    LoansCacheSnapshot(active: active, previous: previous, pendingApprovals: pendingApprovals)
                )
            }
            errorMessage = nil
        } catch {
            if Self.isCancellation(error) { return }
            if active.isEmpty && previous.isEmpty && pendingApprovals.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var loansCacheKey: String? {
        guard let user = authStore.currentSession?.user else { return nil }
        return "loans.overview.v1.\(user.staffId ?? user._id)"
    }

    @MainActor
    private func hydrateCacheIfNeeded() {
        guard !didHydrateCache else { return }
        didHydrateCache = true
        guard let cacheKey = loansCacheKey,
              let cached = LocalCache.get(cacheKey, as: LoansCacheSnapshot.self) else { return }
        active = cached.active
        previous = cached.previous
        pendingApprovals = cached.pendingApprovals
        hasLoaded = true
    }

    @MainActor
    private func approveLoanApproval(_ loan: AppLoan) async {
        guard actingLoanId == nil, let token = authStore.currentSession?.token else { return }
        actingLoanId = loan.id
        defer { actingLoanId = nil }
        do {
            try await MarketingConvexAPIService.approveLoan(token: token, id: loan.id)
            await load()
        } catch {
            if Self.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func beginLoanApproval(_ loan: AppLoan) {
        let stage = loan.currentStage?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !loan.isSalaryAdvance && stage == "nominee_pending" {
            signatureApprovalLoan = loan
        } else {
            Task { await approveLoanApproval(loan) }
        }
    }

    @MainActor
    private func rejectLoanApproval(_ loan: AppLoan) async {
        guard actingLoanId == nil, let token = authStore.currentSession?.token else { return }
        actingLoanId = loan.id
        defer { actingLoanId = nil }
        do {
            try await MarketingConvexAPIService.rejectLoan(token: token, id: loan.id)
            await load()
        } catch {
            if Self.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as NSError).code == NSURLErrorCancelled
    }

    @MainActor
    private func cancelLoan(_ loan: AppLoan) async {
        guard !isCancellingLoan, let token = authStore.currentSession?.token else { return }
        isCancellingLoan = true
        defer {
            isCancellingLoan = false
            loanPendingCancel = nil
        }
        do {
            try await MarketingConvexAPIService.cancelLoan(token: token, id: loan.id)
            await load()
        } catch {
            if Self.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct LoanSignatureApprovalSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let loan: AppLoan
    let onApproved: () async -> Void

    @State private var savedSignature: StaffDigitalSign?
    @State private var isLoadingSignature = false
    @State private var isSubmitting = false
    @State private var showingSignaturePad = false
    @State private var errorMessage: String?

    private var savedStorageId: String? {
        guard savedSignature?.hasSignature == true else { return nil }
        return savedSignature?.storageId?.nonBlank
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(loan.requesterName?.nonBlank ?? loan.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("\(loan.loanId.isEmpty ? "Loan request" : loan.loanId) · \(AppModuleFormatters.rupees(loan.principal))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Text("Your signature confirms your approval as the nominated guarantor.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    if isLoadingSignature {
                        ProgressView("Checking saved signature...")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if let storageId = savedStorageId {
                        savedSignaturePreview(storageId: storageId)

                        Button {
                            Task { await approve(using: storageId) }
                        } label: {
                            actionLabel("Approve with Saved Signature", showsProgress: isSubmitting)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                    } else {
                        ContentUnavailableView(
                            "Signature Required",
                            systemImage: "signature",
                            description: Text("Draw your signature to approve this loan request.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    }

                    Button {
                        showingSignaturePad = true
                    } label: {
                        Label(savedStorageId == nil ? "Draw Signature" : "Replace Signature", systemImage: "pencil.and.scribble")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSubmitting || isLoadingSignature)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xB42318))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Approve Loan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .task { await loadSavedSignature() }
            .sheet(isPresented: $showingSignaturePad) {
                SignatureCaptureView(title: "Loan Signature") { data in
                    Task { await uploadAndApprove(signatureData: data) }
                }
                .interactiveDismissDisabled(isSubmitting)
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func savedSignaturePreview(storageId: String) -> some View {
        Group {
            if let signature = savedSignature,
               let url = MarketingConvexAPIService.digitalSignPreviewURL(signature) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        signaturePlaceholder
                    default:
                        ProgressView()
                    }
                }
            } else {
                signaturePlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appSeparator, lineWidth: 1))
        .accessibilityLabel("Saved signature")
    }

    private var signaturePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "signature")
                .font(.system(size: 32))
            Text("Saved signature available")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.secondary)
    }

    private func actionLabel(_ title: String, showsProgress: Bool) -> some View {
        ZStack {
            Text(title).opacity(showsProgress ? 0 : 1)
            if showsProgress { ProgressView().tint(.white) }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Color(hex: 0x16A34A), in: RoundedRectangle(cornerRadius: 10))
    }

    @MainActor
    private func loadSavedSignature() async {
        guard !isLoadingSignature,
              let token = authStore.currentSession?.token else { return }
        isLoadingSignature = true
        defer { isLoadingSignature = false }
        do {
            savedSignature = try await MarketingConvexAPIService.getDigitalSign(token: token)
        } catch {
            savedSignature = nil
            errorMessage = "A saved signature could not be loaded. Draw a new signature to continue."
        }
    }

    @MainActor
    private func uploadAndApprove(signatureData: Data) async {
        guard let token = authStore.currentSession?.token else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let storageId = try await PostSalesStorageService.uploadData(
                token: token,
                data: signatureData,
                mimeType: "image/png"
            )
            try? await MarketingConvexAPIService.saveDigitalSign(
                token: token,
                storageId: storageId,
                fileName: "signature.png"
            )
            try await finishApproval(token: token, storageId: storageId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func approve(using storageId: String) async {
        guard let token = authStore.currentSession?.token else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await finishApproval(token: token, storageId: storageId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func finishApproval(token: String, storageId: String) async throws {
        try await MarketingConvexAPIService.approveLoan(
            token: token,
            id: loan.id,
            eSignatureId: storageId
        )
        await onApproved()
        dismiss()
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

private enum LoanNomineePickerTarget: String, Identifiable {
    case nominee1
    case nominee2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nominee1: return "Select Nominee 1"
        case .nominee2: return "Select Nominee 2"
        }
    }
}

private enum LoanDatePickerTarget: String, Identifiable {
    case disbursed
    case repaymentStart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disbursed: return "Select Disbursed Date"
        case .repaymentStart: return "Select Repayment Start Month"
        }
    }
}

private struct LoanNomineePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let staff: [ConvexStaffListItem]
    let selectedId: String?
    let onSelect: (ConvexStaffListItem) -> Void

    @State private var searchText = ""

    private var filteredStaff: [ConvexStaffListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return staff }
        return staff.filter { item in
            [
                item.displayName,
                item.employeeId ?? "",
                item.designation ?? "",
                item.department ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text("Search and choose staff")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x667085))
                        .frame(width: 34, height: 34)
                        .background(Color(hex: 0xF2F4F7), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 14)

            NativeInlineSearchBar(text: $searchText, placeholder: "Search nominee")
            .frame(height: 48)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if filteredStaff.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                    Text("No staff found")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x344054))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredStaff) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(item.initials.isEmpty ? "?" : item.initials)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color(hex: 0x0B61CA))
                                        .frame(width: 38, height: 38)
                                        .background(Color(hex: 0xEAF3FF), in: Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.displayName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Color(hex: 0x101828))
                                            .lineLimit(1)
                                        Text([item.employeeId, item.designation, item.department]
                                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                            .filter { !$0.isEmpty }
                                            .joined(separator: " · "))
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(Color(hex: 0x667085))
                                            .lineLimit(1)
                                    }

                                    Spacer()
                                    if selectedId == item.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color(hex: 0x0B61CA))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 66)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
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
    @State private var nomineePickerTarget: LoanNomineePickerTarget?
    @State private var datePickerTarget: LoanDatePickerTarget?

    private let interestOptions = ["Flat", "Reducing"]
    private let documentOptions = ["Aadhaar Card", "PAN Card", "Salary Slip", "Bond Certificate", "Other"]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Request Loan")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .padding(.bottom, 10)
                    Text("Information about Loans")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
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

                    dateInputField(
                        title: "Disbursed Date *",
                        value: dayDisplayFormatter.string(from: disbursedDate),
                        target: .disbursed
                    )
                    dateInputField(
                        title: "Repayment Start Month *",
                        value: monthDisplayFormatter.string(from: repaymentStartMonth),
                        target: .repaymentStart
                    )

                    loanTextField(title: "Tenure (Months) *", placeholder: "Maximum 6", icon: "clock", text: $tenure, keyboard: .numberPad)
                        .onChange(of: tenure) { _, newValue in
                            let digits = newValue.filter(\.isNumber)
                            guard let months = Int(digits), months > 0 else {
                                if tenure != digits { tenure = digits }
                                return
                            }
                            let capped = String(min(months, 6))
                            if tenure != capped {
                                tenure = capped
                            }
                        }

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
                .padding(.horizontal, 20)
                .padding(.bottom, 104)
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
                .padding(.top, 14)
                .padding(.bottom, 20)
                .background(Color.white)
            }
        }
        .appCompactSheetCTAContainer()
        .task { await loadStaff() }
        .sheet(item: $nomineePickerTarget) { target in
            LoanNomineePickerSheet(
                title: target.title,
                staff: availableNominees,
                selectedId: selectedNominee(for: target)?.id
            ) { item in
                setNominee(item, for: target)
                nomineePickerTarget = nil
            }
            .appLibraryNativeSheet([.height(520), .large])
        }
        .sheet(item: $datePickerTarget) { target in
            LoanDatePickerSheet(
                title: target.title,
                selection: dateBinding(for: target)
            )
            .appLibraryNativeSheet([.height(360)])
        }
    }

    private func nomineeMenuField(title: String, selection: Binding<ConvexStaffListItem?>) -> some View {
        let target: LoanNomineePickerTarget = title.contains("1") ? .nominee1 : .nominee2
        return Button {
            nomineePickerTarget = target
        } label: {
            inputShell(title: title, icon: "person.crop.circle", trailingChevron: true) {
                Text(selection.wrappedValue?.displayName ?? "Select Nominee")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(selection.wrappedValue == nil ? Color(hex: 0x98A2B3) : Color(hex: 0x101828))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var availableNominees: [ConvexStaffListItem] {
        staff.filter { $0.id != selectedStaff?.id }
    }

    private func selectedNominee(for target: LoanNomineePickerTarget) -> ConvexStaffListItem? {
        switch target {
        case .nominee1: return selectedNominee1
        case .nominee2: return selectedNominee2
        }
    }

    private func setNominee(_ item: ConvexStaffListItem, for target: LoanNomineePickerTarget) {
        switch target {
        case .nominee1:
            selectedNominee1 = item
        case .nominee2:
            selectedNominee2 = item
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

    private func dateInputField(title: String, value: String, target: LoanDatePickerTarget) -> some View {
        Button {
            datePickerTarget = target
        } label: {
            inputShell(title: title, icon: "calendar", trailingChevron: false) {
                Text(value)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(hex: 0x101828))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 24, height: 24)
                    .background(Color(hex: 0xEAF3FF), in: Circle())
            }
        }
        .buttonStyle(.plain)
    }

    private func dateBinding(for target: LoanDatePickerTarget) -> Binding<Date> {
        switch target {
        case .disbursed:
            return $disbursedDate
        case .repaymentStart:
            return $repaymentStartMonth
        }
    }

    private var dayDisplayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }

    private var monthDisplayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }
}

private struct LoanDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var selection: Date

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text("Choose a date")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 8)

            DatePicker("", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

private extension LoanRequestSheet {
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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Request Advance")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .padding(.bottom, 10)
                    Text("Information about Salary Advance")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
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
                .padding(.horizontal, 20)
                .padding(.bottom, 104)
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
                    .background(LinearGradient(colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 20)
                .background(Color.white)
            }
        }
        .appCompactSheetCTAContainer()
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
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: loanIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(loan.status == .pending ? Color(hex: 0x12B76A) : Color(hex: 0x0B61CA))
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0xEEF4FF), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text(loan.status == .pending ? (loan.loanId.isEmpty ? "—" : loan.loanId) : "Loan ID: \(loan.loanId.isEmpty ? "—" : loan.loanId)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                VStack(spacing: 8) {
                    Text(statusBadgeText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(loan.status == .pending ? Color(hex: 0xF79009) : Color(hex: 0x0B61CA))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background((loan.status == .pending ? Color(hex: 0xFFF4E5) : Color(hex: 0xEAF3FF)), in: Capsule())

                    if loan.status == .pending, let onCancel {
                        Button(action: onCancel) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xEF4444))
                                .frame(width: 34, height: 34)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color(hex: 0xFCA5A5), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if loan.status == .pending || loan.isSalaryAdvance {
                DashedDivider()
                    .padding(.top, 2)

                LoanApprovalTracker(loan: loan)
                    .padding(.top, 4)
            } else {
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
                        Text("Next EMI Due")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color(hex: 0x6B7280))
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x0B61CA))
                            Text(nextEmiDisplay)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x0B61CA))
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, loan.status == .pending ? 12 : 16)
        .background(Color.white)
    }

    private var loanIcon: String {
        if loan.isSalaryAdvance {
            return "indianrupeesign"
        }
        switch loan.type {
        case .education: return "graduationcap.fill"
        case .home: return "house.fill"
        case .other: return "indianrupeesign"
        }
    }

    private var displayTitle: String {
        guard loan.isSalaryAdvance else { return loan.title }
        let title = loan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.lowercased() == "loan" {
            return "Salary Advance"
        }
        return title
    }

    private var statusBadgeText: String {
        if loan.isSalaryAdvance {
            return loan.status == .pending ? "Pending Advance" : "Active Advance"
        }
        return loan.status == .pending ? "Pending" : "Active Loan"
    }

    private var nextEmiDisplay: String {
        if loan.status == .pending {
            return loan.nextEmiAmount > 0 ? AppModuleFormatters.rupees(loan.nextEmiAmount) : "—"
        }
        return loan.nextEmiDueDate.map(AppModuleFormatters.day.string) ?? "—"
    }
}

private struct AdvanceHeroCard: View {
    let loan: AppLoan
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                advanceIcon
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)
                    Text(loan.loanId.isEmpty ? "—" : loan.loanId)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(loan.status == .pending ? "Pending Advance" : "Active Advance")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(loan.status == .pending ? Color(hex: 0xF79009) : Color(hex: 0x0B61CA))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(loan.status == .pending ? Color(hex: 0xFFF4E5) : Color(hex: 0xEAF3FF), in: Capsule())

                    if loan.status == .pending, let onCancel {
                        Button(action: onCancel) {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xEF4444))
                                .frame(width: 34, height: 34)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color(hex: 0xFCA5A5), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            DashedDivider()
                .padding(.top, 2)

            AdvanceTrackerPills(loan: loan)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.white)
    }

    private var advanceIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0xEEF4FF))
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x12B76A))
                .offset(x: -2, y: -2)
            Image(systemName: "circle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .offset(x: 7, y: 8)
        }
    }

    private var displayTitle: String {
        let title = loan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.lowercased() == "loan" || title.lowercased() == "salary advance" {
            return title.isEmpty || title.lowercased() == "loan" ? "Salary Advance" : title
        }
        return title
    }
}

private struct AdvanceTrackerPills: View {
    let loan: AppLoan

    var body: some View {
        HStack(spacing: 8) {
            step(title: "HR", icon: "person.3", isDone: hrDone)

            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
                .overlay {
                    GeometryReader { proxy in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0.5))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
                        }
                        .stroke(Color(hex: 0x1BCB0B), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    }
                }

            step(title: "Acc's", icon: "apps.iphone", isDone: accountsDone)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
    }

    private func step(title: String, icon: String, isDone: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isDone ? "checkmark" : icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(isDone ? Color(hex: 0x1BCB0B) : Color(hex: 0x98A2B3))
        .frame(width: 88, height: 30)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isDone ? Color(hex: 0x1BCB0B) : Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private var stageRank: Int {
        let stage = loan.currentStage?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch stage {
        case "hr_pending": return 3
        case "accountant_pending", "accounts_pending": return 4
        case "disbursed", "completed", "active", "approved": return 5
        default:
            return loan.status == .active ? 5 : -1
        }
    }

    private var hrDone: Bool { stageRank >= 4 }
    private var accountsDone: Bool { stageRank >= 5 }
}

private struct LoanApprovalTracker: View {
    @Environment(AuthStore.self) private var authStore
    let loan: AppLoan
    @State private var workflowSteps: [MarketingConvexAPIService.LoanWorkflowStep] = []

    private var steps: [LoanApprovalStep] {
        if !workflowSteps.isEmpty {
            return workflowSteps.map { step in
                let status = step.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let title = step.name
                    ?? step.approverDesignation
                    ?? step.approverRole
                    ?? "Step \(step.stepOrder ?? 0)"
                return LoanApprovalStep(
                    title: title.uppercased(),
                    icon: workflowIcon(for: step.approverType),
                    isDone: status == "approved" || status == "skipped",
                    name: step.actedByName ?? step.resolvedStaffName
                )
            }
        }
        if loan.isSalaryAdvance {
            return [
                .init(title: "HR", icon: "person.3.fill", isDone: stageRank >= 4, name: loan.hrName),
                .init(title: "ACC'S", icon: "apps.iphone", isDone: stageRank >= 5, name: loan.accountantName)
            ]
        }

        return [
            .init(title: "NOMINEE 1", icon: "shield", isDone: stageRank >= 1 || statusDone(loan.nominee1Status), name: loan.nominee1Name),
            .init(title: "NOMINEE 2", icon: "shield", isDone: stageRank >= 1 || statusDone(loan.nominee2Status), name: loan.nominee2Name),
            .init(title: "GM", icon: "person.badge.clock", isDone: stageRank >= 2, name: loan.gmName),
            .init(title: "AVP", icon: "person.crop.circle.badge.checkmark", isDone: stageRank >= 3, name: loan.avpName),
            .init(title: "HR", icon: "person.3", isDone: stageRank >= 4, name: loan.hrName),
            .init(title: "ACC'S", icon: "apps.iphone", isDone: false, name: loan.accountantName)
        ]
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                ZStack {
                    Rectangle()
                        .fill(Color(hex: 0xE4EAF2))
                        .frame(height: 2)
                        .padding(.horizontal, 24)
                        .offset(y: -16)

                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(steps) { step in
                            VStack(spacing: 7) {
                                Image(systemName: step.isDone ? "checkmark" : step.icon)
                                    .font(.system(size: step.isDone ? 14 : 17, weight: .semibold))
                                    .foregroundStyle(step.isDone ? Color(hex: 0x0B61CA) : Color(hex: 0x98A2B3))
                                    .frame(width: 43, height: 43)
                                    .background(Color(hex: step.isDone ? 0xEAF3FF : 0xEEF4FF), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                                Text(step.title)
                                    .font(.system(size: 8, weight: step.isDone ? .bold : .semibold))
                                    .foregroundStyle(step.isDone ? Color(hex: 0x0B61CA) : Color(hex: 0x98A2B3))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.55)

                                if let name = step.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                                    Text(shortName(name))
                                        .font(.system(size: 7, weight: .medium))
                                        .foregroundStyle(Color(hex: 0x667085))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                }
                            }
                            .frame(width: 72)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
        .task(id: loan.id) {
            guard loan.status == .pending,
                  let token = authStore.currentSession?.token else { return }
            workflowSteps = (try? await MarketingConvexAPIService.getLoanWorkflow(
                token: token,
                loanId: loan.id
            )) ?? []
        }
    }

    private var stageRank: Int {
        let stage = loan.currentStage?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch stage {
        case "nominee_pending": return 0
        case "gm_pending": return 1
        case "avp_pending": return 2
        case "hr_pending": return 3
        case "accountant_pending", "accounts_pending": return 4
        case "disbursed", "completed", "active", "approved": return 5
        default:
            return loan.status == .active ? 5 : -1
        }
    }

    private func statusDone(_ value: String?) -> Bool {
        value?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == "approved"
    }

    private func workflowIcon(for approverType: String?) -> String {
        switch approverType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "role": return "person.3"
        case "designation": return "person.badge.shield.checkmark"
        case "reporting_manager", "manager": return "person.crop.circle.badge.checkmark"
        default: return "person.badge.clock"
        }
    }

    private func shortName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { return trimmed }
        return String(trimmed.prefix(9)) + "…"
    }
}

private struct LoanApprovalStep: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let isDone: Bool
    let name: String?
}

private struct DashedDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0.5))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
                    }
                    .stroke(Color(hex: 0xE5E7EB), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
    }
}

private struct SalaryAdvanceRow: View {
    let loan: AppLoan
    var onCancel: (() -> Void)?
    var isActing = false
    var onReject: (() -> Void)?
    var onAccept: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                advanceIcon
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)
                    Text(loan.loanId.isEmpty ? "Salary Advance Request" : loan.loanId)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineLimit(1)
                }

                Spacer()

                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(statusBackground, in: Capsule())

                if let onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xEF4444))
                            .frame(width: 34, height: 34)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color(hex: 0xFCA5A5), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .overlay(Color(hex: 0xF2F4F7))

            HStack(spacing: 0) {
                metricColumn("Principal", AppModuleFormatters.rupees(loan.principal))
                Rectangle()
                    .fill(Color(hex: 0xE4E7EC))
                    .frame(width: 1, height: 32)
                    .padding(.horizontal, 8)
                metricColumn("Disbursed", disbursedDisplay)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let requesterName {
                HStack(spacing: 8) {
                    Spacer()
                    Text("By")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x344054))
                    Text(requesterInitial)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: 0x667085))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: 0xF2F4F7), in: Circle())
                    Text(requesterName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            if onAccept != nil || onReject != nil {
                HStack(spacing: 12) {
                    Button {
                        onReject?()
                    } label: {
                        Label("Reject", systemImage: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xD92D20))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color(hex: 0xEF4444), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isActing)

                    Button {
                        onAccept?()
                    } label: {
                        Label(isActing ? "Working..." : "Accept", systemImage: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: 0x1BCB0B), Color(hex: 0x25A500)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isActing)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private func metricColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var advanceIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: 0xEEF4FF))
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x12B76A))
                .offset(x: -2, y: -2)
            Image(systemName: "circle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .offset(x: 7, y: 8)
        }
    }

    private var displayTitle: String {
        let title = loan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if loan.isSalaryAdvance && (title.isEmpty || title.lowercased() == "loan") {
            return "Salary Advance"
        }
        if title.isEmpty || title.lowercased() == "loan" { return "Loan Request" }
        return title
    }

    private var requesterName: String? {
        loan.requesterName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForLoan
            ?? loan.requesterEmployeeId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForLoan
    }

    private var requesterInitial: String {
        String((requesterName ?? "?").prefix(1)).uppercased()
    }

    private var disbursedDisplay: String {
        loan.disbursedDate.map(AppModuleFormatters.ymd.string) ?? "—"
    }

    private var statusText: String {
        let raw = loan.rawStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw == "cancelled" || raw == "canceled" { return "• CANCELLED" }
        if raw == "rejected" { return "• REJECTED" }
        if onAccept != nil || onReject != nil { return "• REQUESTED" }
        if loan.status == .pending { return "Pending Advance" }
        if loan.status == .active { return "Approved" }
        return "• REPAID"
    }

    private var statusColor: Color {
        switch statusText {
        case "Pending Advance": return Color(hex: 0xF79009)
        case "Approved": return Color(hex: 0x12B76A)
        case "• REQUESTED": return Color(hex: 0x12B76A)
        case "• CANCELLED": return Color(hex: 0x475467)
        case "• REJECTED": return Color(hex: 0xB42318)
        default: return Color(hex: 0x12B76A)
        }
    }

    private var statusBackground: Color {
        switch statusText {
        case "Pending Advance": return Color(hex: 0xFFF4E5)
        case "Approved", "• REPAID", "• REQUESTED": return Color(hex: 0xECFDF3)
        case "• REJECTED": return Color(hex: 0xFEF3F2)
        default: return Color(hex: 0xE7F8F0)
        }
    }
}

private struct AdvanceHistoryRow: View {
    let loan: AppLoan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                advanceIcon
                    .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)
                    Text(loan.loanId.isEmpty ? "—" : loan.loanId)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineLimit(1)
                }

                Spacer()

                Text("• \(statusText)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusBackground, in: Capsule())
            }

            HStack(spacing: 0) {
                metricColumn("Advance", AppModuleFormatters.rupees(loan.principal))
                Rectangle()
                    .fill(Color(hex: 0xE4E7EC))
                    .frame(width: 1, height: 30)
                    .padding(.horizontal, 8)
                metricColumn("Disbursed", loan.disbursedDate.map(AppModuleFormatters.day.string) ?? "—", alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Label("View Repayment History", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color(hex: 0x0B61CA), in: Capsule())
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private func metricColumn(_ title: String, _ value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    private var advanceIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0xEEF4FF))
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x12B76A))
                .offset(x: -2, y: -2)
            Image(systemName: "circle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .offset(x: 7, y: 8)
        }
    }

    private var displayTitle: String {
        let title = loan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.lowercased() == "loan" {
            return "Medical Expenses"
        }
        return title
    }

    private var statusText: String {
        let raw = loan.rawStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw == "cancelled" || raw == "canceled" { return "CANCELLED" }
        if raw == "rejected" { return "REJECTED" }
        return "REPAID"
    }

    private var statusColor: Color {
        switch statusText {
        case "REJECTED": return Color(hex: 0xB42318)
        case "CANCELLED": return Color(hex: 0x475467)
        default: return Color(hex: 0x12B76A)
        }
    }

    private var statusBackground: Color {
        switch statusText {
        case "REJECTED": return Color(hex: 0xFEF3F2)
        case "CANCELLED": return Color(hex: 0xE7F8F0)
        default: return Color(hex: 0xECFDF3)
        }
    }
}

private struct PreviousLoanRow: View {
    let loan: AppLoan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: 0xEEF4FF))
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x12B76A))
                        .offset(x: -2, y: -2)
                    Image(systemName: "circle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .offset(x: 7, y: 8)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(loan.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text(loan.loanId.isEmpty ? "—" : loan.loanId)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                Text("• \(statusText)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(statusBackground, in: Capsule())
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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        }
    }

    private func metricColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        let raw = loan.rawStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw == "cancelled" || raw == "canceled" { return "CANCELLED" }
        if raw == "rejected" { return "REJECTED" }
        if raw == "paid" || raw == "repaid" || raw == "closed" { return "REPAID" }
        return loan.status == .repaid ? "REPAID" : loan.status.rawValue.uppercased()
    }

    private var statusColor: Color {
        switch statusText {
        case "CANCELLED": return Color(hex: 0x475467)
        case "REJECTED": return Color(hex: 0xB42318)
        default: return Color(hex: 0x12B76A)
        }
    }

    private var statusBackground: Color {
        switch statusText {
        case "CANCELLED": return Color(hex: 0xE7F8F0)
        case "REJECTED": return Color(hex: 0xFEF3F2)
        default: return Color(hex: 0xECFDF3)
        }
    }
}

struct RepaymentHistoryView: View {
    @Environment(AuthStore.self) private var authStore
    let loanId: String
    let status: AppLoanStatus

    @State private var repayments: [AppRepayment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didHydrateCache = false

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
        hydrateCacheIfNeeded()
        isLoading = true
        defer { isLoading = false }
        do {
            async let detailRequest = MarketingConvexAPIService.getLoanDetail(
                token: token,
                id: loanId,
                mappedStatus: status
            )
            async let freshRequest: [ConvexLoanRepaymentData]? = try? MarketingConvexAPIService.getLoanRepayments(
                token: token,
                loanId: loanId
            )
            let loan = try await detailRequest
            let freshPaid = AppLoanMapper.mapRepayments(await freshRequest ?? [])
            let merged = freshPaid.isEmpty
                ? loan.repayments
                : freshPaid + loan.repayments.filter { $0.status != .paid }
            repayments = merged.sorted {
                ($0.dueDate ?? .distantPast) > ($1.dueDate ?? .distantPast)
            }
            if let cacheKey = repaymentsCacheKey {
                LocalCache.put(cacheKey, repayments)
            }
            errorMessage = nil
        } catch {
            if repayments.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var repaymentsCacheKey: String? {
        guard let user = authStore.currentSession?.user else { return nil }
        return "loans.repayments.v1.\(user.staffId ?? user._id).\(loanId)"
    }

    @MainActor
    private func hydrateCacheIfNeeded() {
        guard !didHydrateCache else { return }
        didHydrateCache = true
        guard let cacheKey = repaymentsCacheKey,
              let cached = LocalCache.get(cacheKey, as: [AppRepayment].self) else { return }
        repayments = cached
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
