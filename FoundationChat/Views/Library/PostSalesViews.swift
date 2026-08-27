import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CollectionsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var collections: [CustomerCollectionRow] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showingSubmitSheet = false
    @State private var rectifyingCollection: CustomerCollectionRow?
    @State private var editingCollection: CustomerCollectionRow?
    @State private var selectedFilter: CollectionPaymentFilter = .all
    @State private var selectedFromDate: Date?
    @State private var selectedToDate: Date?
    @State private var draftFromDate = Date()
    @State private var draftToDate = Date()
    @State private var showingDateFilter = false
    @State private var searchText = ""
    @State private var previewURL: URL?

    private var visibleCollections: [CustomerCollectionRow] {
        filterCollections(
            collections,
            filter: selectedFilter,
            searchText: searchText,
            fromDate: selectedFromDate,
            toDate: selectedToDate
        )
    }

    private var cacheKey: String {
        let staffId = authStore.viewer?.subject ?? authStore.currentSession?.user._id ?? "anonymous"
        return "postsales.collections.my.\(staffId)"
    }

    private var summary: CollectionSummary {
        CollectionSummary(rows: visibleCollections)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    PostSalesSegmentedFilter(selection: $selectedFilter)

                    PostSalesSummaryCard(
                        leadingTitle: "\(visibleCollections.count) Collections",
                        amount: summary.amount
                    )

                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Collections"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .toolbarBackground(Color.appElevatedSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Collections")
                    .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    draftFromDate = selectedFromDate ?? Date()
                    draftToDate = selectedToDate ?? draftFromDate
                    showingDateFilter = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Filter collections by date")

                Button {
                    showingSubmitSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                }
                .accessibilityLabel("Create collection")
            }
        }
        .tint(Color(hex: 0x0B61CA))
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .sheet(isPresented: $showingSubmitSheet) {
            CollectionSubmitSheet(rectifyingCollection: nil) {
                await load()
            }
            .appFormActivity()
            .appLibraryNativeSheet([.height(720), .large])
            .presentationBackground(Color.appElevatedSurface)
        }
        .sheet(item: $rectifyingCollection) { collection in
            CollectionSubmitSheet(rectifyingCollection: collection) {
                await load()
            }
            .appFormActivity()
            .appLibraryNativeSheet([.height(720), .large])
            .presentationBackground(Color.appElevatedSurface)
        }
        .sheet(item: $editingCollection) { collection in
            EditCollectionAmountSheet(collection: collection) {
                await load()
            }
            .appLibraryNativeSheet([.height(320), .medium])
            .presentationBackground(Color.white)
        }
        .sheet(isPresented: $showingDateFilter) {
            PostSalesCollectionDateFilterSheet(
                fromDate: $draftFromDate,
                toDate: $draftToDate,
                selectedFromDate: $selectedFromDate,
                selectedToDate: $selectedToDate
            )
                .appLibraryNativeSheet([.height(680), .large])
            .presentationBackground(Color.appElevatedSurface)
        }
        .sheet(item: Binding(get: { previewURL.map(URLPreviewItem.init(url:)) }, set: { if $0 == nil { previewURL = nil } })) { item in
            StoragePreviewSheet(url: item.url)
                .appLibraryNativeSheet([.medium, .large])
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
                    systemImage: "indianrupeesign.circle",
                    description: Text("Collections matching the selected filters will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(visibleCollections) { collection in
                        CollectionRowCard(
                            collection: collection,
                            onProof: { await openProof(collection) },
                            onRectify: collection.isRejected ? { rectifyingCollection = collection } : nil,
                            // Own still-pending row — correct a wrong amount before
                            // Accounts acts on it (mirrors Android "Edit amount").
                            onEdit: (!collection.isRejected && collection.isPendingVerification)
                                ? { editingCollection = collection }
                                : nil
                        )
                    }
                }
            }
        }
    }

    @MainActor
    private func load() async {
        if collections.isEmpty, let cached = LocalCache.get(cacheKey, as: [CustomerCollectionRow].self) {
            collections = cached
            hasLoaded = true
        }
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
            LocalCache.put(cacheKey, collections)
        } catch {
            if collections.isEmpty { errorMessage = error.localizedDescription }
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
    @Environment(\.dismiss) private var dismiss
    @State private var collections: [CustomerCollectionRow] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var selectedForReject: CustomerCollectionRow?
    @State private var rejectRemarks = ""
    @State private var selectedFilter: CollectionPaymentFilter = .all
    @State private var selectedFromDate: Date?
    @State private var selectedToDate: Date?
    @State private var draftFromDate = Date()
    @State private var draftToDate = Date()
    @State private var showingDateFilter = false
    @State private var searchText = ""
    @State private var previewURL: URL?
    @State private var processingCollectionIds: Set<String> = []

    private var visibleCollections: [CustomerCollectionRow] {
        filterCollections(
            collections,
            filter: selectedFilter,
            searchText: searchText,
            fromDate: selectedFromDate,
            toDate: selectedToDate
        )
    }

    private var cacheKey: String {
        let staffId = authStore.viewer?.subject ?? authStore.currentSession?.user._id ?? "anonymous"
        return "postsales.collections.accounts.\(staffId)"
    }

    private var summary: CollectionSummary {
        CollectionSummary(rows: visibleCollections)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    PostSalesSegmentedFilter(selection: $selectedFilter)

                    PostSalesSummaryCard(
                        leadingTitle: "\(summary.count) Pending Verification",
                        amount: summary.amount
                    )

                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .navigationTitle("Post Sales Verification")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Sales Verification"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .toolbarBackground(Color.appElevatedSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Post Sales Verification")
                    .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draftFromDate = selectedFromDate ?? Date()
                    draftToDate = selectedToDate ?? draftFromDate
                    showingDateFilter = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Filter verification by date")
            }
        }
        .tint(Color(hex: 0x0B61CA))
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .alert("Accounts", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $selectedForReject) { collection in
            RejectCollectionSheet(
                title: "Rejection Remarks",
                subtitle: "Specify details about why this is rejected",
                remarks: $rejectRemarks
            ) {
                await reject(collection)
            }
            .appLibraryNativeSheet([.medium])
        }
        .sheet(item: Binding(get: { previewURL.map(URLPreviewItem.init(url:)) }, set: { if $0 == nil { previewURL = nil } })) { item in
            StoragePreviewSheet(url: item.url)
                .appLibraryNativeSheet([.medium, .large])
        }
        .sheet(isPresented: $showingDateFilter) {
            PostSalesCollectionDateFilterSheet(
                fromDate: $draftFromDate,
                toDate: $draftToDate,
                selectedFromDate: $selectedFromDate,
                selectedToDate: $selectedToDate
            )
                .appLibraryNativeSheet([.height(680), .large])
            .presentationBackground(Color.appElevatedSurface)
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
                    description: Text("Collections awaiting Accounts verification will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(visibleCollections) { collection in
                        CollectionRowCard(
                            collection: collection,
                            onProof: {
                                await openProof(collection)
                            },
                            onReject: collection.isPendingVerification && !processingCollectionIds.contains(collection.id) ? {
                                rejectRemarks = ""
                                selectedForReject = collection
                            } : nil,
                            onAccept: collection.isPendingVerification && !processingCollectionIds.contains(collection.id) ? {
                                Task<Void, Never> { await approve(collection) }
                            } : nil
                        )
                    }
                }
            }
        }
    }

    @MainActor
    private func load() async {
        if collections.isEmpty, let cached = LocalCache.get(cacheKey, as: [CustomerCollectionRow].self) {
            collections = cached
            hasLoaded = true
        }
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
            LocalCache.put(cacheKey, collections)
        } catch {
            if collections.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func approve(_ collection: CustomerCollectionRow) async {
        guard let token = authStore.currentSession?.token else { return }
        guard collection.isPendingVerification else {
            errorMessage = "Only pending collections can be approved."
            return
        }
        guard processingCollectionIds.insert(collection.id).inserted else { return }
        defer { processingCollectionIds.remove(collection.id) }
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
        guard collection.isPendingVerification else {
            errorMessage = "Only pending collections can be rejected."
            return
        }
        guard processingCollectionIds.insert(collection.id).inserted else { return }
        defer { processingCollectionIds.remove(collection.id) }
        let trimmedRemarks = rejectRemarks.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemarks.isEmpty else {
            errorMessage = "Remarks are required to reject."
            return
        }
        do {
            _ = try await PostSalesConvexAPIService.rejectCollection(token: token, collectionId: collection.id, remarks: trimmedRemarks)
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
    @Environment(\.dismiss) private var dismiss
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
    @State private var documentsCase: LoanCaseRow?
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

    private var resolvedMode: LoanDeskMode {
        LoanDeskMode(user: authStore.currentSession?.user)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .navigationTitle("Loan Desk")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Loan Desk"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .toolbarBackground(Color.appElevatedSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Loan Desk")
                    .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            }
        }
        .tint(Color(hex: 0x0B61CA))
        .toolbar(.hidden, for: .tabBar)
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
            .appLibraryNativeSheet([.medium])
        }
        .sheet(item: $rejectingCase) { loanCase in
            RejectCollectionSheet(title: "Reject Loan", remarks: $rejectRemarks) {
                await reject(loanCase)
            }
            .appLibraryNativeSheet([.medium])
        }
        .sheet(item: $documentsCase) { loanCase in
            LoanCaseDocumentsSheet(loanCase: loanCase, mode: selectedMode) {
                await load()
            }
            .appLibraryNativeSheet([.large])
            .presentationBackground(Color.white)
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            if isLoading && !hasLoaded {
                AppModuleLoadingRows()
            } else if visibleCases.isEmpty {
                loanDeskEmptyState
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
                            },
                            onOpenDocuments: {
                                documentsCase = loanCase
                            }
                        )
                    }
                }
            }
        }
    }

    private var loanDeskEmptyState: some View {
        let hasQuery = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: 12) {
            Image("LoansEmptyState")
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 150)
                .opacity(0.82)

            Text(hasQuery ? "No Loan Requests Found" : "No Loan Desk Yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            Text(hasQuery
                 ? "Try searching with a different customer, phone number, booking reference, or project."
                 : "Loan requests and their processing status will appear here when records become available.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 500)
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
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16))

                    if isLoading {
                        AppModuleLoadingRows()
                    } else if cases.isEmpty && hasSearched {
                        ContentUnavailableView("No Cases", systemImage: "doc.text.magnifyingglass")
                            .padding(.vertical, 28)
                            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 18))
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
        // Include the staff name: many real records carry the Loan-Desk role
        // signal in the name (e.g. name="Legal Manager") rather than the
        // designation — mirrors Android's composite haystack.
        let text = [user?.designation, user?.department, user?.role, user?.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if text.contains("legal manager") || text.contains("legal head")
            || (text.contains("legal") && (text.contains("manager") || text.contains("head") || text.contains("lead"))) {
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
                .foregroundStyle(.primary)
                Text("Workflow matched to your staff role")
                    .font(AppModuleFont.rowMeta)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PostSalesSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
                .textInputAutocapitalization(.words)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xE0E4EC), lineWidth: 1)
        )
    }
}

