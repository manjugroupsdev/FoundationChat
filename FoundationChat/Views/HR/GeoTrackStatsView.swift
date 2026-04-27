import SwiftUI

// MARK: - GeoTrackStatsView

struct GeoTrackStatsView: View {
    @State private var stats: GeoTrackStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var staffId: String? = nil

    private let geoAPI = GeoTrackAPIService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                dateRangePicker

                if isLoading {
                    ProgressView("Loading stats…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        "Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let stats {
                    statsGrid(stats)
                } else {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.bar",
                        description: Text("No tracking data for the selected period.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("GeoTrack Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var dateRangePicker: some View {
        VStack(spacing: 8) {
            HStack {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
            }
            .onChange(of: startDate) { Task { await load() } }
            .onChange(of: endDate) { Task { await load() } }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statsGrid(_ s: GeoTrackStats) -> some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatCard(
                    icon: "car.circle.fill",
                    color: .blue,
                    label: "Trips",
                    value: "\(s.tripCount)"
                )
                StatCard(
                    icon: "ruler.fill",
                    color: .green,
                    label: "Distance",
                    value: formattedDistance(s.totalDistanceMeters)
                )
                StatCard(
                    icon: "clock.fill",
                    color: .orange,
                    label: "Duration",
                    value: formattedDuration(s.totalDurationSeconds)
                )
                StatCard(
                    icon: "mappin.circle.fill",
                    color: .purple,
                    label: "Stops",
                    value: "\(s.totalStops)"
                )
            }

            if s.tamperEventCount > 0 {
                HStack {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(.red)
                    Text("\(s.tamperEventCount) tamper event\(s.tamperEventCount == 1 ? "" : "s") detected")
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let dayStart = Int64(startDate.timeIntervalSince1970 * 1000)
            let dayEnd   = Int64(endDate.timeIntervalSince1970 * 1000)
            stats = try await geoAPI.stats(staffId: staffId, startDate: dayStart, endDate: dayEnd)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func formattedDistance(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: "%.1f km", km)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let h = Int(seconds / 3600)
        let m = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(h)h \(m)m"
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    NavigationStack {
        GeoTrackStatsView()
    }
}
