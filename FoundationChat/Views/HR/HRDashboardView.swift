import Combine
import SwiftUI

struct HRDashboardView: View {
    @State private var todayCheckIn: Date? = nil
    @State private var todayCheckOut: Date? = nil
    @State private var isLoading = false
    @State private var weekSummary: [DayAttendanceSummary] = []
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var elapsedText = "--:--:--"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    todayStatusCard
                    quickActionsGrid
                    weeklyChart
                }
                .padding()
            }
            .navigationTitle("HR")
            .task {
                loadDashboard()
            }
        }
    }

    private var todayStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let checkIn = todayCheckIn {
                        Text("Checked in at \(checkIn, format: .dateTime.hour().minute())")
                            .font(.headline)
                    } else {
                        Text("Not checked in")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if todayCheckIn != nil && todayCheckOut == nil {
                    VStack {
                        Text(elapsedText)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.green)
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }
                } else if let hours = calculateTodayHours() {
                    Text(hours)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.green)
                }
            }

            if todayCheckIn == nil {
                Button {
                    clockIn()
                } label: {
                    Label("Clock In", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else if todayCheckOut == nil {
                Button {
                    clockOut()
                } label: {
                    Label("Clock Out", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onReceive(timer) { _ in
            updateElapsed()
        }
    }

    private var quickActionsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK ACTIONS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink {
                    AttendanceListView()
                } label: {
                    QuickActionCard(icon: "clock.fill", title: "Attendance", color: .blue)
                }

                NavigationLink {
                    PermissionListView()
                } label: {
                    QuickActionCard(icon: "calendar.badge.clock", title: "Permission", color: .green)
                }

                NavigationLink {
                    CallFollowUpListView()
                } label: {
                    QuickActionCard(icon: "phone.fill", title: "Call Log", color: .cyan)
                }

                NavigationLink {
                    SiteVisitListView()
                } label: {
                    QuickActionCard(icon: "building.2.fill", title: "Site Visits", color: .orange)
                }

                NavigationLink {
                    GPSRecordingView()
                } label: {
                    QuickActionCard(icon: "location.fill", title: "Start Trip", color: .red)
                }

                NavigationLink {
                    GPSTripListView()
                } label: {
                    QuickActionCard(icon: "map.fill", title: "Trip History", color: .indigo)
                }

                NavigationLink {
                    TravelLogView()
                } label: {
                    QuickActionCard(icon: "car.fill", title: "Travel Log", color: .purple)
                }
            }
        }
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THIS WEEK")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            WeeklyAttendanceChart(summary: weekSummary)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func updateElapsed() {
        guard let checkIn = todayCheckIn, todayCheckOut == nil else { return }
        let interval = Date().timeIntervalSince(checkIn)
        let h = Int(interval / 3600)
        let m = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        let s = Int(interval.truncatingRemainder(dividingBy: 60))
        elapsedText = String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func calculateTodayHours() -> String? {
        guard let checkIn = todayCheckIn, let checkOut = todayCheckOut else { return nil }
        let interval = checkOut.timeIntervalSince(checkIn)
        let h = Int(interval / 3600)
        let m = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        return String(format: "%02d:%02d", h, m)
    }

    private func clockIn() {
        todayCheckIn = Date()
        // TODO: Call API endpoint
    }

    private func clockOut() {
        todayCheckOut = Date()
        // TODO: Call API endpoint
    }

    private func loadDashboard() {
        Task {
            do {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                let todayStr = df.string(from: Date())

                // Try to load today's mobile attendance
                let todayRecords: [APIMobileAttendance] = try await HRAPIService.shared.fetchMobileAttendance(
                    limit: 1,
                    fromDate: todayStr,
                    toDate: todayStr
                )
                if let today = todayRecords.first {
                    todayCheckIn = today.inDateAndTime
                    todayCheckOut = today.outDateAndTime
                }
            } catch {
                // Fall back to no data — user can still clock in manually
            }

            // Generate week summary
            let calendar = Calendar.current
            let today = Date()
            let weekday = calendar.component(.weekday, from: today)
            let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 2), to: today)!
            weekSummary = (0..<6).map { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: startOfWeek)!
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "EEE"
                let isPast = date < today
                return DayAttendanceSummary(
                    day: dayFormatter.string(from: date),
                    hours: isPast && !calendar.isDateInWeekend(date) ? Double.random(in: 6...9.5) : nil,
                    date: date
                )
            }
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
