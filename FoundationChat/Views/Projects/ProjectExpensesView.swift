import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProjectExpensesView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var projects: [ProjectSummary] = []
    @State private var selectedProject: ProjectSummary?
    @State private var selectedCategory: ProjectExpenseCategory = .all
    @State private var fromDate: Date?
    @State private var toDate: Date?
    @State private var expenses: [ProjectExpense] = []
    @State private var totals: ExpenseTotals = .zero
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingDateFilter = false
    @State private var showingCreateExpense = false
    @State private var showingProjectPicker = false
    @State private var selectedExpenseForDetail: ProjectExpense?
    @State private var didAnimateIn = false

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                Color(hex: 0x0B61CA)
                    .ignoresSafeArea(edges: .top)

                Color(hex: 0xF8F9FB).ignoresSafeArea()
                    .padding(.top, topInset + 126)

                VStack(spacing: 0) {
                    header(topInset: topInset)

                    VStack(spacing: 0) {
                        totalsCard
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .zIndex(1)

                        categoryChips
                            .padding(.top, 14)

                        expenseList

                        addExpenseButton
                    }
                    .background(Color(hex: 0xF8F9FB))
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 24,
                            topTrailingRadius: 24,
                            style: .continuous
                        )
                    )
                    .offset(y: -22)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showingDateFilter) {
            ExpenseDateFilterSheet(fromDate: $fromDate, toDate: $toDate) {
                Task { await refreshExpenses() }
            }
            .presentationDetents([.height(620), .large])
            .presentationCornerRadius(28)
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showingProjectPicker) {
            NativeSearchableSelectionSheet(
                title: "Select Project",
                prompt: "Search projects",
                items: projects,
                selectedId: selectedProject?.id,
                searchText: { project in project.displayName },
                rowContent: { project, isSelected in
                    projectSelectionRow(project, isSelected: isSelected)
                },
                onSelect: { project in
                    selectedProject = project
                    showingProjectPicker = false
                    Task { await refreshExpenses() }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingCreateExpense) {
            if let selectedProject {
                ExpenseCreationSheet(project: selectedProject, projects: projects) {
                    await refreshExpenses()
                }
                .presentationDetents([.large])
            }
        }
        .sheet(item: $selectedExpenseForDetail) { expense in
            ExpenseDetailSheet(expense: expense) {
                await refreshExpenses()
            }
            .presentationDetents([.height(390), .medium])
        }
        .alert("Error", isPresented: errorAlertBinding, actions: {
            Button("OK", role: .cancel) { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .task { await loadProjects() }
        .onAppear { playEntryAnimation() }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func header(topInset: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Color(hex: 0x0B61CA)
                .ignoresSafeArea(edges: .top)

            Image("ProjectExpensesHeaderIllustration")
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 62)
                .padding(.trailing, 28)
                .offset(y: topInset + 18)
                .opacity(didAnimateIn ? 1 : 0)
                .scaleEffect(didAnimateIn ? 1 : 0.88)
                .animation(.spring(response: 0.52, dampingFraction: 0.82).delay(0.16), value: didAnimateIn)

            VStack(alignment: .leading, spacing: 0) {
                Text("Expenses")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("Manage and track all Expenses")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xD9D6FE))
                    .padding(.top, 3)

                HStack(spacing: 8) {
                    Button {
                        showingProjectPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Text(selectedProject?.displayName ?? (projects.isEmpty ? "Choose a project" : "Choose a project"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: 0x101828))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if selectedProject != nil {
                                Circle()
                                    .fill(Color(hex: 0xF04438))
                                    .frame(width: 8, height: 8)
                            }

                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x667085))
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(!projects.isEmpty)

                    Button {
                        showingDateFilter = true
                    } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .frame(width: 42, height: 42)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Date filter")
                }
                .padding(.top, 12)
                .zIndex(2)
            }
            .padding(.horizontal, 20)
            .padding(.top, topInset + 18)
            .opacity(didAnimateIn ? 1 : 0)
            .offset(x: didAnimateIn ? 0 : -26)
            .animation(.easeOut(duration: 0.42).delay(0.08), value: didAnimateIn)
        }
        .frame(height: topInset + 150)
    }

    private func projectSelectionRow(_ project: ProjectSummary, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(project.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(2)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }
        }
        .padding(.vertical, 4)
    }

    private var totalsCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Expenses")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))

                    Text(formatRsUpper(totals.total))
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    Text(dateRangeText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                }

                Spacer(minLength: 16)

                ExpenseDonutChart(totals: totals.byCategory)
                    .frame(width: 102, height: 102)
            }

            HStack(alignment: .top, spacing: 8) {
                ExpenseLegendItem(title: "Labour", value: formatRs(totals.byCategory.labour), color: ProjectExpenseCategory.labour.color)
                ExpenseLegendItem(title: "Materials", value: formatRs(totals.byCategory.materials), color: ProjectExpenseCategory.materials.color)
                ExpenseLegendItem(title: "Equipments", value: formatRs(totals.byCategory.equipment), color: ProjectExpenseCategory.equipment.color)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(didAnimateIn ? 1 : 0)
        .offset(y: didAnimateIn ? 0 : 40)
        .animation(.easeOut(duration: 0.4).delay(0.1), value: didAnimateIn)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProjectExpenseCategory.allCases) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedCategory = category
                        }
                        Task { await refreshExpenses() }
                    } label: {
                        Text(category.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selectedCategory == category ? .white : Color(hex: 0x475467))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                selectedCategory == category ? Color(hex: 0x0B61CA) : Color(hex: 0xF2F4F7),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .sensoryFeedback(.selection, trigger: selectedCategory)
        .opacity(didAnimateIn ? 1 : 0)
        .offset(y: didAnimateIn ? 0 : 20)
        .animation(.easeOut(duration: 0.38).delay(0.2), value: didAnimateIn)
    }

    @ViewBuilder
    private var expenseList: some View {
        if isLoading && expenses.isEmpty {
            AppModuleLoadingRows()
                .frame(maxHeight: .infinity, alignment: .top)
        } else if expenses.isEmpty {
            Text("No expenses logged yet.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: 0x71717A))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 92)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(Array(expenses.enumerated()), id: \.element.id) { index, expense in
                        Button {
                            selectedExpenseForDetail = expense
                        } label: {
                            ProjectExpenseCard(expense: expense)
                                .padding(.horizontal, 16)
                                .opacity(didAnimateIn ? 1 : 0)
                                .offset(y: didAnimateIn ? 0 : 28)
                                .animation(
                                    .spring(response: 0.42, dampingFraction: 0.9).delay(0.26 + Double(index) * 0.045),
                                    value: didAnimateIn
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            .refreshable { await refreshExpenses() }
        }
    }

    private var addExpenseButton: some View {
        Button {
            if selectedProject == nil {
                errorMessage = "Choose a project first"
            } else {
                showingCreateExpense = true
            }
        } label: {
            Text("Add Expense")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0x18D40D), Color(hex: 0x27A800)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var dateRangeText: String {
        guard let fromDate, let toDate else { return "All time" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return "\(f.string(from: fromDate)) - \(f.string(from: toDate))"
    }

    private func loadProjects() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            projects = try await ProjectConvexAPIService.getMyProjects(token: token)
            if selectedProject == nil {
                selectedProject = projects.first
            }
            await refreshExpenses()
        } catch {
            guard !isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func refreshExpenses() async {
        guard let token = authStore.currentSession?.token, let project = selectedProject else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await ProjectConvexAPIService.listExpenses(
                token: token,
                projectId: project.id,
                fromDate: fromDate.map(AppModuleFormatters.ymd.string(from:)),
                toDate: toDate.map(AppModuleFormatters.ymd.string(from:)),
                category: selectedCategory.queryValue
            )
            expenses = page.expenses
            totals = page.totals
        } catch {
            guard !isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }

        return error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "cancelled"
    }

    private func playEntryAnimation() {
        didAnimateIn = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            didAnimateIn = true
        }
    }

    private func formatRs(_ value: Double) -> String {
        "Rs \(indianNumber(value))"
    }

    private func formatRsUpper(_ value: Double) -> String {
        "RS \(indianNumber(value))"
    }

    private func indianNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

private struct ExpenseLegendItem: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExpenseDonutChart: View {
    let totals: ExpenseCategoryTotals

    private var slices: [(Double, Color)] {
        [
            (totals.labour, ProjectExpenseCategory.labour.color),
            (totals.materials, ProjectExpenseCategory.materials.color),
            (totals.equipment, ProjectExpenseCategory.equipment.color),
            (totals.other, ProjectExpenseCategory.other.color)
        ].filter { $0.0 > 0 }
    }

    var body: some View {
        ZStack {
            if slices.isEmpty {
                Circle()
                    .stroke(Color(hex: 0xEAECF0), lineWidth: 20)
            } else {
                Canvas { context, size in
                    let total = slices.reduce(0) { $0 + $1.0 }
                    let rect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
                    let gap = Angle.degrees(slices.count > 1 ? 4 : 0)
                    var start = Angle.degrees(-90)
                    for slice in slices {
                        let sweep = Angle.degrees(360 * slice.0 / total)
                        let end = start + sweep - gap
                        var path = Path()
                        path.addArc(
                            center: CGPoint(x: size.width / 2, y: size.height / 2),
                            radius: min(rect.width, rect.height) / 2,
                            startAngle: start + gap / 2,
                            endAngle: end,
                            clockwise: false
                        )
                        context.stroke(path, with: .color(slice.1), style: StrokeStyle(lineWidth: 20, lineCap: .butt))
                        start = start + sweep
                    }
                }
            }

            Circle()
                .fill(Color.white)
                .frame(width: 58, height: 58)
        }
    }
}

private struct ProjectExpenseCard: View {
    let expense: ProjectExpense

    private var category: ProjectExpenseCategory {
        ProjectExpenseCategory.from(expense.category)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(category.color)
                        .frame(width: 44, height: 44)

                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title == "All" ? expense.category.capitalized : category.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))

                    Text(monthYear(expense.date))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(formatRs(expense.amount))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))

                    Text(expense.paid ? "Paid" : "Pending")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(expense.paid ? Color(hex: 0x16A34A) : Color(hex: 0xF97316))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(expense.paid ? Color(hex: 0xECFDF3) : Color(hex: 0xFFFAEB), in: Capsule())
                }
            }

            Divider()
                .overlay(Color(hex: 0xF2F4F7))
                .padding(.top, 12)

            HStack(spacing: 4) {
                Text("View Details")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }

    private func monthYear(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        let display = DateFormatter()
        display.dateFormat = "MMMM yyyy"
        return display.string(from: date)
    }

    private func formatRs(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return "Rs \(formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))")"
    }
}

