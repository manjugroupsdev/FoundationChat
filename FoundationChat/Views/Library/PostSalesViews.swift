import SwiftUI
import UniformTypeIdentifiers

struct CollectionsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var collections: [CustomerCollectionRow] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showingSubmitSheet = false
    @State private var rectifyingCollection: CustomerCollectionRow?
    @State private var selectedFilter: CollectionPaymentFilter = .all
    @State private var searchText = ""
    @State private var previewURL: URL?

    private var visibleCollections: [CustomerCollectionRow] {
        filterCollections(collections, filter: selectedFilter, searchText: searchText)
    }

    private var summary: CollectionSummary {
        CollectionSummary(rows: visibleCollections)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                FleetHeader(
                    title: "Collections",
                    subtitle: "Customer payment entries and verification status",
                    systemImage: "creditcard.fill"
                )
                CollectionControls(filter: $selectedFilter, summary: summary)
                    .padding(.horizontal, 16)
                    .padding(.top, -34)
                    .padding(.bottom, 12)
                content
            }
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search collections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSubmitSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Collection")
            }
        }
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .sheet(isPresented: $showingSubmitSheet) {
            CollectionSubmitSheet(rectifyingCollection: nil) {
                await load()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $rectifyingCollection) { collection in
            CollectionSubmitSheet(rectifyingCollection: collection) {
                await load()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(get: { previewURL.map(URLPreviewItem.init(url:)) }, set: { if $0 == nil { previewURL = nil } })) { item in
            StoragePreviewSheet(url: item.url)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Collections", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            if isLoading && !hasLoaded {
                AppModuleLoadingRows()
            } else if visibleCollections.isEmpty {
                ContentUnavailableView(
                    "No Collections",
                    systemImage: "creditcard",
                    description: Text("Submitted collections will appear here.")
                )
                .padding(.vertical, 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(visibleCollections) { collection in
                        CollectionRowCard(
                            collection: collection,
                            onProof: { await openProof(collection) },
                            onRectify: collection.isRejected ? { rectifyingCollection = collection } : nil
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            hasLoaded = true
            return
        }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            collections = try await PostSalesConvexAPIService.listMyCollections(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func openProof(_ collection: CustomerCollectionRow) async {
        guard let token = authStore.currentSession?.token,
              let storageId = collection.proofStorageId?.nonBlank
        else { return }
        do {
            previewURL = try await PostSalesStorageService.getFileURL(token: token, storageId: storageId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AccountsCollectionsReviewView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var collections: [CustomerCollectionRow] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var selectedForReject: CustomerCollectionRow?
    @State private var rejectRemarks = ""
    @State private var selectedFilter: CollectionPaymentFilter = .all
    @State private var searchText = ""
    @State private var previewURL: URL?

    private var visibleCollections: [CustomerCollectionRow] {
        filterCollections(collections, filter: selectedFilter, searchText: searchText)
    }

    private var summary: CollectionSummary {
        CollectionSummary(rows: visibleCollections)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                FleetHeader(
                    title: "Post Sales Verification",
                    subtitle: "Account verification for customer collections",
                    systemImage: "checkmark.seal.fill"
                )
                CollectionControls(filter: $selectedFilter, summary: summary)
                    .padding(.horizontal, 16)
                    .padding(.top, -34)
                    .padding(.bottom, 12)
                content
            }
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Post Sales Verification")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search pending collections")
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .alert("Accounts", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $selectedForReject) { collection in
            RejectCollectionSheet(remarks: $rejectRemarks) {
                await reject(collection)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(get: { previewURL.map(URLPreviewItem.init(url:)) }, set: { if $0 == nil { previewURL = nil } })) { item in
            StoragePreviewSheet(url: item.url)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            if isLoading && !hasLoaded {
                AppModuleLoadingRows()
            } else if visibleCollections.isEmpty {
                ContentUnavailableView(
                    "No Pending Collections",
                    systemImage: "checkmark.seal",
                    description: Text("Collections waiting for account verification will appear here.")
                )
                .padding(.vertical, 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(visibleCollections) { collection in
                        VStack(spacing: 12) {
                            CollectionRowCard(collection: collection) {
                                await openProof(collection)
                            }
                            HStack(spacing: 10) {
                                Button {
                                    Task { await approve(collection) }
                                } label: {
                                    Label("Approve", systemImage: "checkmark.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: 0x16A34A))

                                Button {
                                    rejectRemarks = ""
                                    selectedForReject = collection
                                } label: {
                                    Label("Reject", systemImage: "xmark.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(Color(hex: 0xB42318))
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                        }
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            hasLoaded = true
            return
        }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            collections = try await PostSalesConvexAPIService.listCollectionsForAccounts(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func approve(_ collection: CustomerCollectionRow) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            _ = try await PostSalesConvexAPIService.approveCollection(token: token, collectionId: collection.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reject(_ collection: CustomerCollectionRow) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            _ = try await PostSalesConvexAPIService.rejectCollection(token: token, collectionId: collection.id, remarks: rejectRemarks)
            selectedForReject = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func openProof(_ collection: CustomerCollectionRow) async {
        guard let token = authStore.currentSession?.token,
              let storageId = collection.proofStorageId?.nonBlank
        else { return }
        do {
            previewURL = try await PostSalesStorageService.getFileURL(token: token, storageId: storageId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LoanDeskView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var selectedMode: LoanDeskMode = .sales
    @State private var cases: [LoanCaseRow] = []
    @State private var legalStaff: [LegalStaffRow] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var assigningCase: LoanCaseRow?
    @State private var selectedStaffId = ""
    @State private var rejectingCase: LoanCaseRow?
    @State private var rejectRemarks = ""
    @State private var showingSubmitSheet = false
    @State private var searchText = ""

    private var visibleCases: [LoanCaseRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return cases }
        return cases.filter { loanCase in
            [
                loanCase.name,
                loanCase.phone,
                loanCase.bookingRefNo,
                loanCase.projectName,
                loanCase.plotNo,
                loanCase.statusLabel,
                loanCase.legalAssignedName
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    private var availableModes: [LoanDeskMode] {
        guard authStore.currentSession?.user.isAdmin != true else { return LoanDeskMode.allCases }
        return [resolvedMode]
    }

    private var resolvedMode: LoanDeskMode {
        LoanDeskMode(user: authStore.currentSession?.user)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                FleetHeader(
                    title: "Loan Desk",
                    subtitle: "Sales handoff and legal verification workflow",
                    systemImage: "doc.text.magnifyingglass"
                )
                if availableModes.count > 1 {
                    Picker("Loan desk mode", selection: $selectedMode) {
                        ForEach(availableModes) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, -34)
                    .padding(.bottom, 14)
                    .onChange(of: selectedMode) { _, _ in
                        Task { await load() }
                    }
                } else {
                    LoanModeBanner(mode: selectedMode)
                        .padding(.horizontal, 16)
                        .padding(.top, -34)
                        .padding(.bottom, 14)
                }
                content
            }
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Loan Desk")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search loan cases")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedMode == .sales {
                    Button {
                        showingSubmitSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Submit Loan")
                }
            }
        }
        .refreshable { await load() }
        .task {
            if !hasLoaded {
                selectedMode = resolvedMode
                await load()
            }
        }
        .alert("Loan Desk", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $assigningCase) { loanCase in
            AssignLoanSheet(staff: legalStaff, selectedStaffId: $selectedStaffId) {
                await assign(loanCase)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $rejectingCase) { loanCase in
            RejectCollectionSheet(title: "Reject Loan", remarks: $rejectRemarks) {
                await reject(loanCase)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSubmitSheet) {
            SubmitLoanCaseSheet {
                await load()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            if isLoading && !hasLoaded {
                AppModuleLoadingRows()
            } else if visibleCases.isEmpty {
                ContentUnavailableView(
                    "No Loan Cases",
                    systemImage: "doc.text",
                    description: Text("Cases for this workflow stage will appear here.")
                )
                .padding(.vertical, 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(visibleCases) { loanCase in
                        LoanDeskCaseCard(
                            loanCase: loanCase,
                            mode: selectedMode,
                            onAssign: {
                                selectedStaffId = legalStaff.first?.id ?? ""
                                assigningCase = loanCase
                            },
                            onAccept: {
                                Task { await accept(loanCase) }
                            },
                            onReject: {
                                rejectRemarks = ""
                                rejectingCase = loanCase
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            hasLoaded = true
            return
        }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            switch selectedMode {
            case .sales:
                cases = try await PostSalesConvexAPIService.listLoanDeskForSales(token: token)
                legalStaff = try await PostSalesConvexAPIService.listLegalStaff(token: token)
            case .legalTeam:
                cases = try await PostSalesConvexAPIService.listLoanDeskForLegalTeam(token: token)
            case .legalManager:
                cases = try await PostSalesConvexAPIService.listLoanDeskForLegalManager(token: token)
                legalStaff = try await PostSalesConvexAPIService.listLegalStaff(token: token)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func assign(_ loanCase: LoanCaseRow) async {
        guard let token = authStore.currentSession?.token,
              let staff = legalStaff.first(where: { $0.id == selectedStaffId })
        else { return }
        do {
            _ = try await PostSalesConvexAPIService.assignLoan(
                token: token,
                request: AssignLoanRequest(
                    loanCaseId: loanCase.id,
                    legalStaffId: staff.id,
                    legalStaffName: staff.displayName
                )
            )
            assigningCase = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func accept(_ loanCase: LoanCaseRow) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            _ = try await PostSalesConvexAPIService.legalAcceptLoan(token: token, loanCaseId: loanCase.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reject(_ loanCase: LoanCaseRow) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            _ = try await PostSalesConvexAPIService.legalRejectLoan(token: token, loanCaseId: loanCase.id, remarks: rejectRemarks)
            rejectingCase = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PostSalesCaseLookupView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var mobile = ""
    @State private var cases: [PostSaleCaseSummary] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                FleetHeader(
                    title: "Case Lookup",
                    subtitle: "Find post-sale bookings by mobile number",
                    systemImage: "person.text.rectangle.fill"
                )
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("Mobile number", text: $mobile)
                            .keyboardType(.phonePad)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await search() }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: 0x0B61CA))
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))

                    if isLoading {
                        AppModuleLoadingRows()
                    } else if cases.isEmpty && hasSearched {
                        ContentUnavailableView("No Cases", systemImage: "doc.text.magnifyingglass")
                            .padding(.vertical, 28)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(cases) { item in
                                PostSaleCaseCard(item: item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, -34)
            }
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Case Lookup")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Case Lookup", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func search() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            return
        }
        let phone = AppModuleFormatters.normalizePhone(mobile)
        guard !phone.isEmpty else { return }
        isLoading = true
        defer {
            isLoading = false
            hasSearched = true
        }
        do {
            cases = try await PostSalesConvexAPIService.getCasesByMobile(token: token, mobile: phone)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum LoanDeskMode: String, CaseIterable, Identifiable {
    case sales, legalTeam, legalManager

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sales: return "Sales"
        case .legalTeam: return "Legal"
        case .legalManager: return "Manager"
        }
    }

    init(user: AuthUser?) {
        let text = [user?.designation, user?.department, user?.role]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if text.contains("legal") && (text.contains("manager") || text.contains("head") || text.contains("lead")) {
            self = .legalManager
        } else if text.contains("legal") {
            self = .legalTeam
        } else {
            self = .sales
        }
    }
}

private struct LoanModeBanner: View {
    let mode: LoanDeskMode

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.key.fill")
                .foregroundStyle(Color(hex: 0x0B61CA))
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(AppModuleFont.rowMetaSemibold)
                    .foregroundStyle(Color(hex: 0x101828))
                Text("Workflow matched to your staff role")
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(Color(hex: 0x667085))
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum CollectionPaymentFilter: String, CaseIterable, Identifiable {
    case all, selfFinance, bankLoan

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .selfFinance: return "Self Finance"
        case .bankLoan: return "Bank Loan"
        }
    }
}

private struct CollectionSummary {
    let count: Int
    let amount: Double

    init(rows: [CustomerCollectionRow]) {
        count = rows.count
        amount = rows.reduce(0) { $0 + ($1.amount ?? 0) }
    }
}

private struct URLPreviewItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private func filterCollections(
    _ rows: [CustomerCollectionRow],
    filter: CollectionPaymentFilter,
    searchText: String
) -> [CustomerCollectionRow] {
    let categoryFiltered = rows.filter { row in
        switch filter {
        case .all:
            return true
        case .selfFinance:
            return row.normalizedPaymentCategory.contains("cash") || row.normalizedPaymentCategory.contains("self")
        case .bankLoan:
            return row.normalizedPaymentCategory.contains("loan") || row.normalizedPaymentCategory.contains("bank")
        }
    }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return categoryFiltered }
    return categoryFiltered.filter { row in
        [
            row.collectionRefNo,
            row.customerName,
            row.bookingRefNo,
            row.projectName,
            row.plotNo,
            row.paymentMode,
            row.transactionReference,
            row.customerPaymentCategory
        ]
        .compactMap { $0?.lowercased() }
        .contains { $0.contains(query) }
    }
}

private struct CollectionControls: View {
    @Binding var filter: CollectionPaymentFilter
    let summary: CollectionSummary

    var body: some View {
        VStack(spacing: 10) {
            Picker("Payment category", selection: $filter) {
                ForEach(CollectionPaymentFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                summaryTile("Rows", "\(summary.count)", systemImage: "list.bullet.rectangle")
                summaryTile("Total", AppModuleFormatters.rupees(summary.amount), systemImage: "indianrupeesign.circle")
            }
        }
    }

    private func summaryTile(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color(hex: 0x0B61CA))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(Color(hex: 0x667085))
                Text(value)
                    .font(AppModuleFont.rowMetaSemibold)
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CollectionRowCard: View {
    let collection: CustomerCollectionRow
    var onProof: (() async -> Void)?
    var onRectify: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 42, height: 42)
                    .background(statusColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.displayTitle)
                        .font(AppModuleFont.rowTitle)
                        .foregroundStyle(Color(hex: 0x101828))
                    Text([collection.bookingRefNo, collection.projectName, collection.plotNo].compactMap { $0?.nonBlank }.joined(separator: " · "))
                        .font(AppModuleFont.rowMeta)
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                AppModuleBadge(text: collection.displayStatus, tint: statusColor)
            }

            HStack(spacing: 10) {
                metric("Amount", AppModuleFormatters.rupees(collection.amount ?? 0))
                metric("Mode", collection.paymentMode?.uppercased() ?? "-")
            }
            if let ref = collection.transactionReference?.nonBlank {
                Label(ref, systemImage: "number")
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(Color(hex: 0x667085))
            }
            HStack(spacing: 10) {
                if collection.proofStorageId?.nonBlank != nil, let onProof {
                    Button {
                        Task { await onProof() }
                    } label: {
                        Label("Proof", systemImage: "doc.viewfinder")
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(hex: 0x0B61CA))
                }
                if let onRectify {
                    Button {
                        onRectify()
                    } label: {
                        Label("Rectify", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: 0xB54708))
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private var statusColor: Color {
        switch (collection.verificationStatus ?? "").lowercased() {
        case "approved", "verified": return Color(hex: 0x16A34A)
        case "rejected": return Color(hex: 0xB42318)
        default: return Color(hex: 0xB54708)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppModuleFont.rowMeta)
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(Color(hex: 0x101828))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct LoanDeskCaseCard: View {
    let loanCase: LoanCaseRow
    let mode: LoanDeskMode
    let onAssign: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: 0xEAF3FF), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(loanCase.displayTitle)
                        .font(AppModuleFont.rowTitle)
                        .foregroundStyle(Color(hex: 0x101828))
                    Text([loanCase.projectName, loanCase.plotNo, loanCase.phone].compactMap { $0?.nonBlank }.joined(separator: " · "))
                        .font(AppModuleFont.rowMeta)
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                AppModuleBadge(text: loanCase.displayStatus, tint: Color(hex: 0x0B61CA))
            }

            HStack(spacing: 10) {
                metric("Amount", AppModuleFormatters.rupees(loanCase.displayAmount))
                metric("Docs", "\(loanCase.documentCount ?? loanCase.documentsChecklist?.count ?? 0)")
            }

            if let assignee = loanCase.legalAssignedName?.nonBlank {
                Label(assignee, systemImage: "person.crop.circle.badge.checkmark")
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(Color(hex: 0x667085))
            }

            HStack(spacing: 10) {
                if mode == .sales || mode == .legalManager {
                    Button("Assign") { onAssign() }
                        .buttonStyle(.bordered)
                        .tint(Color(hex: 0x0B61CA))
                }
                if mode != .sales {
                    Button("Accept") { onAccept() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: 0x16A34A))
                    Button("Reject") { onReject() }
                        .buttonStyle(.bordered)
                        .tint(Color(hex: 0xB42318))
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppModuleFont.rowMeta)
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(Color(hex: 0x101828))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PostSaleCaseCard: View {
    let item: PostSaleCaseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(AppModuleFont.rowTitle)
                    Text(item.subtitle)
                        .font(AppModuleFont.rowMeta)
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Spacer()
                AppModuleBadge(text: item.currentStage ?? "Open", tint: Color(hex: 0x0B61CA))
            }
            HStack(spacing: 10) {
                metric("Total", AppModuleFormatters.rupees(item.totalAmount ?? 0))
                metric("Balance", AppModuleFormatters.rupees(item.balanceAmount ?? 0))
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppModuleFont.rowMeta)
                .foregroundStyle(Color(hex: 0x667085))
            Text(value)
                .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(Color(hex: 0x101828))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CollectionSubmitSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let rectifyingCollection: CustomerCollectionRow?
    @State private var caseId = ""
    @State private var mobile = ""
    @State private var caseMatches: [PostSaleCaseSummary] = []
    @State private var selectedCaseId = ""
    @State private var amount = ""
    @State private var paymentMode = "cash"
    @State private var reference = ""
    @State private var bankName = ""
    @State private var notes = ""
    @State private var proofFile: PostSalesUploadedFile?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isSearching = false
    @State private var isUploading = false
    @State private var showingFileImporter = false
    let onSaved: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    HStack {
                        TextField("Mobile number", text: $mobile)
                            .keyboardType(.phonePad)
                        Button {
                            Task { await searchCases() }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .disabled(isSearching || AppModuleFormatters.normalizePhone(mobile).isEmpty)
                    }

                    if !caseMatches.isEmpty {
                        Picker("Case", selection: $selectedCaseId) {
                            ForEach(caseMatches) { item in
                                Text(item.title).tag(item.id)
                            }
                        }
                    }

                    TextField("Case ID", text: $caseId)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("Payment Mode", selection: $paymentMode) {
                        ForEach(["cash", "upi", "neft", "rtgs", "cheque", "dd", "bank"], id: \.self) { mode in
                            Text(mode.uppercased()).tag(mode)
                        }
                    }
                    TextField("Transaction Reference", text: $reference)
                    TextField("Bank Name", text: $bankName)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section("Proof") {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label(proofFile?.fileName ?? "Attach payment proof", systemImage: "paperclip")
                    }
                    if isUploading {
                        ProgressView("Uploading proof...")
                    }
                    if let proofFile {
                        Text(proofFile.storageId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(rectifyingCollection == nil ? "New Collection" : "Rectify Collection")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: applyRectifyPrefill)
            .onChange(of: selectedCaseId) { _, newValue in
                if !newValue.isEmpty { caseId = newValue }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.image, .pdf, .data],
                allowsMultipleSelection: false
            ) { result in
                Task { await importProof(result) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving..." : "Save") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || isUploading || caseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(amount) == nil)
                }
            }
            .alert("Collection", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func applyRectifyPrefill() {
        guard let row = rectifyingCollection, caseId.isEmpty else { return }
        caseId = row.caseId ?? ""
        selectedCaseId = row.caseId ?? ""
        amount = row.amount.map { String($0) } ?? ""
        paymentMode = row.paymentMode ?? "cash"
        reference = row.transactionReference ?? ""
        bankName = row.bankName ?? ""
        notes = row.notes ?? row.verificationNotes ?? ""
    }

    @MainActor
    private func searchCases() async {
        guard let token = authStore.currentSession?.token else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            caseMatches = try await PostSalesConvexAPIService.getCasesByMobile(
                token: token,
                mobile: AppModuleFormatters.normalizePhone(mobile)
            )
            if let first = caseMatches.first {
                selectedCaseId = first.id
                caseId = first.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importProof(_ result: Result<[URL], Error>) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            guard let url = try result.get().first else { return }
            isUploading = true
            defer { isUploading = false }
            proofFile = try await PostSalesStorageService.uploadFile(token: token, fileURL: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submit() async {
        guard let token = authStore.currentSession?.token, let amountValue = Double(amount) else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await PostSalesConvexAPIService.submitCollection(
                token: token,
                request: SubmitCollectionRequest(
                    caseId: caseId.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: amountValue,
                    paymentMode: paymentMode,
                    transactionReference: reference.nonBlank,
                    bankName: bankName.nonBlank,
                    proofStorageId: proofFile?.storageId,
                    proofFileName: proofFile?.fileName,
                    notes: notes.nonBlank
                )
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RejectCollectionSheet: View {
    var title = "Reject Collection"
    @Binding var remarks: String
    let onSubmit: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Remarks", text: $remarks, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving..." : "Submit") {
                        Task {
                            isSubmitting = true
                            await onSubmit()
                            isSubmitting = false
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting || remarks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct AssignLoanSheet: View {
    let staff: [LegalStaffRow]
    @Binding var selectedStaffId: String
    let onSubmit: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Legal Staff", selection: $selectedStaffId) {
                    ForEach(staff) { member in
                        Text(member.displayName).tag(member.id)
                    }
                }
            }
            .navigationTitle("Assign Loan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving..." : "Assign") {
                        Task {
                            isSubmitting = true
                            await onSubmit()
                            isSubmitting = false
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting || selectedStaffId.isEmpty)
                }
            }
        }
    }
}

private struct SubmitLoanCaseSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var caseId = ""
    @State private var applicantType = "salaried"
    @State private var requestedAmount = ""
    @State private var documents = LoanDocumentDraft.defaultSet
    @State private var importingDocumentId: UUID?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isUploading = false
    let onSaved: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Case ID", text: $caseId)
                    Picker("Applicant Type", selection: $applicantType) {
                        Text("Salaried").tag("salaried")
                        Text("Business").tag("business")
                        Text("Pension").tag("pension")
                    }
                    TextField("Requested Amount", text: $requestedAmount)
                        .keyboardType(.decimalPad)
                }

                Section("Documents") {
                    ForEach($documents) { $document in
                        HStack(spacing: 12) {
                            Image(systemName: document.storageId == nil ? "doc.badge.plus" : "doc.fill")
                                .foregroundStyle(document.storageId == nil ? Color(hex: 0x667085) : Color(hex: 0x16A34A))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.label)
                                Text(document.fileName ?? "No file selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                importingDocumentId = document.id
                            } label: {
                                Image(systemName: "paperclip")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if isUploading {
                        ProgressView("Uploading document...")
                    }
                }
            }
            .navigationTitle("Submit Loan")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: Binding(
                    get: { importingDocumentId != nil },
                    set: { if !$0 { importingDocumentId = nil } }
                ),
                allowedContentTypes: [.image, .pdf, .data],
                allowsMultipleSelection: false
            ) { result in
                Task { await importDocument(result) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving..." : "Submit") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || isUploading || caseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || uploadedDocuments.isEmpty)
                }
            }
            .alert("Loan Desk", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var uploadedDocuments: [SubmitLoanDocument] {
        documents.compactMap { document in
            guard let storageId = document.storageId else { return nil }
            return SubmitLoanDocument(label: document.label, storageId: storageId, fileName: document.fileName)
        }
    }

    @MainActor
    private func importDocument(_ result: Result<[URL], Error>) async {
        guard let token = authStore.currentSession?.token,
              let documentId = importingDocumentId
        else { return }
        do {
            guard let url = try result.get().first else { return }
            isUploading = true
            defer {
                isUploading = false
                importingDocumentId = nil
            }
            let uploaded = try await PostSalesStorageService.uploadFile(token: token, fileURL: url)
            if let index = documents.firstIndex(where: { $0.id == documentId }) {
                documents[index].storageId = uploaded.storageId
                documents[index].fileName = uploaded.fileName
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submit() async {
        guard let token = authStore.currentSession?.token else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await PostSalesConvexAPIService.submitLoanRequest(
                token: token,
                request: SubmitLoanDeskRequest(
                    caseId: caseId.trimmingCharacters(in: .whitespacesAndNewlines),
                    applicantType: applicantType,
                    requestedAmount: Double(requestedAmount),
                    documents: uploadedDocuments
                )
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LoanDocumentDraft: Identifiable, Equatable {
    let id = UUID()
    let label: String
    var storageId: String?
    var fileName: String?

    static let defaultSet = [
        LoanDocumentDraft(label: "PAN Card"),
        LoanDocumentDraft(label: "Aadhaar Card"),
        LoanDocumentDraft(label: "Bank Statement"),
        LoanDocumentDraft(label: "Pay Slip")
    ]
}

private struct StoragePreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        ContentUnavailableView(
                            "Preview Unavailable",
                            systemImage: "doc",
                            description: Text("Open the signed file link to view this proof.")
                        )
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Link(destination: url) {
                    Label("Open File", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x0B61CA))
            }
            .padding(18)
            .navigationTitle("Proof")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private extension CustomerCollectionRow {
    var isRejected: Bool {
        (verificationStatus ?? "").localizedCaseInsensitiveContains("reject")
    }

    var normalizedPaymentCategory: String {
        (customerPaymentCategory ?? "").replacingOccurrences(of: "_", with: " ").lowercased()
    }
}
