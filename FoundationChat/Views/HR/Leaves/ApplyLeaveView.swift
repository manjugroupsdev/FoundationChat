import SwiftUI

private struct LeaveCategoryOption: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let backendCode: String
    let balanceTracked: Bool
    let requiresReasonPrefix: Bool

    // Non-half-day categories submit their own backend code. Half-day is a
    // pseudo-category with no balance of its own; the real base leave type it
    // books against is resolved from the available list (see
    // ApplyLeaveView.halfDayBaseType), so this fallback is only used if that
    // resolution ever fails. Mirrors Android's halfDayBaseType() fallback of
    // "unpaid" — NOT "casual", which would silently drain the casual balance.
    var submitCode: String {
        backendCode == "half_day" ? "unpaid" : backendCode
    }

    static let defaultOptions = options(from: ["unpaid", "compensatory", "half_day"])

    static func options(from backendTypes: [String]) -> [LeaveCategoryOption] {
        let normalizedTypes = backendTypes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        var seenIds = Set<String>()
        var result: [LeaveCategoryOption] = []

        for type in normalizedTypes {
            let option = LeaveCategoryOption(
                id: type,
                label: prettyLabel(for: type),
                backendCode: type,
                balanceTracked: balanceTracked(for: type),
                requiresReasonPrefix: type == "half_day"
            )
            if seenIds.insert(type).inserted {
                result.append(option)
            }
        }

        return result.isEmpty ? defaultOptions : result
    }

    private static func balanceTracked(for value: String) -> Bool {
        switch value {
        case "unpaid":
            return false
        default:
            return true
        }
    }

    private static func prettyLabel(for value: String) -> String {
        switch value {
        case "casual": return "Casual Leave"
        case "sick": return "Sick Leave"
        case "earned": return "Earned Leave"
        case "unpaid": return "Unpaid Leave"
        case "compensatory": return "Compensatory Leave"
        case "half_day": return "Half Day Leave"
        default:
            let base = value
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { part in
                    part.prefix(1).uppercased() + part.dropFirst().lowercased()
                }
                .joined(separator: " ")
            return base.localizedCaseInsensitiveContains("leave") ? base : "\(base) Leave"
        }
    }
}

