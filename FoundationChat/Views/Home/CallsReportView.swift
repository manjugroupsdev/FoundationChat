import SwiftUI

/// VP-dashboard "Calls Report" drill-down — today's calls with a direction
/// filter (All / Incoming / Outgoing). Ports the Android CallsReportFragment.
struct CallsReportView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var calls: [DashboardCallRow] = []
    @State private var direction: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedCacheKey: String?

    /// `nil` = all directions; "incoming"/"outgoing" filter.
    init(initialDirection: String? = nil) {
        _direction = State(initialValue: initialDirection)
    }

    private var cacheKey: String {
        let staffId = authStore.viewer?.subject ?? authStore.currentSession?.user._id ?? "anonymous"
        let day = AppModuleFormatters.ymd.string(from: Date())
        return "dashboard.calls.\(staffId).\(day).\(direction ?? "all")"
    }

    var body: some View {
        List {
            Section {
                Picker("Direction", selection: Binding(
                    get: { direction ?? "all" },
                    set: { direction = ($0 == "all") ? nil : $0 }
                )) {
                    Text("All").tag("all")
                    Text("Incoming").tag("inbound")
                    Text("Outgoing").tag("outbound")
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if isLoading && calls.isEmpty {
                ForEach(0..<5, id: \.self) { _ in
                    DashboardDrilldownSkeletonRow()
                }
            } else if let errorMessage, calls.isEmpty {
                centeredRow {
                    VStack(spacing: 10) {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                }
            } else if calls.isEmpty {
                centeredRow {
                    Label("No calls found", systemImage: "phone.down")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(calls) { call in
                    callRow(call)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Calls Report")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: direction) { await load() }
        .refreshable { await load(forceRefresh: true) }
    }

    private func callRow(_ call: DashboardCallRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: directionIcon(call.callType))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(directionTint(call.callType))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(call.phoneNumber?.nonBlank ?? "Unknown number")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let agent = call.agent?.nonBlank {
                        Text(agent).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if let status = call.status?.nonBlank {
                        Text(status.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(directionTint(call.callType).opacity(0.12), in: Capsule())
                            .foregroundStyle(directionTint(call.callType))
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                if let time = call.time?.nonBlank {
                    Text(time).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                if let talk = (call.talkTime ?? call.duration)?.nonBlank {
                    Text(talk).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func centeredRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { Spacer(); content(); Spacer() }
            .padding(.vertical, 32)
            .listRowSeparator(.hidden)
    }

    private func directionIcon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "incoming", "inbound": return "phone.arrow.down.left"
        case "outgoing", "outbound": return "phone.arrow.up.right"
        case "missed": return "phone.down"
        default: return "phone"
        }
    }

    private func directionTint(_ type: String?) -> Color {
        switch (type ?? "").lowercased() {
        case "incoming", "inbound": return Color(hex: 0x059669)
        case "outgoing", "outbound": return Color(hex: 0x0B61CA)
        case "missed": return Color(hex: 0xDC2626)
        default: return Color(hex: 0x64748B)
        }
    }

    @MainActor
    private func load(forceRefresh: Bool = false) async {
        let requestedCacheKey = cacheKey
        if loadedCacheKey != requestedCacheKey {
            calls = LocalCache.get(requestedCacheKey, as: [DashboardCallRow].self) ?? []
            loadedCacheKey = requestedCacheKey
        } else if !forceRefresh, calls.isEmpty,
                  let cached = LocalCache.get(requestedCacheKey, as: [DashboardCallRow].self) {
            calls = cached
        }
        guard let token = authStore.currentSession?.token else {
            if calls.isEmpty { errorMessage = "Not signed in." }
            return
        }
        isLoading = calls.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            let refreshed = try await DashboardConvexAPIService.getDashboardCalls(
                token: token, date: nil, direction: direction
            )
            guard !Task.isCancelled, cacheKey == requestedCacheKey else { return }
            calls = refreshed
            LocalCache.put(requestedCacheKey, refreshed)
        } catch {
            guard !Task.isCancelled else { return }
            if calls.isEmpty { errorMessage = error.localizedDescription }
        }
    }
}

struct DashboardDrilldownSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.appSeparator.opacity(0.7))
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.appSeparator.opacity(0.7))
                    .frame(width: 150, height: 15)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.appSeparator.opacity(0.55))
                    .frame(width: 105, height: 11)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.appSeparator.opacity(0.55))
                .frame(width: 52, height: 12)
        }
        .padding(.vertical, 5)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