private struct ExpenseDateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fromDate: Date?
    @Binding var toDate: Date?
    let onApply: () -> Void

    @State private var draftFrom = Date()
    @State private var draftTo = Date()
    @State private var visibleMonth = Date()

    private let calendar = Calendar.current
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetGrabber
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("Date Filter")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                Text("Select Date Filter")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(hex: 0x667085))
            }

            HStack {
                Button { moveMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))

                Spacer()

                Button { moveMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 12) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x101828))
                        .frame(maxWidth: .infinity)
                        .frame(height: 33)
                        .background(Color(hex: 0xEAECF0), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                ForEach(calendarDays, id: \.date) { item in
                    Button {
                        selectDate(item.date)
                    } label: {
                        Text("\(calendar.component(.day, from: item.date))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(dayTextColor(item))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background {
                                dayBackground(item)
                                    .clipShape(Capsule())
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)

            Button {
                fromDate = min(draftFrom, draftTo)
                toDate = max(draftFrom, draftTo)
                onApply()
                dismiss()
            } label: {
                Text("Submit Date")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: 0x18B900), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .onAppear {
            draftFrom = fromDate ?? Date()
            draftTo = toDate ?? fromDate ?? Date()
            visibleMonth = draftFrom
        }
    }

    private var sheetGrabber: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(hex: 0xD9D9D9))
            .frame(width: 32, height: 4)
            .frame(maxWidth: .infinity)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: visibleMonth)
    }

    private var calendarDays: [(date: Date, isCurrentMonth: Bool)] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let gridStart = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)?.start,
              let lastDay = calendar.date(byAdding: DateComponents(day: -1), to: monthInterval.end),
              let gridEnd = calendar.dateInterval(of: .weekOfMonth, for: lastDay)?.end else {
            return []
        }

        var days: [(Date, Bool)] = []
        var cursor = gridStart
        while cursor < gridEnd {
            days.append((cursor, calendar.isDate(cursor, equalTo: visibleMonth, toGranularity: .month)))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return days
    }

    private func moveMonth(_ value: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            visibleMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
        }
    }

    private func selectDate(_ date: Date) {
        if draftFrom != draftTo {
            draftFrom = date
            draftTo = date
        } else if date < draftFrom {
            draftTo = draftFrom
            draftFrom = date
        } else {
            draftTo = date
        }
    }

    private func dayTextColor(_ item: (date: Date, isCurrentMonth: Bool)) -> Color {
        if isSelectedEndpoint(item.date) { return .white }
        return item.isCurrentMonth ? Color(hex: 0x101828) : Color(hex: 0x98A2B3)
    }

    @ViewBuilder
    private func dayBackground(_ item: (date: Date, isCurrentMonth: Bool)) -> some View {
        if isSelectedEndpoint(item.date) {
            Color(hex: 0x0B61CA)
        } else if isWithinRange(item.date) {
            Color(hex: 0xEAF2FF)
        } else {
            Color.clear
        }
    }

    private func isSelectedEndpoint(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: draftFrom) || calendar.isDate(date, inSameDayAs: draftTo)
    }

    private func isWithinRange(_ date: Date) -> Bool {
        let lower = min(draftFrom, draftTo)
        let upper = max(draftFrom, draftTo)
        return date > lower && date < upper
    }
}

