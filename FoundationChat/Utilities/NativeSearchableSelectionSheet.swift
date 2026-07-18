import SwiftUI

struct NativeSearchableSelectionSheet<Item: Identifiable, RowContent: View>: View where Item.ID: Equatable {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let prompt: String
    let items: [Item]
    let selectedId: Item.ID?
    let searchText: (Item) -> String
    let rowContent: (Item, Bool) -> RowContent
    let onSelect: (Item) -> Void

    @State private var query = ""

    init(
        title: String,
        prompt: String = "Search",
        items: [Item],
        selectedId: Item.ID?,
        searchText: @escaping (Item) -> String,
        @ViewBuilder rowContent: @escaping (Item, Bool) -> RowContent,
        onSelect: @escaping (Item) -> Void
    ) {
        self.title = title
        self.prompt = prompt
        self.items = items
        self.selectedId = selectedId
        self.searchText = searchText
        self.rowContent = rowContent
        self.onSelect = onSelect
    }

    private var filteredItems: [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { searchText($0).localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "magnifyingglass",
                        description: Text("Try another search.")
                    )
                } else {
                    ForEach(filteredItems) { item in
                        Button {
                            select(item)
                        } label: {
                            rowContent(item, selectedId == item.id)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: prompt
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func select(_ item: Item) {
        onSelect(item)
        dismiss()
    }
}
