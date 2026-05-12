import CoreLocation
import SwiftUI

/// Home tab — mirrors Android `HomeFragment` content order:
/// 1) Greeting line
/// 2) Work Summary card
/// 3) Today Visits list (rows push into TripNavigationView)
///
/// Header uses the navigation toolbar (matches Chat tab): notification bell on
/// the left of trailing items, profile avatar on the right.
struct HomeView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var todayVisits: [GeoTrackTodayVisit] = []
    @State private var unreadCount: Int = 0
    @State private var isLoadingVisits: Bool = false
    @State private var loadError: String?
    @State private var visitToOpen: GeoTrackTodayVisit?

    private let geoAPI = GeoTrackAPIService.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    workSummaryCard
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                        .listRowSeparator(.hidden)
                }

                Section {
                    if isLoadingVisits && todayVisits.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    } else if visibleVisits.isEmpty {
                        ContentUnavailableView(
                            "No Visits Today",
                            systemImage: "calendar",
                            description: Text("You're all clear — no visits planned today.")
                        )
                    } else {
                        ForEach(visibleVisits) { visit in
                            Button {
                                visitToOpen = visit
                            } label: {
                                visitRow(for: visit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack {
                        Text("Today Visits")
                        Spacer()
                        if !visibleVisits.isEmpty {
                            Text("\(visibleVisits.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue, in: Capsule())
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            NotificationsListView()
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                                if unreadCount > 0 {
                                    Text(unreadCount > 99 ? "99+" : String(unreadCount))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.red, in: Capsule())
                                        .offset(x: 8, y: -6)
                                }
                            }
                        }

                        NavigationLink {
                            ProfileView()
                        } label: {
                            ProfileAvatarView(label: authStore.currentUserLabel)
                        }
                    }
                }
            }
            .navigationDestination(item: $visitToOpen) { visit in
                TripNavigationView(
                    visitId: visit.id,
                    placeId: nil,
                    placeName: visit.placeName ?? "Visit",
                    placeAddress: visit.placeAddress,
                    destination: coordinate(for: visit),
                    initialStatus: visit.status
                )
            }
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    // MARK: - Work Summary

    private var workSummaryCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("My Work Summary")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(workSummarySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.purple, Color.indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var workSummarySubtitle: String {
        let count = visibleVisits.count
        if count == 0 {
            return "No visits scheduled today."
        }
        return "Today \(count) visit\(count == 1 ? "" : "s") on your schedule."
    }

    // MARK: - Today Visits

    private var visibleVisits: [GeoTrackTodayVisit] {
        todayVisits.filter { $0.status.uppercased() != "CANCELLED" }
    }

    private func visitRow(for visit: GeoTrackTodayVisit) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "mappin")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.placeName ?? "Visit")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let address = visit.placeAddress, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            statusPill(for: visit.status)
        }
        .padding(.vertical, 4)
    }

    private func statusPill(for status: String) -> some View {
        let normalized = status.uppercased()
        let label: String
        let color: Color
        switch normalized {
        case "IN_PROGRESS", "STARTED":
            label = "In progress"; color = .orange
        case "COMPLETED", "DONE":
            label = "Completed"; color = .gray
        default:
            label = "Start Trip"; color = .blue
        }
        return Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func coordinate(for visit: GeoTrackTodayVisit) -> CLLocationCoordinate2D? {
        guard let lat = visit.placeLat, let lng = visit.placeLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // MARK: - Loading

    @MainActor
    private func reload() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadTodayVisits() }
            group.addTask { await self.loadUnread() }
        }
    }

    @MainActor
    private func loadTodayVisits() async {
        isLoadingVisits = true
        defer { isLoadingVisits = false }
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = formatter.string(from: Date())
            todayVisits = try await geoAPI.todayVisits(date: today)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func loadUnread() async {
        do {
            unreadCount = try await authStore.fetchUnreadNotificationCount()
        } catch {
            unreadCount = 0
        }
    }
}

extension GeoTrackTodayVisit: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: GeoTrackTodayVisit, rhs: GeoTrackTodayVisit) -> Bool { lhs.id == rhs.id }
}

#Preview {
    HomeView()
        .environment(AuthStore())
}