private struct ExpenseCreationSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let project: ProjectSummary
    let projects: [ProjectSummary]
    let onCreated: () async -> Void

    @State private var selectedProject: ProjectSummary?
    @State private var category: ProjectExpenseCategory? = .labour
    @State private var date = Date()
    @State private var didSelectDate = true
    @State private var showingDatePicker = false
    @State private var amount = ""
    @State private var notes = ""
    @State private var paymentMethod = ""
    @State private var isSaving = false
    @State private var isLoadingPhotos = false
    @State private var errorMessage: String?
    @State private var selectedPhotoData: [Data] = []

    private let categories: [ProjectExpenseCategory] = [.labour, .materials, .equipment, .other]
    private let paymentMethods = ["Cash", "UPI", "Bank Transfer", "Card", "Cheque", "Other"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    sheetHeader(title: "Expense Creation", subtitle: "In this you can able to create expenses")
                        .padding(.bottom, 6)

                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Expense Category *")
                        Menu {
                            ForEach(categories) { item in
                                Button(item.title) { category = item }
                            }
                        } label: {
                            pickerField(
                                icon: "doc.text",
                                iconColor: Color(hex: 0x7A5AF8),
                                title: category?.title ?? "Enter Expense",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Date")
                        Button {
                            showingDatePicker = true
                        } label: {
                            pickerField(icon: "calendar", iconColor: Color(hex: 0x0B61CA), title: didSelectDate ? displayDate(date) : "Select Date")
                        }
                        .buttonStyle(.plain)
                    }

                    iconTextField(label: "Money *", icon: "wallet.pass", placeholder: "Enter Money", text: $amount, keyboard: .decimalPad)
                    iconTextEditor(label: "Notes (Optional)", icon: "doc.text", placeholder: "Enter Notes", text: $notes)

                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Payment Method *")
                        Menu {
                            ForEach(paymentMethods, id: \.self) { method in
                                Button(method) { paymentMethod = method }
                            }
                        } label: {
                            pickerField(icon: "banknote", iconColor: Color(hex: 0x16A34A), title: paymentMethod.isEmpty ? "Select Payment Method" : paymentMethod, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }

                    photosBlock

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }

            Button {
                saveExpense()
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                } else {
                    Text("Save It")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
            }
            .buttonStyle(.plain)
            .background(Color(hex: 0x1BCA0B), in: Capsule())
            .disabled(isSaving)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .background(Color.white)
        }
        .background(Color.white)
        .onAppear {
            if selectedProject == nil {
                selectedProject = project
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            VStack(alignment: .leading, spacing: 18) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0xD9D9D9))
                    .frame(width: 42, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                Text("Select Date")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .padding(.top, 2)

                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                Button {
                    didSelectDate = true
                    showingDatePicker = false
                } label: {
                    Text("Submit Date")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(hex: 0x18B900))
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .background(Color.white)
            .presentationDetents([.height(470)])
            .presentationBackground(Color.white)
            .presentationCornerRadius(28)
            .presentationDragIndicator(.hidden)
        }
    }

    private func sheetHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0xD0D5DD))
                .frame(width: 40, height: 4)
                .padding(.bottom, 14)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: 0x667085))
    }

    private func readOnlyField(title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color(hex: 0x101828))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 46)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
            }
    }

    private func pickerField(icon: String, iconColor: Color, title: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x101828))
                .lineLimit(1)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
        }
    }

    private func iconTextField(
        label: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label)
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(icon == "doc" ? Color(hex: 0x0B61CA) : Color(hex: 0x16A34A))
                    .frame(width: 22)
                TextField(placeholder, text: text)
                    .font(.system(size: 14, weight: .medium))
                    .keyboardType(keyboard)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
            }
        }
    }

    private func iconTextEditor(label: String, icon: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 22)
                    .padding(.top, 10)
                ZStack(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: 0x98A2B3))
                            .padding(.top, 10)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: text)
                        .font(.system(size: 14, weight: .medium))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 92)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
            }
        }
    }

    private var photosBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                fieldLabel("Photos")
                Spacer()
                Text("\(selectedPhotoData.count) \(selectedPhotoData.count == 1 ? "Photo" : "Photos")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(selectedPhotoData.enumerated()), id: \.offset) { index, data in
                        selectedPhotoThumbnail(data: data) {
                            selectedPhotoData.remove(at: index)
                        }
                    }

                    CameraFirstPhotoPicker(
                        maxSelectionCount: max(1, 6 - selectedPhotoData.count),
                        isDisabled: isSaving || isLoadingPhotos || selectedPhotoData.count >= 6
                    ) { photos in
                        isLoadingPhotos = true
                        selectedPhotoData.append(contentsOf: photos.prefix(max(0, 6 - selectedPhotoData.count)))
                        isLoadingPhotos = false
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: 0xF8FAFC))
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(hex: 0x98A2B3), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

                            if isLoadingPhotos {
                                ProgressView()
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x667085))
                            }
                        }
                        .frame(width: 72, height: 72)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add receipt photo")
                }
            }
        }
    }

    private func selectedPhotoThumbnail(data: Data, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                #if canImport(UIKit)
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(hex: 0xF8FAFC)
                }
                #else
                Color(hex: 0xF8FAFC)
                #endif
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.black.opacity(0.72))
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove receipt photo")
        }
    }

    private func saveExpense() {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in"
            return
        }
        guard let category else {
            errorMessage = "Select an expense category"
            return
        }
        guard let selectedProject else {
            errorMessage = "Select a project"
            return
        }
        let cleanedAmount = amount.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleanedAmount), value > 0 else {
            errorMessage = "Enter a valid amount"
            return
        }
        guard !paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Select payment method"
            return
        }

        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                let receipts = try await uploadSelectedReceipts(token: token)
                _ = try await ProjectConvexAPIService.createExpense(
                    token: token,
                    projectId: selectedProject.id,
                    category: category.rawValue,
                    amount: value,
                    date: AppModuleFormatters.ymd.string(from: date),
                    paymentMethod: paymentMethod,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    receipts: receipts.isEmpty ? nil : receipts,
                    paid: true
                )
                await onCreated()
                dismiss()
            } catch {
                let message = error.localizedDescription
                errorMessage = message == "Forbidden" ? "You are not assigned to this project" : message
            }
        }
    }

    private func uploadSelectedReceipts(token: String) async throws -> [ExpenseReceipt] {
        guard !selectedPhotoData.isEmpty else { return [] }

        var receipts: [ExpenseReceipt] = []
        for (index, data) in selectedPhotoData.enumerated() {
            let storageId = try await HRConvexAPIService.uploadPhoto(token: token, imageData: data)
            receipts.append(ExpenseReceipt(storageId: storageId, url: nil, name: "expense_receipt_\(index + 1).jpg"))
        }
        return receipts
    }

    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