struct PostSalesSegmentedFilter: View {
    @Binding var selection: CollectionPaymentFilter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CollectionPaymentFilter.allCases) { item in
                Button {
                    withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
                        selection = item
                    }
                } label: {
                    Text(item.title)
                        .font(.system(size: 14, weight: selection == item ? .bold : .semibold))
                        .foregroundStyle(selection == item ? .white : Color(hex: 0x667085))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            selection == item ? Color(hex: 0x0B61CA) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.appSurface, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
    }
}

struct PostSalesSummaryCard: View {
    let leadingTitle: String
    let amount: Double

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "dollarsign.square")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.13), in: Circle())

            Text(leadingTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text("Total Amount")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.78))
                Text(AppModuleFormatters.rupees(amount))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x0B61CA), Color(hex: 0x02499D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

enum CollectionPaymentFilter: String, CaseIterable, Identifiable {
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
        count = rows.count { $0.isPendingVerification }
        amount = rows.reduce(0) { $0 + ($1.amount ?? 0) }
    }
}

private struct URLPreviewItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct PostSalesCollectionDateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fromDate: Date
    @Binding var toDate: Date
    @Binding var selectedFromDate: Date?
    @Binding var selectedToDate: Date?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.primary)
                            .frame(width: 86, height: 44)
                            .background(Color.appFieldBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 12)

                    HStack(spacing: 18) {
                        Button {
                            selectedFromDate = nil
                            selectedToDate = nil
                            dismiss()
                        } label: {
                            Text("Clear")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(selectedFromDate == nil ? Color(hex: 0xC4C7CE) : Color(hex: 0x0B61CA))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedFromDate == nil)

                        Button {
                            if fromDate <= toDate {
                                selectedFromDate = fromDate
                                selectedToDate = toDate
                            } else {
                                selectedFromDate = toDate
                                selectedToDate = fromDate
                            }
                            dismiss()
                        } label: {
                            Text("Select")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x0B61CA))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 128, alignment: .trailing)
                }

                Text("Date Filter")
                    .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 18)

            VStack(spacing: 14) {
                Text("Select Date Range")
                    .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)

                DatePicker("From", selection: $fromDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(Color(hex: 0x0B61CA))
                    .padding(.horizontal, 22)

                DatePicker("To", selection: $toDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(Color(hex: 0x0B61CA))
                    .padding(.horizontal, 22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.appSurface)
    }
}

