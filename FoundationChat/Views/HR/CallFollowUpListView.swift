import SwiftUI

struct CallFollowUpListView: View {
    @State private var calls: [APICallLog] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let api = HRAPIService.shared

    private var filteredCalls: [APICallLog] {
        if searchText.isEmpty { return calls }
        return calls.filter {
            ($0.clientName ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.mobileNumber ?? "").contains(searchText) ||
            ($0.callRefNo ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if filteredCalls.isEmpty {
                ContentUnavailableView("No Call Logs", systemImage: "phone",
                    description: Text("Call follow-ups will appear here."))
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredCalls) { call in
                    APICallLogRow(call: call)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name or phone")
        .navigationTitle("Call Follow Up")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCalls() }
        .refreshable { await loadCalls() }
    }

    private func loadCalls() async {
        isLoading = true
        errorMessage = nil
        do {
            calls = try await api.fetchCallLogs()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct APICallLogRow: View {
    let call: APICallLog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(call.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let status = call.callStatus, !status.isEmpty {
                    Text(status)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(callStatusColor(status).opacity(0.15), in: Capsule())
                        .foregroundStyle(callStatusColor(status))
                }
            }

            if !call.displayPhone.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "phone.fill").font(.caption2)
                    Text(call.displayPhone)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let project = call.nameOfProject, !project.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "building.2").font(.caption2)
                    Text(project)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let date = call.createdDateAndTime {
                Text(date, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let remarks = call.remarks, !remarks.isEmpty {
                Text(remarks)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(2)
            }

            if let reviewDate = call.reviewDateTime {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock").font(.caption2)
                    Text("Follow up: \(reviewDate, format: .dateTime.day().month(.abbreviated))")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func callStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "hot": return .red
        case "warm": return .orange
        case "cold": return .blue
        case "booked": return .green
        default: return .secondary
        }
    }
}
