import SwiftUI

struct AdvancedFilterOption: Identifiable, Hashable {
    let id: String
    let label: String
    var subtitle: String? = nil
}

struct AdvancedFilterCategory: Identifiable {
    enum SelectionMode: Equatable {
        case single
        case multiple
    }

    let id: String
    let title: String
    var options: [AdvancedFilterOption] = []
    var selectionMode: SelectionMode = .multiple
    var showsDateRange = false
    var isSearchable = true
}

struct AdvancedFilterState: Equatable {
    var selections: [String: Set<String>] = [:]
    var fromDate: Date?
    var toDate: Date?

    func selected(_ categoryID: String) -> Set<String> {
        selections[categoryID] ?? []
    }

    mutating func setSelected(_ values: Set<String>, for categoryID: String) {
        if values.isEmpty {
            selections.removeValue(forKey: categoryID)
        } else {
            selections[categoryID] = values
        }
    }

    var activeCount: Int {
        selections.values.reduce(0) { $0 + $1.count } + ((fromDate != nil || toDate != nil) ? 1 : 0)
    }

    mutating func clear() {
        selections.removeAll()
        fromDate = nil
        toDate = nil
    }
}

struct AdvancedListFilterView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let categories: [AdvancedFilterCategory]
    let initialState: AdvancedFilterState
    let resultCount: (AdvancedFilterState) -> Int
    let onApply: (AdvancedFilterState) -> Void

    @State private var draft: AdvancedFilterState
    @State private var selectedCategoryID: String
    @State private var optionSearchText = ""

    init(
        title: String = "Filters",
        categories: [AdvancedFilterCategory],
        state: AdvancedFilterState,
        resultCount: @escaping (AdvancedFilterState) -> Int,
        onApply: @escaping (AdvancedFilterState) -> Void
    ) {
        self.title = title
        self.categories = categories
        self.initialState = state
        self.resultCount = resultCount
        self.onApply = onApply
        _draft = State(initialValue: state)
        _selectedCategoryID = State(initialValue: categories.first?.id ?? "")
    }

    private var selectedCategory: AdvancedFilterCategory? {
        categories.first { $0.id == selectedCategoryID } ?? categories.first
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                categoryRail
                    .frame(width: 132)
                Divider()
                optionPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                applyBar
            }
            .background(Color(.systemBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Close filters")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear All") { draft.clear() }
                        .disabled(draft.activeCount == 0)
                }
            }
        }
    }

    private var categoryRail: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(categories) { category in
                    Button {
                        selectedCategoryID = category.id
                        optionSearchText = ""
                    } label: {
                        HStack(spacing: 6) {
                            Text(category.title)
                                .font(.system(size: 14, weight: category.id == selectedCategoryID ? .semibold : .regular))
                                .foregroundStyle(category.id == selectedCategoryID ? Color(hex: 0x0B61CA) : .primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 2)
                            if categoryActiveCount(category) > 0 {
                                Text("\(categoryActiveCount(category))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 20, minHeight: 20)
                                    .background(Color(hex: 0x0B61CA), in: Circle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .background(category.id == selectedCategoryID ? Color(.systemBackground) : Color(.secondarySystemBackground))
                        .overlay(alignment: .leading) {
                            if category.id == selectedCategoryID {
                                Rectangle()
                                    .fill(Color(hex: 0x0B61CA))
                                    .frame(width: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private var optionPane: some View {
        if let category = selectedCategory {
            VStack(spacing: 0) {
                if category.isSearchable && !category.showsDateRange {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search \(category.title.lowercased())", text: $optionSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                    Text(category.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 10)

                    if category.showsDateRange {
                        dateRangeOptions
                    } else if filteredOptions(in: category).isEmpty {
                        ContentUnavailableView(
                            optionSearchText.isEmpty ? "No options available" : "No matching options",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        ForEach(filteredOptions(in: category)) { option in
                            optionRow(option, category: category)
                        }
                    }
                    }
                }
            }
        }
    }

    private func filteredOptions(in category: AdvancedFilterCategory) -> [AdvancedFilterOption] {
        let query = optionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return category.options }
        return category.options.filter {
            $0.label.localizedCaseInsensitiveContains(query)
                || ($0.subtitle?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private func optionRow(_ option: AdvancedFilterOption, category: AdvancedFilterCategory) -> some View {
        let isSelected = draft.selected(category.id).contains(option.id)
        return Button {
            toggle(option.id, in: category)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.label)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    if let subtitle = option.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .frame(minHeight: 54)
        }
        .buttonStyle(.plain)
    }

    private var dateRangeOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                datePreset("Today", from: Date(), to: Date())
                datePreset(
                    "7 days",
                    from: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date(),
                    to: Date()
                )
            }
            HStack(spacing: 8) {
                datePreset(
                    "This month",
                    from: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date(),
                    to: Date()
                )
                Button("Clear dates") {
                    draft.fromDate = nil
                    draft.toDate = nil
                }
                .buttonStyle(.bordered)
                .disabled(draft.fromDate == nil && draft.toDate == nil)
            }

            Divider()

            DatePicker(
                "From",
                selection: Binding(
                    get: { draft.fromDate ?? Date() },
                    set: { draft.fromDate = Calendar.current.startOfDay(for: $0) }
                ),
                displayedComponents: .date
            )
            DatePicker(
                "To",
                selection: Binding(
                    get: { draft.toDate ?? draft.fromDate ?? Date() },
                    set: { draft.toDate = Calendar.current.startOfDay(for: $0) }
                ),
                displayedComponents: .date
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func datePreset(_ label: String, from: Date, to: Date) -> some View {
        Button(label) {
            draft.fromDate = Calendar.current.startOfDay(for: from)
            draft.toDate = Calendar.current.startOfDay(for: to)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private var applyBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(resultCount(normalized(draft)))")
                    .font(.system(size: 17, weight: .bold))
                Text("results found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onApply(normalized(draft))
                dismiss()
            } label: {
                Text("Apply")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(hex: 0x0B61CA), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func categoryActiveCount(_ category: AdvancedFilterCategory) -> Int {
        if category.showsDateRange {
            return (draft.fromDate != nil || draft.toDate != nil) ? 1 : 0
        }
        return draft.selected(category.id).count
    }

    private func toggle(_ optionID: String, in category: AdvancedFilterCategory) {
        var selected = draft.selected(category.id)
        if selected.contains(optionID) {
            selected.remove(optionID)
        } else if category.selectionMode == .single {
            selected = [optionID]
        } else {
            selected.insert(optionID)
        }
        draft.setSelected(selected, for: category.id)
    }

    private func normalized(_ state: AdvancedFilterState) -> AdvancedFilterState {
        guard let from = state.fromDate, let to = state.toDate, from > to else { return state }
        var copy = state
        copy.fromDate = to
        copy.toDate = from
        return copy
    }
}
