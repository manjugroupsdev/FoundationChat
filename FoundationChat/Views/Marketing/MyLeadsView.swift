import SwiftUI
import UIKit

/// Telecaller "My Leads" — leads assigned to the signed-in user.
/// Mirrors the Android `MyLeadsFragment` modes (All + segment filters).
struct MyLeadsView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var mode: LeadMode = .all
    @State private var leads: [ConvexLead] = []
    @State private var nextCursor: String?
    @State private var hasMore: Bool = false
    @State private var isLoading: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage: String?
    @State private var search: String = ""

    private let pageSize = 50

    var body: some View {
        List {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(LeadMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if filteredLeads.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Leads",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(emptyDescription)
                )
            } else {
                ForEach(filteredLeads) { lead in
                    LeadRow(lead: lead)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if let phone = lead.phone, !phone.isEmpty {
                                Button {
                                    call(phone)
                                } label: {
                                    Label("Call", systemImage: "phone.fill")
                                }
                                .tint(.green)
                            }
                        }
                        .onAppear {
                            if lead.id == filteredLeads.last?.id, hasMore, !isLoadingMore {
                                loadMore()
                            }
                        }
                }

                if hasMore {
                    HStack {
                        Spacer()
                        if isLoadingMore {
                            ProgressView()
                        } else {
                            Button("Load more") { loadMore() }
                                .font(.subheadline)
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .navigationTitle("My Leads")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search name or phone")
        .refreshable { await reload() }
        .overlay {
            if isLoading && leads.isEmpty {
                ProgressView()
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await reload() }
        .onChange(of: mode) { _, _ in
            Task { await reload() }
        }
    }

    private var filteredLeads: [ConvexLead] {
        let scoped = leads.filter { mode.matches($0) }
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return scoped }
        return scoped.filter { lead in
            (lead.name?.lowercased().contains(trimmed) ?? false)
                || (lead.phone?.contains(trimmed) ?? false)
                || (lead.alternatePhone?.contains(trimmed) ?? false)
        }
    }

    private var emptyDescription: String {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            return "No leads match your search."
        }
        switch mode {
        case .all: return "You have no leads assigned yet."
        default: return "No leads in \(mode.title)."
        }
    }

    @MainActor
    private func reload() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await TelecallerConvexAPIService.getMyLeads(
                token: token,
                status: mode.statusFilter,
                cursor: nil,
                limit: pageSize
            )
            leads = page.leads
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() {
        guard let token = authStore.currentSession?.token, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            do {
                let page = try await TelecallerConvexAPIService.getMyLeads(
                    token: token,
                    status: mode.statusFilter,
                    cursor: nextCursor,
                    limit: pageSize
                )
                let existingIDs = Set(leads.map(\.id))
                let merged = leads + page.leads.filter { !existingIDs.contains($0.id) }
                leads = merged
                nextCursor = page.nextCursor
                hasMore = page.hasMore
            } catch {
                errorMessage = error.localizedDescription
                hasMore = false
            }
        }
    }

    private func call(_ phone: String) {
        let allowed = CharacterSet(charactersIn: "0123456789+*#")
        let encoded = phone.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        guard !encoded.isEmpty, let url = URL(string: "tel:\(encoded)") else { return }
        let app = UIApplication.shared
        if app.canOpenURL(url) { app.open(url) }
    }
}

private struct LeadRow: View {
    let lead: ConvexLead

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                Text(lead.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: "phone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(lead.displayPhone)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let source = lead.source, !source.isEmpty {
                    Text(source.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            statusBadge
        }
        .padding(.vertical, 4)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(avatarColor.opacity(0.15))
            Text(avatarInitials)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(avatarColor)
        }
        .frame(width: 40, height: 40)
    }

    private var avatarInitials: String {
        let name = lead.name?.trimmingCharacters(in: .whitespaces) ?? ""
        if name.isEmpty {
            return String((lead.phone ?? "•").suffix(2))
        }
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var avatarColor: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green]
        let key = lead.id.hashValue
        return palette[abs(key) % palette.count]
    }

    private var statusBadge: some View {
        Text(lead.statusLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch (lead.status ?? "new").lowercased() {
        case "new": return .blue
        case "contacted": return .orange
        case "follow_up", "followup", "follow-up": return .purple
        case "converted": return .green
        case "closed", "lost", "cancelled": return .gray
        default: return .secondary
        }
    }
}

#Preview {
    NavigationStack { MyLeadsView() }
        .environment(AuthStore())
}
