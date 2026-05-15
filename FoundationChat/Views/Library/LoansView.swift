import SwiftUI

struct LoansView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var active: [AppLoan] = []
    @State private var previous: [AppLoan] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var heroLoan: AppLoan? { active.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                if isLoading && !hasLoaded {
                    AppModuleLoadingRows()
                } else if active.isEmpty && previous.isEmpty {
                    ContentUnavailableView(
                        "No Loans",
                        systemImage: "indianrupeesign.circle",
                        description: Text(errorMessage ?? "Your active and previous loans will appear here.")
                    )
                    .padding(.top, 60)
                } else {
                    if let heroLoan {
                        NavigationLink {
                            RepaymentHistoryView(loanId: heroLoan.id, status: heroLoan.status)
                        } label: {
                            LoanHeroCard(loan: heroLoan)
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if !previous.isEmpty {
                        HStack {
                            Text("Previous Loans")
                                .font(AppModuleFont.rowTitle)
                            Spacer()
                            Text("\(previous.count)")
                                .font(AppModuleFont.rowMetaSemibold)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

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
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Loans")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
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
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x02499D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Loans")
                    .font(AppModuleFont.screenTitle)
                    .foregroundStyle(.white)
                Text("Track your outstanding balance and EMI timeline")
                    .font(AppModuleFont.rowBody)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(22)
        }
        .frame(height: 170)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
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
            errorMessage = error.localizedDescription
        }
    }
}

private struct LoanHeroCard: View {
    let loan: AppLoan

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: loan.type == .education ? "graduationcap.fill" : "house.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(loan.title)
                        .font(AppModuleFont.rowTitle)
                        .foregroundStyle(.white)
                    Text(loan.loanId.isEmpty ? "—" : loan.loanId)
                        .font(AppModuleFont.rowMeta)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                AppModuleBadge(
                    text: loan.status == .pending ? "Pending" : "Active Loan",
                    tint: loan.status == .pending ? .orange : .blue
                )
                .background(.white, in: Capsule())
            }

            HStack(spacing: 14) {
                metric("Outstanding", AppModuleFormatters.rupees(loan.outstandingBalance))
                metric("Next EMI", loan.nextEmiDueDate.map(AppModuleFormatters.day.string) ?? "—")
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x1849A9), Color(hex: 0x0B61CA)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .padding(.horizontal)
        .shadow(color: Color(hex: 0x0B61CA).opacity(0.18), radius: 14, y: 8)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppModuleFont.rowMeta)
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(AppModuleFont.rowTitle)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
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
