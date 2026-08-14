import SwiftUI

/// VP-dashboard "Calls Report" drill-down — today's calls with a direction
/// filter (All / Incoming / Outgoing). Ports the Android CallsReportFragment.
struct CallsReportView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var calls: [DashboardCallRow] = []
    @State private var direction: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// `nil` = all directions; "incoming"/"outgoing" filter.
    init(initialDirection: String? = nil) {
        _direction = State(initialValue: initialDirection)
    }

    var body: some View {
        List {
            Section {
                Picker("Direction", selection: Binding(
                    get: { direction ?? "all" },
                    set: { direction = ($0 == "all") ? nil : $0 }
                )) {
                    Text("All").tag("all")
                    Text("Incoming").tag("incoming")
                    Text("Outgoing").tag("outgoing")
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if isLoading && calls.isEmpty {
                centeredRow { ProgressView() }
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
    }

    private func callRow(_ call: DashboardCallRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: directionIcon(call.callType))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(directionTint(call.callType))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(call.phoneNumber?.nilIfBlank ?? "Unknown number")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let agent = call.agent?.nilIfBlank {
                        Text(agent).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if let status = call.status?.nilIfBlank {
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
                if let time = call.time?.nilIfBlank {
                    Text(time).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                if let talk = (call.talkTime ?? call.duration)?.nilIfBlank {
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

    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        errorMessage = nil
        do {
            calls = try await DashboardConvexAPIService.getDashboardCalls(
                token: token, date: nil, direction: direction
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