struct ApplyLeaveView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var leaveTypes = LeaveCategoryOption.defaultOptions
    @State private var selectedLeaveCategory = LeaveCategoryOption.defaultOptions[0]
    @State private var fromDate: Date?
    @State private var toDate: Date?
    @State private var reason = ""
    @State private var selectedHalfDaySession = "Morning"
    @State private var compOffCredits: [ConvexCompOffCredit] = []
    @State private var selectedCompOffCredit: ConvexCompOffCredit?
    @State private var compOffCreditsLoaded = false
    @State private var isLoadingCompOffCredits = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showCategorySheet = false
    @State private var showCompOffCreditSheet = false
    @State private var showDurationSheet = false
    @State private var showSubmitConfirmation = false
    @FocusState private var isReasonFocused: Bool

    var onApplied: (() -> Void)?

    private var canSubmit: Bool {
        if selectedLeaveCategory.backendCode == "compensatory" {
            return selectedCompOffCredit != nil && fromDate != nil && !isSubmitting
        }
        return fromDate != nil && toDate != nil && !isSubmitting
    }

    private var selectedLeaveTypeLabel: String {
        selectedLeaveCategory.label
    }

    private var durationLabel: String {
        guard let fromDate, let toDate else { return "Select Duration" }
        if Calendar.current.isDate(fromDate, inSameDayAs: toDate) {
            return Self.labelDateFormatter.string(from: fromDate)
        }
        return "\(Self.labelDateFormatter.string(from: fromDate)) - \(Self.labelDateFormatter.string(from: toDate))"
    }

    private var isCompOff: Bool {
        selectedLeaveCategory.backendCode == "compensatory"
    }

    /// The real leave type a Half Day is booked against: the first available
    /// base type excluding the half_day / compensatory pseudo-categories,
    /// falling back to "unpaid". Mirrors Android `halfDayBaseType()`.
    private var halfDayBaseType: String {
        leaveTypes.first {
            $0.backendCode != "half_day" && $0.backendCode != "compensatory"
        }?.backendCode ?? "unpaid"
    }

    private var compOffCreditLabel: String {
        guard let selectedCompOffCredit else { return "Select Credit" }
        return Self.compOffCreditLabel(selectedCompOffCredit)
    }

    private var compOffCreditsCacheKey: String? {
        guard let user = authStore.currentSession?.user else { return nil }
        let staff = user.staffId?.nonBlank ?? user._id
        return "leaves.compoff.credits.\(staff)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Fill Leave Information")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))

                    Text("Information about leave details")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .padding(.top, 2)

                    fieldLabel("Leave Category")
                        .padding(.top, 16)
                    applyField(icon: "doc.text", value: selectedLeaveTypeLabel, action: { showCategorySheet = true })

                    if isCompOff {
                        fieldLabel("Comp Off Credit")
                            .padding(.top, 16)
                        applyField(
                            icon: "checkmark.seal",
                            value: isLoadingCompOffCredits ? "Loading credits..." : compOffCreditLabel,
                            action: { showCompOffCreditPicker() }
                        )
                        .disabled(compOffCredits.isEmpty && compOffCreditsLoaded)
                        .opacity((compOffCredits.isEmpty && compOffCreditsLoaded) ? 0.55 : 1)

                        if compOffCreditsLoaded && compOffCredits.isEmpty {
                            Text("No comp-off balance available. You earn 1 comp-off credit by working a full day on your weekly-off or a holiday.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: 0x667085))
                                .padding(.top, 8)
                        }
                    }

                    fieldLabel(isCompOff ? "Comp Off Date" : "Leave Duration")
                        .padding(.top, 16)
                    applyField(icon: "calendar", value: durationLabel, action: { showDurationPicker() })

                    if selectedLeaveCategory.backendCode == "half_day" {
                        halfDaySessionPicker
                            .padding(.top, 14)
                    }

                    if !isCompOff {
                        fieldLabel("Leave Description")
                            .padding(.top, 16)
                        TextField("Enter Leave Description", text: $reason, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: 0x101828))
                            .lineLimit(4...6)
                            .focused($isReasonFocused)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 90, alignment: .topLeading)
                            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
                            }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xB42318))
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)

            submitButton
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
                .background(Color.white)
        }
        .background(Color.white)
        .appCompactSheetCTAContainer()
        .task { await loadLeaveTypes() }
        .onDisappear {
            dismissKeyboard()
        }
        .sheet(isPresented: $showCategorySheet) {
            LeaveCategorySheet(
                leaveTypes: leaveTypes,
                selectedType: selectedLeaveCategory,
                onClose: { showCategorySheet = false },
                onSubmit: { category in
                    applySelectedCategory(category)
                    showCategorySheet = false
                }
            )
            .appLibraryNativeSheet([.height(categorySheetHeight)])
        }
        .sheet(isPresented: $showCompOffCreditSheet) {
            CompOffCreditSheet(
                credits: compOffCredits,
                selectedCredit: selectedCompOffCredit,
                onClose: { showCompOffCreditSheet = false },
                onSubmit: { credit in
                    let changed = credit.id != selectedCompOffCredit?.id
                    selectedCompOffCredit = credit
                    if changed {
                        fromDate = nil
                        toDate = nil
                    }
                    errorMessage = nil
                    showCompOffCreditSheet = false
                }
            )
            .appLibraryNativeSheet([.height(compOffSheetHeight)])
        }
        .sheet(isPresented: $showDurationSheet) {
            LeaveDurationSheet(
                title: isCompOff ? "Comp Off Date" : "Leave Duration",
                subtitle: isCompOff ? "Select the day to take" : "Select Leave Duration",
                initialFromDate: fromDate,
                initialToDate: toDate,
                singleSelection: selectedLeaveCategory.backendCode == "half_day" || isCompOff,
                lockedMonthDate: isCompOff ? selectedCompOffCredit?.earnedDate.flatMap { Self.apiDateFormatter.date(from: $0) } : nil,
                disabledDate: isCompOff ? selectedCompOffCredit?.earnedDate.flatMap { Self.apiDateFormatter.date(from: $0) } : nil,
                onClose: { showDurationSheet = false },
                onSubmit: { pickedFrom, pickedTo in
                    fromDate = min(pickedFrom, pickedTo)
                    toDate = (selectedLeaveCategory.backendCode == "half_day" || isCompOff) ? min(pickedFrom, pickedTo) : max(pickedFrom, pickedTo)
                    showDurationSheet = false
                }
            )
            .appLibraryNativeSheet([.height(430)])
        }
        .sheet(isPresented: $showSubmitConfirmation) {
            SubmitLeaveConfirmSheet(
                isSubmitting: isSubmitting,
                onCancel: { showSubmitConfirmation = false },
                onSubmit: { submit() }
            )
            .appLibraryNativeSheet([.height(248)])
        }
        .appFormActivity()
    }

    private var submitBackground: some ShapeStyle {
        canSubmit
            ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)], startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(Color(hex: 0xD0D5DD))
    }

    private var submitButton: some View {
        Button {
            promptSubmitConfirmation()
        } label: {
            ZStack {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Submit Now")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(submitBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var halfDaySessionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Half Day Session")
                .padding(.bottom, 0)
            HStack(spacing: 10) {
                halfDaySessionButton("Morning")
                halfDaySessionButton("Afternoon")
            }
        }
    }

    private func halfDaySessionButton(_ title: String) -> some View {
        Button {
            selectedHalfDaySession = title
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selectedHalfDaySession == title ? Color(hex: 0x1D4ED8) : Color(hex: 0x344054))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    selectedHalfDaySession == title ? Color(hex: 0xEAF2FF) : Color(hex: 0xF8FAFC),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selectedHalfDaySession == title ? Color(hex: 0x7DB2FF) : Color(hex: 0xEAECF0), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var categorySheetHeight: CGFloat {
        CGFloat(168 + max(leaveTypes.count, 1) * 54)
    }

    private var compOffSheetHeight: CGFloat {
        CGFloat(min(560, 168 + max(compOffCredits.count, 1) * 64))
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(hex: 0x344054))
            .padding(.bottom, 6)
    }

    private func applyField(icon: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(width: 20)
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(value.hasPrefix("Select") ? Color(hex: 0x9CA3AF) : Color(hex: 0x101828))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func promptSubmitConfirmation() {
        dismissKeyboard()
        if isCompOff {
            guard selectedCompOffCredit != nil else {
                errorMessage = "Select a comp-off credit"
                return
            }
            guard fromDate != nil else {
                errorMessage = "Select the day to take"
                return
            }
            errorMessage = nil
            showSubmitConfirmation = true
            return
        }
        guard let fromDate, let toDate else {
            errorMessage = "Select leave duration"
            return
        }
        guard toDate >= fromDate else {
            errorMessage = "To date must be on or after from date"
            return
        }
        errorMessage = nil
        showSubmitConfirmation = true
    }

    private func submit() {
        dismissKeyboard()
        guard let token = authStore.currentSession?.token else { return }
        guard let fromDate, let toDate else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                if isCompOff {
                    guard let selectedCompOffCredit else { return }
                    _ = try await HRConvexAPIService.applyCompOff(
                        token: token,
                        creditId: selectedCompOffCredit.id,
                        date: Self.apiDateFormatter.string(from: fromDate)
                    )
                } else {
                    _ = try await HRConvexAPIService.applyLeave(
                        token: token,
                        leaveType: selectedLeaveCategory.backendCode == "half_day" ? halfDayBaseType : selectedLeaveCategory.submitCode,
                        fromDate: Self.apiDateFormatter.string(from: min(fromDate, toDate)),
                        toDate: Self.apiDateFormatter.string(from: max(fromDate, toDate)),
                        reason: submitReason,
                        isHalfDay: selectedLeaveCategory.backendCode == "half_day" ? true : nil,
                        halfDaySession: selectedLeaveCategory.backendCode == "half_day" ? selectedHalfDaySession.lowercased() : nil,
                        halfDayType: selectedLeaveCategory.backendCode == "half_day" ? selectedHalfDaySession.lowercased() : nil
                    )
                }
                onApplied?()
                dismiss()
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                showSubmitConfirmation = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadLeaveTypes() async {
        leaveTypes = LeaveCategoryOption.defaultOptions
        guard leaveTypes.contains(selectedLeaveCategory) else {
            selectedLeaveCategory = leaveTypes[0]
            return
        }
    }

    private func applySelectedCategory(_ category: LeaveCategoryOption) {
        let previousCode = selectedLeaveCategory.backendCode
        selectedLeaveCategory = category
        errorMessage = nil

        if category.backendCode == "half_day", let fromDate {
            toDate = fromDate
        }

        if category.backendCode == "compensatory" {
            if previousCode != "compensatory" {
                fromDate = nil
                toDate = nil
                reason = ""
            }
            Task { await loadCompOffCreditsIfNeeded() }
        }
    }

    private func showCompOffCreditPicker() {
        guard compOffCreditsLoaded else {
            Task { await loadCompOffCreditsIfNeeded(openWhenLoaded: true) }
            return
        }
        guard !compOffCredits.isEmpty else {
            errorMessage = "No comp-off credits available"
            return
        }
        showCompOffCreditSheet = true
    }

    private func showDurationPicker() {
        if isCompOff && selectedCompOffCredit == nil {
            errorMessage = "Select a comp-off credit first"
            return
        }
        errorMessage = nil
        showDurationSheet = true
    }

    @MainActor
    private func loadCompOffCreditsIfNeeded(openWhenLoaded: Bool = false) async {
        guard !compOffCreditsLoaded else {
            if openWhenLoaded, !compOffCredits.isEmpty { showCompOffCreditSheet = true }
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        if let cacheKey = compOffCreditsCacheKey,
           let cached = LocalCache.get(cacheKey, as: [ConvexCompOffCredit].self) {
            compOffCredits = cached
        }
        isLoadingCompOffCredits = true
        defer {
            isLoadingCompOffCredits = false
            compOffCreditsLoaded = true
        }
        do {
            compOffCredits = try await HRConvexAPIService.getCompOffCredits(token: token)
            if let cacheKey = compOffCreditsCacheKey {
                LocalCache.put(cacheKey, compOffCredits)
            }
            if openWhenLoaded, !compOffCredits.isEmpty {
                showCompOffCreditSheet = true
            } else if openWhenLoaded {
                errorMessage = "No comp-off credits available"
            }
        } catch {
            if openWhenLoaded {
                errorMessage = compOffCredits.isEmpty ? error.localizedDescription : nil
            }
        }
    }

    private func dismissKeyboard() {
        isReasonFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var submitReason: String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedLeaveCategory.backendCode == "half_day" else { return trimmed }
        return "[\(selectedHalfDaySession)] \(trimmed)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    fileprivate static let labelDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()

    fileprivate static func compOffCreditLabel(_ credit: ConvexCompOffCredit) -> String {
        let earned = credit.earnedDate
            .flatMap(apiDateFormatter.date(from:))
            .map(labelDateFormatter.string(from:)) ?? "Credit"
        let expires = credit.expiresAt
            .flatMap(apiDateFormatter.date(from:))
            .map(labelDateFormatter.string(from:))
        if let expires {
            return "Earned \(earned) · valid till \(expires)"
        }
        return "Earned \(earned)"
    }
}

private struct LeaveCategorySheet: View {
    let leaveTypes: [LeaveCategoryOption]
    let selectedType: LeaveCategoryOption
    let onClose: () -> Void
    let onSubmit: (LeaveCategoryOption) -> Void

    @State private var draftType: LeaveCategoryOption

    init(leaveTypes: [LeaveCategoryOption], selectedType: LeaveCategoryOption, onClose: @escaping () -> Void, onSubmit: @escaping (LeaveCategoryOption) -> Void) {
        self.leaveTypes = leaveTypes
        self.selectedType = selectedType
        self.onClose = onClose
        self.onSubmit = onSubmit
        _draftType = State(initialValue: selectedType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHandle

            Text("Leave Category")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
            Text("Select Leave category")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .padding(.top, 2)

            VStack(spacing: 8) {
                ForEach(leaveTypes) { type in
                    Button {
                        draftType = type
                    } label: {
                        HStack {
                            Text(type.label)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(hex: 0x101828))
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                            Spacer()
                            Image(systemName: draftType == type ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(draftType == type ? Color(hex: 0x1BCA0B) : Color(hex: 0x98A2B3))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(draftType == type ? Color(hex: 0xEAF8E8) : Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(draftType == type ? Color(hex: 0x1BCA0B).opacity(0.35) : Color(hex: 0xEAECF0), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)

            HStack(spacing: 12) {
                outlineButton("Close Message", action: onClose)
                filledButton("Submit") { onSubmit(draftType) }
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background(Color.white)
        .appCompactSheetCTAContainer()
    }

    private var sheetHandle: some View {
        EmptyView()
    }
}

private struct CompOffCreditSheet: View {
    let credits: [ConvexCompOffCredit]
    let selectedCredit: ConvexCompOffCredit?
    let onClose: () -> Void
    let onSubmit: (ConvexCompOffCredit) -> Void

    @State private var draftCredit: ConvexCompOffCredit?

    init(
        credits: [ConvexCompOffCredit],
        selectedCredit: ConvexCompOffCredit?,
        onClose: @escaping () -> Void,
        onSubmit: @escaping (ConvexCompOffCredit) -> Void
    ) {
        self.credits = credits
        self.selectedCredit = selectedCredit
        self.onClose = onClose
        self.onSubmit = onSubmit
        _draftCredit = State(initialValue: selectedCredit ?? credits.first)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHandle

            Text("Comp Off Credit")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
            Text("Select a credit to spend")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .padding(.top, 2)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(credits) { credit in
                        Button {
                            draftCredit = credit
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(draftCredit?.id == credit.id ? Color(hex: 0xEAF8E8) : Color(hex: 0xF2F4F7))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "checkmark.seal")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(draftCredit?.id == credit.id ? Color(hex: 0x1BCA0B) : Color(hex: 0x667085))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Self.creditTitle(credit))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color(hex: 0x101828))
                                        .lineLimit(1)

                                    Text(Self.creditSubtitle(credit))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color(hex: 0x667085))
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: draftCredit?.id == credit.id ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(draftCredit?.id == credit.id ? Color(hex: 0x1BCA0B) : Color(hex: 0x98A2B3))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 58)
                            .background(draftCredit?.id == credit.id ? Color(hex: 0xEAF8E8) : Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(draftCredit?.id == credit.id ? Color(hex: 0x1BCA0B).opacity(0.35) : Color(hex: 0xEAECF0), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 16)
            }

            HStack(spacing: 12) {
                outlineButton("Close Message", action: onClose)
                filledButton("Submit") {
                    if let draftCredit {
                        onSubmit(draftCredit)
                    }
                }
                .disabled(draftCredit == nil)
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background(Color.white)
        .appCompactSheetCTAContainer()
    }

    private var sheetHandle: some View {
        EmptyView()
    }

    private static func creditTitle(_ credit: ConvexCompOffCredit) -> String {
        guard let earnedDate = credit.earnedDate,
              let date = ApplyLeaveView.apiDateFormatter.date(from: earnedDate)
        else { return "Comp-off credit" }
        return "Earned \(ApplyLeaveView.labelDateFormatter.string(from: date))"
    }

    private static func creditSubtitle(_ credit: ConvexCompOffCredit) -> String {
        let source = credit.source?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiry = credit.expiresAt
            .flatMap { ApplyLeaveView.apiDateFormatter.date(from: $0) }
            .map { "Valid till \(ApplyLeaveView.labelDateFormatter.string(from: $0))" }
        let subtitle = [source, expiry]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
        return subtitle.isEmpty ? "Available credit" : subtitle
    }
}

private struct LeaveDurationSheet: View {
    let title: String
    let subtitle: String
    let initialFromDate: Date?
    let initialToDate: Date?
    let singleSelection: Bool
    let lockedMonthDate: Date?
    let disabledDate: Date?
    let onClose: () -> Void
    let onSubmit: (Date, Date) -> Void

    @State private var displayedMonth: Date
    @State private var draftFromDate: Date?
    @State private var draftToDate: Date?

    init(
        title: String,
        subtitle: String,
        initialFromDate: Date?,
        initialToDate: Date?,
        singleSelection: Bool = false,
        lockedMonthDate: Date? = nil,
        disabledDate: Date? = nil,
        onClose: @escaping () -> Void,
        onSubmit: @escaping (Date, Date) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.initialFromDate = initialFromDate
        self.initialToDate = initialToDate
        self.singleSelection = singleSelection
        self.lockedMonthDate = lockedMonthDate
        self.disabledDate = disabledDate
        self.onClose = onClose
        self.onSubmit = onSubmit
        let baseDate = lockedMonthDate ?? initialFromDate ?? Date()
        _displayedMonth = State(initialValue: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: baseDate)) ?? baseDate)
        _draftFromDate = State(initialValue: initialFromDate)
        _draftToDate = State(initialValue: initialToDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHandle

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .padding(.top, 2)

            HStack {
                if lockedMonthDate == nil {
                    Button { changeMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color(hex: 0x101828))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
                Spacer()
                Text(Self.monthFormatter.string(from: displayedMonth))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                if lockedMonthDate == nil {
                    Button { changeMonth(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color(hex: 0x101828))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
            }
            .padding(.top, 12)

            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 24)
            .background(Color(hex: 0xEEF0F5))
            .padding(.top, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(monthGridDays, id: \.self) { date in
                    dayCell(date)
                }
            }
            .padding(.top, 6)

            filledButton("Submit Date") {
                guard let draftFromDate else { return }
                onSubmit(draftFromDate, draftToDate ?? draftFromDate)
            }
            .padding(.top, 16)
            .disabled(draftFromDate == nil)

            outlineButton("Close Message", action: onClose)
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background(Color.white)
        .appCompactSheetCTAContainer()
    }

    private var sheetHandle: some View {
        EmptyView()
    }

    private var monthGridDays: [Date] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
        let weekdayOffset = calendar.component(.weekday, from: monthStart) - 1
        let firstVisible = calendar.date(byAdding: .day, value: -weekdayOffset, to: monthStart) ?? monthStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstVisible) }
    }

    private func dayCell(_ date: Date) -> some View {
        let calendar = Calendar.current
        let inCurrentMonth = calendar.component(.month, from: date) == calendar.component(.month, from: displayedMonth)
            && calendar.component(.year, from: date) == calendar.component(.year, from: displayedMonth)
        let selectedStart = draftFromDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let selectedEnd = draftToDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let inRange = isInRange(date)
        let isDisabledDate = disabledDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let selectable = inCurrentMonth && !isDisabledDate

        return Button {
            guard selectable else { return }
            select(date)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 12, weight: selectedStart || selectedEnd ? .bold : .regular))
                .foregroundStyle(dayTextColor(inCurrentMonth: selectable, selected: selectedStart || selectedEnd))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    if selectedStart || selectedEnd {
                        Circle().fill(Color(hex: 0x1BCA0B))
                    } else if inRange {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: 0xEAF8E8))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
    }

    private func dayTextColor(inCurrentMonth: Bool, selected: Bool) -> Color {
        if selected { return .white }
        return inCurrentMonth ? Color(hex: 0x101828) : Color(hex: 0x98A2B3)
    }

    private func isInRange(_ date: Date) -> Bool {
        guard let draftFromDate, let draftToDate else { return false }
        let start = min(draftFromDate, draftToDate)
        let end = max(draftFromDate, draftToDate)
        return date >= Calendar.current.startOfDay(for: start) && date <= Calendar.current.startOfDay(for: end)
    }

    private func select(_ date: Date) {
        let normalized = Calendar.current.startOfDay(for: date)
        if singleSelection {
            draftFromDate = normalized
            draftToDate = normalized
            return
        }
        if draftFromDate == nil || draftToDate != nil {
            draftFromDate = normalized
            draftToDate = nil
        } else if let from = draftFromDate, normalized < from {
            draftToDate = from
            draftFromDate = normalized
        } else {
            draftToDate = normalized
        }
    }

    private func changeMonth(_ value: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }

    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}

private struct SubmitLeaveConfirmSheet: View {
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0xEAF8E8))
                    .frame(width: 58, height: 58)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1BCA0B))
            }
            .padding(.top, 20)

            Text("Apply Leave")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
                .padding(.top, 10)

            Text("Double-check your leave details to ensure everything is correct. Do you want to proceed?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            HStack(spacing: 12) {
                outlineButton("Close Message", action: onCancel)
                filledButton(isSubmitting ? "Submitting..." : "Submit") {
                    onSubmit()
                }
                .disabled(isSubmitting)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .background(Color.white)
        .appCompactSheetCTAContainer()
    }
}

private func filledButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
    }
    .buttonStyle(.plain)
}

private func outlineButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(hex: 0x1BCA0B))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(hex: 0x1BCA0B), lineWidth: 1)
            }
    }
    .buttonStyle(.plain)
}
