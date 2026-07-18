import SwiftUI

struct FinesDeductionsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var fines: [ConvexFineDeduction] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFine: ConvexFineDeduction?
    @State private var showingCreateFine = false

    private var canViewAll: Bool {
        authStore.hasPermission("fines.view")
    }

    private var canManage: Bool {
        authStore.hasPermission("fines.manage")
    }

    private var filteredFines: [ConvexFineDeduction] {
        guard canViewAll, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fines
        }
        return fines.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || ($0.employeeId ?? "").localizedCaseInsensitiveContains(searchText)
                || $0.displayDepartment.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if canViewAll {
                        searchField
                            .padding(.bottom, 4)
                    }

                    if isLoading && fines.isEmpty {
                        fineSkeletons
                    } else if filteredFines.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 90)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredFines) { fine in
                                FineDeductionCard(fine: fine) {
                                    selectedFine = fine
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .refreshable { await loadFines() }
        }
        .background(Color(hex: 0xF5F6FA).ignoresSafeArea())
        .navigationTitle("Fines & Deductions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateFine = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .accessibilityLabel("Create Fine")
                }
            }
        }
        .task { await loadFines() }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .sheet(item: $selectedFine) { fine in
            FineDeductionDetailSheet(fine: fine)
                .appLibraryNativeSheet([.medium, .large])
        }
        .sheet(isPresented: $showingCreateFine) {
            CreateFineDeductionSheet {
                await loadFines()
            }
            .appLibraryNativeSheet([.height(720), .large])
            .presentationBackground(Color.white)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 34, height: 34)
                        .background(Color(hex: 0xEEF6FF), in: Circle())
                }
                .buttonStyle(.plain)

                Text("Fines & Deductions")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1D2939))
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 46)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.white)

            Divider()
                .background(Color(hex: 0xE4E7EC))
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            TextField("Search Employee", text: $searchText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: 0x1D2939))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        }
    }

    private var fineSkeletons: some View {
        VStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .frame(height: 86)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 14) {
                            Circle().fill(Color(hex: 0xEEF2F6)).frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xEEF2F6)).frame(width: 120, height: 14)
                                RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xEEF2F6)).frame(width: 170, height: 10)
                            }
                            Spacer()
                            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xEEF2F6)).frame(width: 58, height: 16)
                        }
                        .padding(16)
                    }
                    .redacted(reason: .placeholder)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color(hex: 0x98A2B3))
                .frame(width: 78, height: 78)
                .background(Color.white, in: Circle())

            Text("No Fines Recorded")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x1D2939))

            Text(canViewAll ? "Search another name or add a new fine." : "Your active fines and deductions will show here.")
                .font(.system(size: 13, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x98A2B3))
                .padding(.horizontal, 24)
        }
    }

    @MainActor
    private func loadFines() async {
        guard let token = authStore.currentSession?.token, !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            fines = canViewAll
                ? try await HRConvexAPIService.listFines(token: token, status: "active")
                : try await HRConvexAPIService.listMyFines(token: token)
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

private struct FineDeductionCard: View {
    let fine: ConvexFineDeduction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                FineAvatar(name: fine.displayName, urlString: fine.staffPhotoUrl, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(fine.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1D2939))
                        .lineLimit(1)

                    Text("\(fine.displayDepartment)\n\(fine.displayType)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineSpacing(2)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "indianrupeesign.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                        Text(AppModuleFormatters.rupees(fine.amount ?? 0))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1D2939))
                    }

                    Text(fine.displayStatus)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x22C55E))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Color(hex: 0xECFDF3), in: Capsule())

                    Text(fine.displayDate)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct CreateFineDeductionSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let onCreated: () async -> Void

    @State private var staff: [ConvexStaffListItem] = []
    @State private var selectedStaff: ConvexStaffListItem?
    @State private var showEmployeePicker = false
    @State private var fineType = ""
    @State private var amount = ""
    @State private var notes = ""
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var selectedPhotoData: Data?
    @State private var isLoadingStaff = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let years = Array((Calendar.current.component(.year, from: Date()) - 1)...(Calendar.current.component(.year, from: Date()) + 1))

    private var canSubmit: Bool {
        selectedStaff?.employeeId?.nonBlank != nil
            && fineType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && parsedAmount > 0
            && !isSubmitting
    }

    private var parsedAmount: Double {
        Double(amount.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            formContent
        }
        .background(Color.white)
        .task { await loadStaff() }
        .sheet(isPresented: $showEmployeePicker) {
            employeePickerSheet
                .appLibraryNativeSheet([.large])
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    private var formContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Create Fine")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .padding(.bottom, 10)

                    Text("Information about fine details")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .padding(.bottom, 2)

                    Button {
                        Task { await openEmployeePicker() }
                    } label: {
                        CreateFineFieldShell(icon: "person.circle", chevron: true) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Employee *")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x344054))
                                Text(selectedStaff?.displayName ?? "Select Employee")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(selectedStaff == nil ? Color(hex: 0x98A2B3) : Color(hex: 0x101828))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if isLoadingStaff {
                                ProgressView()
                                    .tint(Color(hex: 0x0B61CA))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    textField(title: "Fine Type *", placeholder: "Enter fine type", icon: "doc.text", text: $fineType)

                    textField(title: "Amount *", placeholder: "Enter amount", icon: "indianrupeesign.circle", text: $amount, keyboard: .decimalPad)

                    HStack(spacing: 12) {
                        menuField(title: "Month", value: monthName(month)) {
                            ForEach(1...12, id: \.self) { value in
                                Button(monthName(value)) {
                                    month = value
                                }
                            }
                        }
                        menuField(title: "Year", value: String(year)) {
                            ForEach(years, id: \.self) { value in
                                Button(String(value)) { year = value }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x344054))

                        TextEditor(text: $notes)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color(hex: 0x101828))
                            .frame(minHeight: 104)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color(hex: 0xE4E7EC), lineWidth: 1)
                            }
                    }

                    CameraFirstPhotoPicker(maxSelectionCount: 1, isDisabled: isSubmitting) { data in
                        selectedPhotoData = data.first
                    } label: {
                        CreateFineFieldShell(icon: selectedPhotoData == nil ? "photo" : "checkmark.circle.fill", chevron: true) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Photo")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x344054))
                                Text(selectedPhotoData == nil ? "Upload fine photo" : "Photo selected")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(selectedPhotoData == nil ? Color(hex: 0x667085) : Color(hex: 0x16A34A))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }

            Button {
                Task { await submitFine() }
            } label: {
                HStack(spacing: 10) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSubmitting ? "Creating..." : "Create It")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: canSubmit ? [Color(hex: 0x18D20B), Color(hex: 0x29A800)] : [Color(hex: 0xD0D5DD), Color(hex: 0xD0D5DD)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .background(Color.white)
        }
    }

    @ViewBuilder
    private var employeePickerSheet: some View {
        if staff.isEmpty && isLoadingStaff {
            NavigationStack {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(Color(hex: 0x0B61CA))
                    Text("Loading employees...")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Select Employee")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showEmployeePicker = false }
                    }
                }
            }
        } else {
            NativeSearchableSelectionSheet(
                title: "Select Employee",
                prompt: "Search employees",
                items: staff,
                selectedId: selectedStaff?.id,
                searchText: { item in
                    [
                        item.displayName,
                        item.employeeId,
                        item.department,
                        item.designation
                    ]
                    .compactMap { $0?.nonBlank }
                    .joined(separator: " ")
                },
                rowContent: { item, isSelected in
                    HStack(spacing: 12) {
                        Text(item.initials)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .frame(width: 42, height: 42)
                            .background(Color(hex: 0xEEF8FF), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x101828))
                                .lineLimit(1)

                            Text([item.employeeId, item.department, item.designation].compactMap { $0?.nonBlank }.joined(separator: " · "))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: 0x667085))
                                .lineLimit(1)
                        }

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x0B61CA))
                        }
                    }
                    .padding(.vertical, 4)
                },
                onSelect: { selectedStaff = $0 }
            )
        }
    }

    private func textField(
        title: String,
        placeholder: String,
        icon: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x344054))
            CreateFineFieldShell(icon: icon) {
                TextField(placeholder, text: text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
            }
        }
    }

    private func menuField<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x344054))
            Menu {
                content()
            } label: {
                CreateFineFieldShell(icon: "calendar", chevron: true) {
                    Text(value)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @MainActor
    private func loadStaff(force: Bool = false) async {
        guard (force || staff.isEmpty), let token = authStore.currentSession?.token, !token.isEmpty else { return }
        isLoadingStaff = true
        defer { isLoadingStaff = false }
        do {
            var loadedStaff = try await HRConvexAPIService.listAllStaff(token: token, status: "active")
            if loadedStaff.isEmpty {
                loadedStaff = try await HRConvexAPIService.listAllStaff(token: token)
            }
            if loadedStaff.isEmpty {
                let page = try await HRConvexAPIService.getStaffPaginated(token: token, numItems: 100, status: "active")
                loadedStaff = page.page
            }
            staff = loadedStaff.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func openEmployeePicker() async {
        if staff.isEmpty {
            await loadStaff(force: true)
        }
        guard !staff.isEmpty else {
            errorMessage = "No employees found. Please try again."
            return
        }
        showEmployeePicker = true
    }

    @MainActor
    private func submitFine() async {
        guard let token = authStore.currentSession?.token, !token.isEmpty else { return }
        guard let employeeId = selectedStaff?.employeeId?.nonBlank else {
            errorMessage = "Please select an employee"
            return
        }
        let cleanFineType = fineType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanFineType.isEmpty else {
            errorMessage = "Please enter fine type"
            return
        }
        guard parsedAmount > 0 else {
            errorMessage = "Please enter a valid amount"
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var photoId: String?
            if let selectedPhotoData {
                photoId = try await HRConvexAPIService.uploadPhoto(token: token, imageData: selectedPhotoData)
            }
            _ = try await HRConvexAPIService.createFine(
                token: token,
                employeeId: employeeId,
                amount: parsedAmount,
                month: month,
                year: year,
                customTypeName: cleanFineType,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                photoStorageId: photoId,
                photoFileName: photoId == nil ? nil : "fine_photo.jpg"
            )
            await onCreated()
            dismiss()
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func monthName(_ value: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        guard symbols.indices.contains(value - 1) else { return String(value) }
        return symbols[value - 1]
    }
}

private struct CreateFineFieldShell<Content: View>: View {
    let icon: String
    var chevron = false
    let content: () -> Content

    init(icon: String, chevron: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.chevron = chevron
        self.content = content
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: 0x667085))
                .frame(width: 24)

            content()

            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x667085))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xE4E7EC), lineWidth: 1)
        }
    }
}

