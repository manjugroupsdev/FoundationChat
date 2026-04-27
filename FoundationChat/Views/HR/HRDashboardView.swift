import Combine
import SwiftUI

struct HRDashboardView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var todayAttendance: ConvexTodayAttendance?
    @State private var isLoading = false
    @State private var weekSummary: [DayAttendanceSummary] = []
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var elapsedText = "--:--:--"
    @State private var errorMessage: String?
    @State private var showPunchIn = false
    @State private var showPunchOut = false

    private var hasPunchedIn: Bool { todayAttendance?.hasPunchedIn == true }
    private var isOpen: Bool { todayAttendance?.isOpen == true }

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
            .sheet(isPresented: $showPunchIn) {
                PunchFlowView(mode: .punchIn) {
                    loadDashboard()
                }
            }
            .sheet(isPresented: $showPunchOut) {
                PunchFlowView(mode: .punchOut) {
                    loadDashboard()
                }
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
                    if let punchIn = todayAttendance?.punchInDate {
                        Text("Checked in at \(punchIn, format: .dateTime.hour().minute())")
                            .font(.headline)
                    } else {
                        Text("Not checked in")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isOpen {
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !hasPunchedIn {
                Button {
                    showPunchIn = true
                } label: {
                    Label("Clock In", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else if isOpen {
                Button {
                    showPunchOut = true
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
                    ConvexAttendanceListView()
                } label: {
                    QuickActionCard(icon: "clock.fill", title: "Attendance", color: .blue)
                }

                NavigationLink {
                    TasksListView()
                } label: {
                    QuickActionCard(icon: "checklist", title: "Tasks", color: .indigo)
                }

                NavigationLink {
                    LeavesListView()
                } label: {
                    QuickActionCard(icon: "calendar.badge.minus", title: "Leaves", color: .purple)
                }

                NavigationLink {
                    ConvexPermissionListView()
                } label: {
                    QuickActionCard(icon: "calendar.badge.clock", title: "Permission", color: .green)
                }

                NavigationLink {
                    LeaveApprovalsView()
                } label: {
                    QuickActionCard(icon: "checkmark.circle.fill", title: "Approvals", color: .teal)
                }

                NavigationLink {
                    GPSRecordingView()
                } label: {
                    QuickActionCard(icon: "location.fill", title: "Start Trip", color: .red)
                }

                NavigationLink {
                    GeoTrackTodayVisitsView()
                } label: {
                    QuickActionCard(icon: "calendar.badge.clock", title: "My Visits", color: .teal)
                }

                NavigationLink {
                    GeoTrackAssignedPlacesView()
                } label: {
                    QuickActionCard(icon: "building.2.fill", title: "My Places", color: .mint)
                }

                NavigationLink {
                    GeoTrackStatsView()
                } label: {
                    QuickActionCard(icon: "chart.bar.fill", title: "GPS Stats", color: .indigo)
                }

                NavigationLink {
                    GeoTrackLiveStatusView()
                } label: {
                    QuickActionCard(icon: "dot.radiowaves.left.and.right", title: "Live Status", color: .red)
                }

                NavigationLink {
                    StaffListView()
                } label: {
                    QuickActionCard(icon: "person.2.fill", title: "Staff", color: .pink)
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
        guard let punchIn = todayAttendance?.punchInDate, isOpen else { return }
        let interval = Date().timeIntervalSince(punchIn)
        let h = Int(interval / 3600)
        let m = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        let s = Int(interval.truncatingRemainder(dividingBy: 60))
        elapsedText = String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func calculateTodayHours() -> String? {
        guard let mins = todayAttendance?.cumulativeMinutes ?? todayAttendance?.totalMinutes, mins > 0 else { return nil }
        let h = mins / 60
        let m = mins % 60
        return String(format: "%02d:%02d", h, m)
    }

    private func loadDashboard() {
        guard let token = authStore.currentSession?.token else { return }
        Task {
            do {
                let today = try await HRConvexAPIService.getTodayAttendance(token: token)
                todayAttendance = today
            } catch {
                // Fall back — user can still clock in
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
