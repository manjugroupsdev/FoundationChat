import SwiftUI

struct PunchLogSheet: View {
    @Environment(AuthStore.self) private var authStore

    let record: ConvexAttendanceRecord

    @State private var entries: [PunchLogEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var displayEntries: [PunchLogEntry] {
        entries.isEmpty ? fallbackEntries : entries
    }

    private var fallbackEntries: [PunchLogEntry] {
        (record.sessions ?? []).enumerated().map { index, session in
            PunchLogEntry(session: session, index: index)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryRow
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if displayEntries.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Punch Logs",
                        systemImage: "clock.badge.questionmark",
                        description: Text("Punch details are not available for this attendance record.")
                    )
                    .listRowBackground(Color.clear)
                }

                Section("Punch Logs") {
                    ForEach(Array(displayEntries.enumerated()), id: \.element.id) { index, entry in
                        punchLogRow(entry, index: index)
                    }
                }
            }
            .navigationTitle("Punch Log")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isLoading && entries.isEmpty {
                    ProgressView()
                }
            }
            .task(id: record.id) {
                await loadPunchLogs()
            }
        }
    }

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.date ?? "--")
                        .font(.headline)
                    if let status = record.approvedAttendance ?? record.status {
                        Text(status.capitalized)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(attendanceStatusColor(status))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(record.totalHoursFormatted)
                        .font(.headline)
                    Text("\(displayEntries.count) session\(displayEntries.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func punchLogRow(_ entry: PunchLogEntry, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.durationLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            punchLine(
                title: "Punch In",
                time: entry.punchInTime,
                address: entry.punchInAddress,
                latitude: entry.punchInLatitude,
                longitude: entry.punchInLongitude,
                photo: entry.punchInPhoto,
                color: .green,
                icon: "arrow.right.circle.fill"
            )

            punchLine(
                title: "Punch Out",
                time: entry.punchOutTime,
                address: entry.punchOutAddress,
                latitude: entry.punchOutLatitude,
                longitude: entry.punchOutLongitude,
                photo: entry.punchOutPhoto,
                color: .orange,
                icon: "arrow.left.circle.fill"
            )

            if let source = entry.source?.nilIfBlank {
                Label(source, systemImage: "tray.full")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func punchLine(
        title: String,
        time: String?,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        photo: String?,
        color: Color,
        icon: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(time))
                        .font(.subheadline.weight(.medium))
                }

                if let address = address?.nilIfBlank {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let latitude, let longitude {
                    Text(String(format: "%.5f, %.5f", latitude, longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if photo?.nilIfBlank != nil {
                    Label("Photo captured", systemImage: "camera.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func loadPunchLogs() async {
        guard let token = authStore.currentSession?.token,
              let date = record.date?.nilIfBlank else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await HRConvexAPIService.getDaySessions(
                token: token,
                date: date,
                staffId: record.staffId
            )
            entries = (response.sessions ?? []).enumerated().map { index, session in
                PunchLogEntry(session: session, index: index)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatTime(_ value: String?) -> String {
        guard let value = value?.nilIfBlank else { return "--" }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        let date = fractional.date(from: value) ?? standard.date(from: value)
        guard let date else { return value }

        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        return formatter.string(from: date)
    }

    private func attendanceStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "present", "approved", "auto-approved": return .green
        case "half-day": return .orange
        case "absent": return .red
        default: return .secondary
        }
    }
}

private struct PunchLogEntry: Identifiable {
    let id: String
    let punchInTime: String?
    let punchOutTime: String?
    let durationMinutes: Int?
    let punchInLatitude: Double?
    let punchInLongitude: Double?
    let punchInAddress: String?
    let punchInPhoto: String?
    let punchOutLatitude: Double?
    let punchOutLongitude: Double?
    let punchOutAddress: String?
    let punchOutPhoto: String?
    let source: String?

    var durationLabel: String {
        guard let durationMinutes, durationMinutes > 0 else { return "--" }
        let h = durationMinutes / 60
        let m = durationMinutes % 60
        return String(format: "%dh %02dm", h, m)
    }

    init(session: ConvexDaySession, index: Int) {
        self.id = session.id + "_\(index)"
        self.punchInTime = session.punchInTime
        self.punchOutTime = session.punchOutTime
        self.durationMinutes = session.durationMinutes
        self.punchInLatitude = session.punchInLatitude
        self.punchInLongitude = session.punchInLongitude
        self.punchInAddress = session.punchInAddress
        self.punchInPhoto = session.punchInPhoto
        self.punchOutLatitude = session.punchOutLatitude
        self.punchOutLongitude = session.punchOutLongitude
        self.punchOutAddress = session.punchOutAddress
        self.punchOutPhoto = session.punchOutPhoto
        self.source = session.source
    }

    init(session: ConvexAttendanceSession, index: Int) {
        self.id = "\(session.punchInTime ?? "in")_\(session.punchOutTime ?? "out")_\(index)"
        self.punchInTime = session.punchInTime
        self.punchOutTime = session.punchOutTime
        self.durationMinutes = nil
        self.punchInLatitude = session.punchInLatitude
        self.punchInLongitude = session.punchInLongitude
        self.punchInAddress = nil
        self.punchInPhoto = session.punchInPhoto
        self.punchOutLatitude = session.punchOutLatitude
        self.punchOutLongitude = session.punchOutLongitude
        self.punchOutAddress = nil
        self.punchOutPhoto = session.punchOutPhoto
        self.source = session.source
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    PunchLogSheet(
        record: ConvexAttendanceRecord(
            _id: "1",
            _creationTime: nil,
            attendanceId: "ATT-1",
            date: "2026-06-08",
            firstPunchIn: "2026-06-08T03:30:00.000Z",
            lastPunchOut: "2026-06-08T12:30:00.000Z",
            sessionCount: 1,
            sessions: [],
            totalMinutes: 540,
            cumulativeMinutes: nil,
            attendanceValue: nil,
            staffId: nil,
            staffName: nil,
            source: "mobile",
            status: "present",
            approvedAttendance: nil,
            approvedBy: nil,
            approvedByName: nil,
            approvedOn: nil,
            lateMinutes: nil,
            fineAmount: nil,
            lateFineDeduction: nil,
            otherFines: nil
        )
    )
}