private struct FineDeductionDetailSheet: View {
    let fine: ConvexFineDeduction

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(fine.displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))

                Text(detailMeta)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .padding(.top, 4)

                finePhoto
                    .padding(.top, 16)

                Text("Reason")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x344054))
                    .padding(.top, 18)

                Text(fine.notes?.nonBlank ?? "No reason provided")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(hex: 0x475467))
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(Color.white)
    }

    private var detailMeta: String {
        [
            fine.displayType,
            AppModuleFormatters.rupees(fine.amount ?? 0),
            fine.displayStatus,
            fine.displayDate
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "  -  ")
    }

    @ViewBuilder
    private var finePhoto: some View {
        if let url = resolvedURL(fine.photoUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    noPhoto("Could not load picture")
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
            }
        } else {
            noPhoto("No picture attached")
        }
    }

    private func noPhoto(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(hex: 0x9CA3AF))
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
            }
    }
}

private struct FineAvatar: View {
    let name: String
    let urlString: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = resolvedURL(urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold))
            .foregroundStyle(Color(hex: 0x0B61CA))
            .frame(width: size, height: size)
            .background(Color(hex: 0xEEF8FF), in: Circle())
    }

    private var initials: String {
        let pieces = name
            .split(separator: " ")
            .compactMap(\.first)
        let text = String(pieces.prefix(2)).uppercased()
        return text.isEmpty ? "S" : text
    }
}

private func resolvedURL(_ value: String?) -> URL? {
    guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty,
          raw != "null",
          raw != "undefined"
    else { return nil }

    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
        return URL(string: raw)
    }
    if raw.hasPrefix("/") {
        return URL(string: "\(AppConfig.baseURL)\(raw)")
    }
    return URL(string: raw)
}

#Preview {
    FinesDeductionsView()
        .environment(AuthStore())
}