private struct ExpenseDetailSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let expense: ProjectExpense
    let onChanged: () async -> Void

    @State private var loadedExpense: ProjectExpense?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var displayExpense: ProjectExpense { loadedExpense ?? expense }
    private var category: ProjectExpenseCategory { ProjectExpenseCategory.from(displayExpense.category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0xD9D9D9))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 14)

            Text("Expense Details")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))
                .padding(.bottom, 20)

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(category.color)
                        .frame(width: 56, height: 56)
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(category.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text(displayExpense.paid ? "Paid" : "Pending")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(displayExpense.paid ? Color(hex: 0x16A34A) : Color(hex: 0xF97316))
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background(displayExpense.paid ? Color(hex: 0xECFDF3) : Color(hex: 0xFFFAEB), in: Capsule())
                }

                Spacer()
            }
            .padding(.bottom, 28)

            detailRow("Amount", value: formatRs(displayExpense.amount))
            detailRow("Date", value: displayDate(displayExpense.date))
            detailRow("Payment Method", value: displayExpense.paymentMethod?.projectExpenseNilIfBlank ?? "-")

            if let notes = displayExpense.notes?.projectExpenseNilIfBlank {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Notes")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                    Text(notes)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color(hex: 0x475467))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(Color.white)
        .task { await loadExpense() }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
            Spacer()
            Text(value)
                .font(.system(size: title == "Amount" ? 16 : 14, weight: title == "Amount" ? .bold : .medium))
                .foregroundStyle(title == "Amount" ? Color(hex: 0x101828) : Color(hex: 0x475467))
                .multilineTextAlignment(.trailing)
        }
        .padding(.bottom, 20)
    }

    private func loadExpense() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            loadedExpense = try await ProjectConvexAPIService.getExpense(token: token, id: expense.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatRs(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return "Rs \(formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))")"
    }

    private func displayDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

private extension String {
    var projectExpenseNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