private func filterCollections(
    _ rows: [CustomerCollectionRow],
    filter: CollectionPaymentFilter,
    searchText: String,
    fromDate: Date?,
    toDate: Date?
) -> [CustomerCollectionRow] {
    let categoryFiltered = rows.filter { row in
        // Android maps only `loan` → BANK_LOAN; everything else (cash_in_hand,
        // null, unknown) falls into SELF_FINANCE. Mirror that so self-financed
        // rows with a blank category still show under the Self Finance tab.
        let isBankLoan = row.normalizedPaymentCategory == "loan"
        switch filter {
        case .all:
            return true
        case .selfFinance:
            return !isBankLoan
        case .bankLoan:
            return isBankLoan
        }
    }
    let dateFiltered: [CustomerCollectionRow]
    if let fromDate, let toDate {
        dateFiltered = categoryFiltered.filter { $0.matchesCollectionDateRange(from: fromDate, to: toDate) }
    } else {
        dateFiltered = categoryFiltered
    }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return dateFiltered }
    return dateFiltered.filter { row in
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
        .compactMap { $0 }
        .contains { $0.localizedStandardContains(query) }
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
                summaryTile(
                    "Pending Verification",
                    summary.count == 1 ? "1" : "\(summary.count)",
                    systemImage: "checkmark.seal"
                )
                summaryTile("Total Amount", AppModuleFormatters.rupees(summary.amount), systemImage: "indianrupeesign.circle")
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
                .foregroundStyle(.secondary)
                Text(value)
                    .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CollectionRowCard: View {
    let collection: CustomerCollectionRow
    var onProof: (() async -> Void)? = nil
    var onRectify: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onReject: (() -> Void)? = nil
    var onAccept: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text(AppModuleFormatters.rupees(collection.amount ?? 0))
                        .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 12)
                    statusBadge
                }

                Text(collection.androidBookingLabel)
                    .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            DashedDivider()
                .stroke(Color(hex: 0xEAECF0), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .frame(height: 1)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    collectionInfoRow(
                        title: "Payment Mode",
                        value: collection.humanPaymentMode,
                        systemImage: "creditcard"
                    )
                    collectionInfoRow(
                        title: "Ref ID",
                        value: collection.transactionReference?.nonBlank ?? "-",
                        systemImage: "number"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let storageId = collection.proofStorageId?.nonBlank {
                    CollectionProofThumbnail(storageId: storageId) {
                        if let onProof {
                            await onProof()
                        }
                    }
                }
            }

            if let date = collection.androidCollectionDate {
                Label(collection.isEdited ? "\(date)  ·  Edited" : date, systemImage: "calendar")
                    .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
            }

            if collection.isRejected, let remarks = collection.verificationNotes?.nonBlank {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accountant's Remarks:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0xB42318))
                    Text(remarks)
                        .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xFFF1F0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let onReject, let onAccept {
                HStack(spacing: 12) {
                    Button {
                        onReject()
                    } label: {
                        Label("Reject", systemImage: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(hex: 0xF04438))

                    Button {
                        onAccept()
                    } label: {
                        Label("Accept", systemImage: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: 0x16A34A))
                }
                .padding(.top, 4)
            } else if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit amount", systemImage: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x0B61CA))
                .padding(.top, 4)
            } else if let onRectify {
                Button {
                    onRectify()
                } label: {
                    Label("Re-submit", systemImage: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x16A34A))
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(collection.androidStatusLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusColor: Color {
        switch (collection.verificationStatus ?? "").lowercased() {
        case "approved", "verified": return Color(hex: 0x16A34A)
        case "rejected": return Color(hex: 0xB42318)
        default: return Color(hex: 0xB54708)
        }
    }

    private func collectionInfoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 28, height: 28)
                .background(Color.appFieldBackground, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DashedDivider: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct CollectionProofThumbnail: View {
    @Environment(AuthStore.self) private var authStore
    let storageId: String
    let onTap: () async -> Void
    @State private var thumbnailURL: URL?
    @State private var didFail = false

    var body: some View {
        Button {
            Task { await onTap() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.appFieldBackground)
                if let thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            proofFallback
                        @unknown default:
                            proofFallback
                        }
                    }
                } else if didFail {
                    proofFallback
                } else {
                    ProgressView()
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(hex: 0xE4E7EC), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .task(id: storageId) {
            await loadThumbnail()
        }
    }

    private var proofFallback: some View {
        Image(systemName: "doc.viewfinder")
            .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tertiary)
    }

    @MainActor
    private func loadThumbnail() async {
        guard thumbnailURL == nil,
              let token = authStore.currentSession?.token
        else { return }
        do {
            thumbnailURL = try await PostSalesStorageService.getFileURL(token: token, storageId: storageId)
        } catch {
            didFail = true
        }
    }
}

private struct LoanDeskCaseCard: View {
    let loanCase: LoanCaseRow
    let mode: LoanDeskMode
    let onAssign: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void
    let onOpenDocuments: () -> Void

    // Status gating mirrors Android's LoanDeskAdapter, which keys actions off
    // the server-supplied statusLabel ("Docs Pending" / "App Received" /
    // "Approved" / "Rejected").
    private var statusLabel: String { loanCase.statusLabel?.nonBlank ?? "Docs Pending" }
    private var isAppReceived: Bool { statusLabel.caseInsensitiveCompare("App Received") == .orderedSame }
    private var isRejected: Bool { statusLabel.caseInsensitiveCompare("Rejected") == .orderedSame }
    private var isDocsPending: Bool { statusLabel.caseInsensitiveCompare("Docs Pending") == .orderedSame }
    private var isAssigned: Bool { loanCase.legalAssignedName?.nonBlank != nil }

    private var statusTint: Color {
        switch statusLabel.lowercased() {
        case "approved": return Color(hex: 0x16A34A)
        case "rejected": return Color(hex: 0xF04438)
        case "app received": return Color(hex: 0xB42318)
        default: return Color(hex: 0xB93815)
        }
    }

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
                .foregroundStyle(.primary)
                    Text([loanCase.projectName, loanCase.plotNo, loanCase.phone].compactMap { $0?.nonBlank }.joined(separator: " · "))
                        .font(AppModuleFont.rowMeta)
                .foregroundStyle(.secondary)
                }
                Spacer()
                AppModuleBadge(text: statusLabel, tint: statusTint)
            }

            HStack(spacing: 10) {
                metric("Amount", AppModuleFormatters.rupees(loanCase.displayAmount))
                metric("Docs", "\(loanCase.documentCount ?? loanCase.documentsChecklist?.count ?? 0)")
            }

            if let assignee = loanCase.legalAssignedName?.nonBlank {
                Label("Assigned: \(assignee)", systemImage: "person.crop.circle.badge.checkmark")
                    .font(AppModuleFont.rowMeta)
                .foregroundStyle(.secondary)
            }

            // Sales sees the legal officer's rejection remarks so they know what
            // to fix before re-uploading (mirrors Android's rejected-row remarks).
            if isRejected, let remarks = loanCase.legalRejectionRemarks?.nonBlank {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rejection Remarks:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0xB42318))
                    Text(remarks)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xFFF1F0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            actionRow
        }
        .padding(16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    @ViewBuilder
    private var actionRow: some View {
        switch mode {
        case .sales:
            // Sales manages the document checklist. Once a legal officer is
            // assigned the case is locked to view-only (handled in the sheet).
            Group {
                if isAssigned {
                    Button { onOpenDocuments() } label: { salesDocumentsLabel }
                        .buttonStyle(.bordered)
                } else {
                    Button { onOpenDocuments() } label: { salesDocumentsLabel }
                        .buttonStyle(.borderedProminent)
                }
            }
            .tint(Color(hex: 0x0B61CA))
            .padding(.top, 2)

        case .legalManager:
            HStack(spacing: 10) {
                documentsButton
                // Manager only assigns while the case is awaiting allocation.
                if isAppReceived && !isAssigned {
                    Button { onAssign() } label: {
                        Label("Assign", systemImage: "person.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: 0x0B61CA))
                }
            }
            .padding(.top, 2)

        case .legalTeam:
            VStack(spacing: 10) {
                documentsButton
                if isAppReceived {
                    HStack(spacing: 10) {
                        Button { onReject() } label: {
                            Label("Reject", systemImage: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(hex: 0xF04438))

                        Button { onAccept() } label: {
                            Label("Accept", systemImage: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: 0x16A34A))
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var salesDocumentsLabel: some View {
        Label(isAssigned ? "View Documents" : (isRejected ? "Re-upload Documents" : "Upload Documents"),
              systemImage: isAssigned ? "doc.text.magnifyingglass" : "arrow.up.doc")
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
    }

    // Legal roles can review the uploaded documents once they exist (Android
    // only wires the card tap when status != "Docs Pending").
    @ViewBuilder
    private var documentsButton: some View {
        if !isDocsPending {
            Button {
                onOpenDocuments()
            } label: {
                Label("View Documents", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.bordered)
            .tint(Color(hex: 0x0B61CA))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppModuleFont.rowMeta)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 10))
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
                .foregroundStyle(.secondary)
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
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppModuleFont.rowMeta)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}

private enum CollectionEntryPaymentMode: String, CaseIterable, Identifiable {
    case cash
    case upi
    case neft
    case rtgs
    case cheque
    case dd
    case bank

    var id: String { rawValue }
    var title: String { self == .bank ? "Bank Transfer" : rawValue.uppercased() }
    var isCash: Bool { self == .cash }
    var isInstrument: Bool { self == .cheque || self == .dd }
}

private struct CollectionBookingSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let cases: [PostSaleCaseSummary]
    let selectedCaseId: String
    let onSelect: (PostSaleCaseSummary) -> Void
    @State private var searchText = ""

    private var filteredCases: [PostSaleCaseSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return cases }
        return cases.filter { item in
            [
                item.clientName,
                item.bookingRefNo,
                item.mobileNumber,
                item.projectName,
                item.plotNo
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredCases) { item in
                Button {
                    onSelect(item)
                    dismiss()
                } label: {
                    CollectionBookingSelectionRow(
                        item: item,
                        isSelected: item.id == selectedCaseId
                    )
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if filteredCases.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Select Booking")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search customer, booking or project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct CollectionBookingSelectionRow: View {
    let item: PostSaleCaseSummary
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.clientName?.nonBlank ?? "Customer")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(item.bookingRefNo?.nonBlank ?? "Booking reference unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
            }

            Label(item.mobileNumber?.nonBlank ?? "No mobile number", systemImage: "phone")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                bookingMetric("Project", item.projectName?.nonBlank ?? "-")
                bookingMetric("Plot", item.plotNo?.nonBlank ?? "-")
            }

            HStack {
                Text("Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(AppModuleFormatters.rupees(item.balanceAmount ?? 0))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func bookingMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 10))
    }
}

private struct CollectionSelectedBookingView: View {
    let item: PostSaleCaseSummary
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.clientName?.nonBlank ?? "Customer")
                        .font(.headline)
                    Text(item.bookingRefNo?.nonBlank ?? "Booking selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Change", action: onChange)
                    .font(.subheadline.weight(.semibold))
            }

            Text(
                [
                    item.projectName?.nonBlank,
                    item.plotNo?.nonBlank.map { "Plot \($0)" },
                    item.mobileNumber?.nonBlank
                ]
                .compactMap { $0 }
                .joined(separator: " · ")
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack {
                Text("Outstanding balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(AppModuleFormatters.rupees(item.balanceAmount ?? 0))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct CollectionSubmitSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let rectifyingCollection: CustomerCollectionRow?
    @State private var caseId = ""
    @State private var caseMatches: [PostSaleCaseSummary] = []
    @State private var selectedCase: PostSaleCaseSummary?
    @State private var amount = ""
    @State private var paymentMode: CollectionEntryPaymentMode = .upi
    @State private var reference = ""
    @State private var notes = ""
    @State private var proofFile: PostSalesUploadedFile?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isSearching = false
    @State private var isUploading = false
    @State private var showingFileImporter = false
    @State private var showingBookingSelection = false
    @State private var showingProofCamera = false
    @State private var proofImage: UIImage?
    @State private var hasPreparedForm = false
    let onSaved: () async -> Void

    private var amountValue: Double? {
        guard let value = Double(amount), value.isFinite, value > 0 else { return nil }
        return value
    }

    private var canSubmit: Bool {
        !isSubmitting
            && !isUploading
            && caseId.nonBlank != nil
            && amountValue != nil
            && reference.nonBlank != nil
    }

    private var openBookingsCacheKey: String {
        let staffId = authStore.viewer?.subject ?? authStore.currentSession?.user._id ?? "anonymous"
        return "postsales.collections.open-bookings.\(staffId)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    if let selectedCase {
                        CollectionSelectedBookingView(item: selectedCase) {
                            showingBookingSelection = true
                        }
                    } else if let rectifyingCollection {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rectifyingCollection.customerName?.nonBlank ?? "Existing booking")
                                .font(.headline)
                            Text(
                                [
                                    rectifyingCollection.bookingRefNo?.nonBlank,
                                    rectifyingCollection.projectName?.nonBlank,
                                    rectifyingCollection.plotNo?.nonBlank.map { "Plot \($0)" }
                                ]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            showingBookingSelection = true
                        } label: {
                            if isSearching {
                                Label("Loading bookings...", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label("Select Booking", systemImage: "rectangle.stack")
                            }
                        }
                        .disabled(isSearching || caseMatches.isEmpty)
                    }

                    if !isSearching && caseMatches.isEmpty && rectifyingCollection == nil {
                        Text("No open confirmed bookings are available for collection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Payment") {
                    TextField("Amount received", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("Payment Mode", selection: $paymentMode) {
                        ForEach(CollectionEntryPaymentMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    TextField("Transaction Reference", text: $reference)
                        .textInputAutocapitalization(.characters)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section("Payment Proof") {
                    HStack {
                        Button {
                            showingProofCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                        }
                        Spacer()
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label(proofFile == nil ? "Attach File" : "Replace File", systemImage: "paperclip")
                        }
                    }
                    if isUploading {
                        ProgressView("Uploading proof...")
                    }
                    if let proofFile {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(proofFile.fileName)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(proofFile.fileSize.formatted(.byteCount(style: .file)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                self.proofFile = nil
                            }
                        }
                    }

                    Text("PDF, JPG, PNG or WebP up to 10 MB. Accounts can review this before approval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(rectifyingCollection == nil ? "Payment Entry" : "Rectify Collection")
            .navigationBarTitleDisplayMode(.inline)
            .task { await prepareForm() }
            .onChange(of: caseId) { _, _ in saveDraftIfNeeded() }
            .onChange(of: amount) { _, _ in saveDraftIfNeeded() }
            .onChange(of: reference) { _, _ in saveDraftIfNeeded() }
            .onChange(of: notes) { _, _ in saveDraftIfNeeded() }
            .onChange(of: paymentMode) { _, _ in saveDraftIfNeeded() }
            .onChange(of: proofFile) { _, _ in saveDraftIfNeeded() }
            .onChange(of: proofImage) { _, image in
                guard let image else { return }
                Task { await uploadCameraProof(image) }
            }
            .sheet(isPresented: $showingBookingSelection) {
                CollectionBookingSelectionSheet(
                    cases: caseMatches,
                    selectedCaseId: selectedCase?.id ?? caseId
                ) { item in
                    selectedCase = item
                    caseId = item.id
                }
                .appLibraryNativeSheet([.medium, .large])
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.pdf, .jpeg, .png, .webP],
                allowsMultipleSelection: false
            ) { result in
                Task { await importProof(result) }
            }
            .fullScreenCover(isPresented: $showingProofCamera) {
                PunchCameraView(capturedImage: $proofImage)
                    .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Submitting..." : "Submit for Accounts") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
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
        amount = row.amount.map { String($0) } ?? ""
        paymentMode = CollectionEntryPaymentMode(rawValue: row.paymentMode ?? "") ?? .upi
        reference = row.transactionReference ?? ""
        notes = row.notes ?? row.verificationNotes ?? ""
    }

    @MainActor
    private func prepareForm() async {
        guard !hasPreparedForm else { return }
        hasPreparedForm = true
        if rectifyingCollection != nil {
            applyRectifyPrefill()
            return
        }
        restoreDraft()
        await loadOpenBookings()
    }

    @MainActor
    private func loadOpenBookings() async {
        if caseMatches.isEmpty,
           let cached = LocalCache.get(openBookingsCacheKey, as: [PostSaleCaseSummary].self) {
            caseMatches = cached
            if let restored = cached.first(where: { $0.id == caseId }) {
                selectedCase = restored
            }
        }
        guard let token = authStore.currentSession?.token else { return }
        isSearching = caseMatches.isEmpty
        defer { isSearching = false }
        do {
            caseMatches = try await PostSalesConvexAPIService.listOpenBookings(token: token)
            LocalCache.put(openBookingsCacheKey, caseMatches)
            if let restored = caseMatches.first(where: { $0.id == caseId }) {
                selectedCase = restored
            }
        } catch {
            if caseMatches.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func importProof(_ result: Result<[URL], Error>) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            guard let url = try result.get().first else { return }
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = values.fileSize ?? 0
            let allowedTypes: Set<UTType> = [.pdf, .jpeg, .png, .webP]
            guard let type = UTType(filenameExtension: url.pathExtension),
                  allowedTypes.contains(type)
            else {
                errorMessage = "Upload a PDF, JPG, PNG or WebP proof."
                return
            }
            guard fileSize <= 10 * 1024 * 1024 else {
                errorMessage = "Proof file must be 10 MB or smaller."
                return
            }
            isUploading = true
            defer { isUploading = false }
            proofFile = try await PostSalesStorageService.uploadFile(token: token, fileURL: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func uploadCameraProof(_ image: UIImage) async {
        guard let token = authStore.currentSession?.token,
              let data = image.jpegData(compressionQuality: 0.72) else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let storageId = try await PostSalesStorageService.uploadData(
                token: token,
                data: data,
                mimeType: "image/jpeg"
            )
            proofFile = PostSalesUploadedFile(
                storageId: storageId,
                fileName: "collection-proof.jpg",
                mimeType: "image/jpeg",
                fileSize: data.count
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submit() async {
        guard let token = authStore.currentSession?.token, let amountValue else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await PostSalesConvexAPIService.submitCollection(
                token: token,
                request: SubmitCollectionRequest(
                    cpVisitId: nil,
                    caseId: caseId.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: amountValue,
                    paymentMode: paymentMode.rawValue,
                    transactionReference: reference.nonBlank,
                    bankName: nil,
                    branchName: nil,
                    paymentInstrumentDate: nil,
                    proofStorageId: proofFile?.storageId,
                    proofFileName: proofFile?.fileName,
                    notes: notes.nonBlank
                )
            )
            clearDraft()
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let draftKey = "collection.form.draft.v1"

    private func saveDraftIfNeeded() {
        guard hasPreparedForm, rectifyingCollection == nil else { return }
        let draft = CollectionFormDraft(
            caseId: caseId,
            amount: amount,
            paymentMode: paymentMode.rawValue,
            reference: reference,
            notes: notes,
            proofFile: proofFile
        )
        guard !draft.isEmpty, let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: Self.draftKey)
    }

    private func restoreDraft() {
        guard let data = UserDefaults.standard.data(forKey: Self.draftKey),
              let draft = try? JSONDecoder().decode(CollectionFormDraft.self, from: data) else { return }
        caseId = draft.caseId
        amount = draft.amount
        paymentMode = CollectionEntryPaymentMode(rawValue: draft.paymentMode) ?? .upi
        reference = draft.reference
        notes = draft.notes
        proofFile = draft.proofFile
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
    }
}

private struct CollectionFormDraft: Codable {
    let caseId: String
    let amount: String
    let paymentMode: String
    let reference: String
    let notes: String
    let proofFile: PostSalesUploadedFile?

    var isEmpty: Bool {
        caseId.isEmpty && amount.isEmpty && reference.isEmpty && notes.isEmpty && proofFile == nil
    }
}

private struct RejectCollectionSheet: View {
    var title = "Reject Collection"
    var subtitle: String?
    @Binding var remarks: String
    let onSubmit: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                if let subtitle {
                    Section {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                    }
                }
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

/// Collector corrects a wrong amount on their own still-pending collection
/// before it reaches Accounts (mirrors Android's "Edit amount" dialog →
/// POST /api/postsales/collections/correct). Only the amount is editable here.
private struct EditCollectionAmountSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let collection: CustomerCollectionRow
    let onSaved: () async -> Void
    @State private var amountText: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(collection: CustomerCollectionRow, onSaved: @escaping () async -> Void) {
        self.collection = collection
        self.onSaved = onSaved
        let value = collection.amount ?? 0
        // Show a whole number without a trailing ".0" when the amount is integral.
        let initial = value == value.rounded() ? String(Int(value)) : String(value)
        _amountText = State(initialValue: value > 0 ? initial : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Correct the amount before it reaches Accounts.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                Section("Corrected Amount (₹)") {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Edit Collection Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving..." : "Save") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || (Double(amountText) ?? 0) <= 0)
                }
            }
            .alert("Collection", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func submit() async {
        guard let token = authStore.currentSession?.token else { return }
        guard let newAmount = Double(amountText), newAmount > 0 else {
            errorMessage = "Enter a valid amount greater than zero"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await PostSalesConvexAPIService.correctCollection(
                token: token,
                request: CorrectCollectionRequest(collectionId: collection.id, amount: newAmount)
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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

/// Per-case Loan Desk document sheet. Sales seeds the required-document
/// checklist straight from the tapped case (`documentsChecklist` labels +
/// any files already on the server), uploads into each slot, and submits
/// with the case's own caseId + applicantType — no free-text entry. Legal
/// roles (and Sales once a legal officer is assigned) open it read-only to
/// review and preview the uploaded files. Mirrors Android's
/// LoanDeskUploadBottomSheet + previewSlot.
private struct LoanCaseDocumentsSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let loanCase: LoanCaseRow
    let mode: LoanDeskMode
    let onSaved: () async -> Void

    @State private var slots: [LoanDocSlot] = []
    @State private var didBuildSlots = false
    @State private var importingSlotId: UUID?
    @State private var previewURL: URL?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isUploading = false

    // Sales can upload/replace until a legal officer is assigned. Everyone
    // else (and Sales post-assignment) views the checklist read-only.
    private var isEditable: Bool {
        mode == .sales && loanCase.legalAssignedName?.nonBlank == nil
    }

    // Mirrors Android's allCovered + anyFreshReady: every slot must have a
    // file (pre-existing or freshly uploaded) and at least one must be new.
    private var canSubmit: Bool {
        !isUploading
            && !slots.isEmpty
            && slots.allSatisfy { $0.storageId?.nonBlank != nil }
            && slots.contains { $0.isFresh }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Case") {
                    LabeledContent("Client", value: loanCase.displayTitle)
                    if let sub = [loanCase.projectName, loanCase.plotNo].compactMap({ $0?.nonBlank }).joined(separator: " · ").nonBlank {
                        LabeledContent("Project", value: sub)
                    }
                    LabeledContent("Amount", value: AppModuleFormatters.rupees(loanCase.displayAmount))
                    if let type = loanCase.applicantType?.nonBlank {
                        LabeledContent("Applicant Type", value: type.capitalized)
                    }
                }

                Section(isEditable ? "Required Documents" : "Documents") {
                    if slots.isEmpty {
                        Text("No documents are configured for this loan case.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach($slots) { $slot in
                        documentRow($slot)
                    }
                    if isUploading {
                        ProgressView("Uploading document...")
                    }
                }
            }
            .navigationTitle(isEditable ? "Submit Documents" : "Loan Documents")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !didBuildSlots else { return }
                didBuildSlots = true
                slots = LoanDocSlot.build(from: loanCase)
            }
            .fileImporter(
                isPresented: Binding(
                    get: { importingSlotId != nil },
                    set: { if !$0 { importingSlotId = nil } }
                ),
                allowedContentTypes: [.image, .pdf, .data],
                allowsMultipleSelection: false
            ) { result in
                Task { await importDocument(result) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditable ? "Cancel" : "Close") { dismiss() }
                }
                if isEditable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSubmitting ? "Saving..." : "Submit") {
                            Task { await submit() }
                        }
                        .disabled(isSubmitting || !canSubmit)
                    }
                }
            }
            .alert("Loan Desk", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: Binding(get: { previewURL.map(URLPreviewItem.init(url:)) }, set: { if $0 == nil { previewURL = nil } })) { item in
                StoragePreviewSheet(url: item.url)
                    .appLibraryNativeSheet([.medium, .large])
            }
        }
    }

    private func documentRow(_ slot: Binding<LoanDocSlot>) -> some View {
        let value = slot.wrappedValue
        return HStack(spacing: 12) {
            Image(systemName: value.storageId == nil ? "doc.badge.plus" : "doc.fill")
                .foregroundStyle(value.storageId == nil ? Color(hex: 0x667085) : Color(hex: 0x16A34A))
            VStack(alignment: .leading, spacing: 3) {
                Text(value.label)
                Text(value.fileName?.nonBlank ?? "No file selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if value.storageId?.nonBlank != nil {
                Button {
                    Task { await preview(value) }
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .tint(Color(hex: 0x0B61CA))
            }
            if isEditable {
                Button {
                    importingSlotId = value.id
                } label: {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @MainActor
    private func preview(_ slot: LoanDocSlot) async {
        guard let token = authStore.currentSession?.token,
              let storageId = slot.storageId?.nonBlank
        else { return }
        do {
            previewURL = try await PostSalesStorageService.getFileURL(token: token, storageId: storageId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importDocument(_ result: Result<[URL], Error>) async {
        guard let token = authStore.currentSession?.token,
              let slotId = importingSlotId
        else { return }
        do {
            guard let url = try result.get().first else { return }
            isUploading = true
            defer {
                isUploading = false
                importingSlotId = nil
            }
            guard let slotIndex = slots.firstIndex(where: { $0.id == slotId }) else { return }
            let uploaded = try await PostSalesStorageService.uploadFile(token: token, fileURL: url)
            try await PostSalesConvexAPIService.uploadLoanDocument(
                token: token,
                request: UploadLoanDocumentRequest(
                    loanCaseId: loanCase.id,
                    index: slotIndex,
                    storageId: uploaded.storageId,
                    fileName: uploaded.fileName
                )
            )
            slots[slotIndex].storageId = uploaded.storageId
            slots[slotIndex].fileName = uploaded.fileName
            slots[slotIndex].isFresh = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submit() async {
        guard let token = authStore.currentSession?.token else { return }
        guard let caseId = loanCase.caseId?.nonBlank else {
            errorMessage = "This case has no booking linked."
            return
        }
        // Only freshly uploaded files are sent; the server keeps previously
        // approved documents authoritative (mirrors Android readyUploadsForSubmit).
        let documents = slots.compactMap { slot -> SubmitLoanDocument? in
            guard slot.isFresh, let storageId = slot.storageId?.nonBlank else { return nil }
            return SubmitLoanDocument(label: slot.label, storageId: storageId, fileName: slot.fileName)
        }
        guard !documents.isEmpty else {
            errorMessage = "Upload at least one document to submit."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await PostSalesConvexAPIService.submitLoanRequest(
                token: token,
                request: SubmitLoanDeskRequest(
                    caseId: caseId,
                    applicantType: loanCase.applicantType?.nonBlank ?? "salaried",
                    requestedAmount: loanCase.requestedAmount,
                    documents: documents
                )
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LoanDocSlot: Identifiable, Equatable {
    let id = UUID()
    let label: String
    var storageId: String?
    var fileName: String?
    // True when the file was picked in this session (vs. seeded from the
    // server) — only fresh uploads go in the submit payload.
    var isFresh: Bool = false

    private static let defaultLabels = ["PAN Card", "Aadhaar Card", "Bank Statement", "Pay Slip"]

    static func build(from loanCase: LoanCaseRow) -> [LoanDocSlot] {
        let checklist = loanCase.documentsChecklist ?? []
        if checklist.isEmpty {
            return defaultLabels.map { LoanDocSlot(label: $0) }
        }
        return checklist.map { doc in
            LoanDocSlot(
                label: doc.label,
                storageId: doc.storageId?.nonBlank,
                fileName: doc.fileName?.nonBlank
            )
        }
    }
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

    var isPendingVerification: Bool {
        let normalized = (verificationStatus ?? "pending_accounts").normalizedStatusToken
        return ["pending", "pending_accounts", "clarification_requested"].contains(normalized)
    }

    var normalizedPaymentCategory: String {
        (customerPaymentCategory ?? "").replacingOccurrences(of: "_", with: " ").lowercased()
    }

    /// True when the collector corrected their own entry while still pending
    /// Accounts — drives the "Edited" tag (mirrors Android `collectorEditedAt`).
    var isEdited: Bool { collectorEditedAt?.nonBlank != nil }

    var androidBookingLabel: String {
        let site = projectName?.nonBlank
        let plot = plotNo?.nonBlank
        let client = customerName?.nonBlank
        if let site, let plot { return "\(site) - Plot \(plot)" }
        if let site { return site }
        if let client, let plot { return "\(client) - Plot \(plot)" }
        if let client { return client }
        if let bookingRefNo = bookingRefNo?.nonBlank { return bookingRefNo }
        if let bookingId = bookingId?.nonBlank { return "Booking \(String(bookingId.suffix(6)))" }
        return collectionRefNo?.nonBlank ?? "Collection"
    }

    var androidStatusLabel: String {
        switch (verificationStatus ?? "").normalizedStatusToken {
        case "approved", "verified":
            return "Approved"
        case "rejected":
            return "Rejected"
        default:
            return "Pending"
        }
    }

    var humanPaymentMode: String {
        switch (paymentMode ?? "").normalizedStatusToken {
        case "cash": return "Cash"
        case "upi": return "UPI"
        case "neft": return "NEFT"
        case "rtgs": return "RTGS"
        case "cheque": return "Cheque"
        case "dd": return "DD"
        case "bank": return "Bank Transfer"
        default:
            guard let paymentMode = paymentMode?.nonBlank else { return "-" }
            return paymentMode.prefix(1).uppercased() + String(paymentMode.dropFirst())
        }
    }

    func matchesCollectionDate(_ selectedDate: Date) -> Bool {
        let calendar = Calendar.current
        return collectionFilterDates.contains { calendar.isDate($0, inSameDayAs: selectedDate) }
    }

    func matchesCollectionDateRange(from: Date, to: Date) -> Bool {
        let calendar = Calendar.current
        let lowerBound = calendar.startOfDay(for: min(from, to))
        let upperDay = calendar.startOfDay(for: max(from, to))
        let upperBound = calendar.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay
        return collectionFilterDates.contains { $0 >= lowerBound && $0 < upperBound }
    }

    private var collectionFilterDates: [Date] {
        [collectionDate, createdAt].compactMap { Self.parseCollectionDate($0) }
    }

    var androidCollectionDate: String? {
        let raw = createdAt?.nonBlank ?? collectionDate?.nonBlank
        guard let raw else { return nil }
        let parsed = Self.parseCollectionDate(raw)
        guard let parsed else { return raw }
        return Self.displayDateFormatter.string(from: parsed)
    }

    private static func parseCollectionDate(_ raw: String?) -> Date? {
        guard let raw = raw?.nonBlank else { return nil }
        return isoMillisFormatter.date(from: raw)
            ?? isoNoMillisFormatter.date(from: raw)
            ?? dateOnlyFormatter.date(from: raw)
            ?? ISO8601DateFormatter().date(from: raw)
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd, yyyy • hh:mm a"
        return formatter
    }()

    private static let isoMillisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    private static let isoNoMillisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension String {
    var normalizedStatusToken: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
