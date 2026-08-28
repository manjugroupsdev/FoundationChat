import SwiftUI
import MapKit

/// GM review queue for OUT-OF-GEOFENCE CP completions held for approval.
///
/// Mirrors Android `CpApprovalQueueBottomSheet`. Lists the completions awaiting
/// this GM (the server scopes the feed to the resolved approver), each with the
/// client, the field staff, the place + how far out of geofence, the recorded
/// outcome, the staff's reason, and the arrival photo. Approve → the visit
/// completes; Reject (with a remark) → the visit reopens for the same staff.
struct CpApprovalQueueView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var items: [CpApprovalItem] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var busyItemId: String?

    @State private var rejectTarget: CpApprovalItem?
    @State private var rejectRemark = ""
    @State private var routeTarget: CpApprovalItem?

    private var cacheKey: String {
        let staffId = authStore.viewer?.subject ?? authStore.currentSession?.user._id ?? "anonymous"
        return "marketing.cp-approvals.pending.\(staffId)"
    }

    var body: some View {
        ScrollView {
            if isLoading && items.isEmpty {
                skeletonList
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else if items.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(items) { item in
                        CpApprovalCard(
                            item: item,
                            isBusy: busyItemId == item.id,
                            onViewRoute: { routeTarget = item },
                            onApprove: { Task { await approve(item) } },
                            onReject: {
                                rejectRemark = ""
                                rejectTarget = item
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .refreshable { await load() }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("CP Approvals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("CP Approvals")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
            }
        }
        .task { if !hasLoaded { await load() } }
        .sheet(item: $routeTarget) { item in
            CpApprovalTripDetailSheet(item: item)
        }
        .alert("Reject & reassign", isPresented: Binding(
            get: { rejectTarget != nil },
            set: { if !$0 { rejectTarget = nil } }
        )) {
            TextField("Reason for rejecting", text: $rejectRemark)
            Button("Cancel", role: .cancel) { rejectTarget = nil }
            Button("Reject", role: .destructive) {
                if let target = rejectTarget {
                    Task { await reject(target, remark: rejectRemark) }
                }
            }
        } message: {
            Text("This reopens the visit for \(rejectTarget?.staffName ?? "the staff") with your remark.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Color(hex: 0x98A2B3))
                .padding(.top, 72)
            Text(errorMessage == nil ? "Nothing to Approve" : "Couldn't Load")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .padding(.top, 16)
            Text(errorMessage ?? "Out-of-geofence CP completions waiting on your approval will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x667085))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var skeletonList: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: 0xE4E7EC))
                    .frame(height: 190)
                    .redacted(reason: .placeholder)
            }
        }
    }

    @MainActor
    private func load() async {
        if items.isEmpty,
           let cached = LocalCache.get(cacheKey, as: [CpApprovalItem].self) {
            items = cached
            hasLoaded = true
        }
        guard let token = authStore.currentSession?.token else {
            if items.isEmpty { errorMessage = "Not signed in." }
            hasLoaded = true
            return
        }
        isLoading = items.isEmpty
        defer { isLoading = false; hasLoaded = true }
        do {
            items = try await MarketingConvexAPIService.getPendingCpApprovals(token: token)
            LocalCache.put(cacheKey, items)
            errorMessage = nil
        } catch {
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func approve(_ item: CpApprovalItem) async {
        guard let token = authStore.currentSession?.token else { return }
        busyItemId = item.id
        defer { busyItemId = nil }
        do {
            try await MarketingConvexAPIService.approveCpCompletion(token: token, id: item.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reject(_ item: CpApprovalItem, remark: String) async {
        let trimmed = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "A remark is required to reject."
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        rejectTarget = nil
        busyItemId = item.id
        defer { busyItemId = nil }
        do {
            try await MarketingConvexAPIService.rejectCpCompletion(token: token, id: item.id, remark: trimmed)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CpApprovalCard: View {
    let item: CpApprovalItem
    let isBusy: Bool
    let onViewRoute: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.clientName?.blankToNil ?? "Client")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            Text("by \(item.staffName?.blankToNil ?? "Field staff")")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x475467))

            VStack(alignment: .leading, spacing: 5) {
                approvalFact("Date & time", ApprovalFormatting.scheduled(item))
                approvalFact("Start time", ApprovalFormatting.epoch(item.startedAt))
                approvalFact("End time", ApprovalFormatting.epoch(item.completedAt ?? item.requestedAt))
                approvalFact("CP type", ApprovalFormatting.cpType(item.cpType))
            }
            .padding(.top, 6)

            if let place = placeLine, !place.isEmpty {
                Text(place)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xB54708))
                    .padding(.top, 4)
            }

            if let outcome = item.outcome?.blankToNil {
                Text("Outcome: \(outcome.replacingOccurrences(of: "_", with: " "))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x475467))
            }

            if let remark = item.staffRemark?.blankToNil {
                Text("Staff reason: \(remark)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x101828))
                    .padding(.top, 2)
            }

            if let scheduled = item.scheduledDate?.blankToNil {
                Text("Scheduled: \(scheduled)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x667085))
            }

            if let photoUrl = item.photoUrl?.blankToNil, let url = URL(string: photoUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color(hex: 0xF2F4F7).overlay(Image(systemName: "photo").foregroundStyle(Color(hex: 0x98A2B3)))
                    default:
                        Color(hex: 0xF2F4F7).overlay(ProgressView())
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 10)
            }

            Button(action: onViewRoute) {
                Label("View trip & travelled route", systemImage: "map")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(hex: 0xEFF6FF), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Button(action: onReject) {
                    Text("Reject")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xB42318))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(hex: 0xFEE4E2), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Button(action: onApprove) {
                    Group {
                        if isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Text("Approve")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(hex: 0x169B2F), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
            .padding(.top, 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .stroke(Color(hex: 0xE4E7EC), lineWidth: 1)
        )
    }

    private func approvalFact(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value)")
            .font(.system(size: 12))
            .foregroundStyle(Color(hex: 0x344054))
    }

    private var placeLine: String? {
        let distance = item.distanceMeters.map { meters -> String in
            let label: String
            if meters >= 1000 {
                label = String(format: "%.1f km", meters / 1000)
            } else {
                label = "\(Int(meters.rounded())) m"
            }
            return "\(label) out of geofence"
        }
        return [item.placeName?.blankToNil, distance]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct CpApprovalTripDetailSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let item: CpApprovalItem

    @State private var route: CpApprovalRouteData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.clientName?.blankToNil ?? "CP trip details")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color(hex: 0x101828))
                        Text(item.placeName?.blankToNil ?? item.placeAddress?.blankToNil ?? "Client place")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0x667085))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        detail("Visit date", item.scheduledDate ?? "Not recorded")
                        detail("Scheduled time", ApprovalFormatting.clock(item.scheduledTime))
                        detail("Start time", ApprovalFormatting.epoch(item.startedAt))
                        detail("End time", ApprovalFormatting.epoch(item.completedAt ?? item.requestedAt))
                        detail("CP type", ApprovalFormatting.cpType(item.cpType))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12))

                    Text("Travelled route")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))

                    Map(position: $mapPosition) {
                        if let startCoordinate {
                            Annotation("Trip start", coordinate: startCoordinate) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                    .background(.white, in: Circle())
                            }
                        }
                        if let endCoordinate {
                            Annotation("Trip end", coordinate: endCoordinate) {
                                Image(systemName: "flag.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                                    .background(.white, in: Circle())
                            }
                        }
                        if displayCoordinates.count >= 2 {
                            MapPolyline(coordinates: displayCoordinates)
                                .stroke(
                                    Color(hex: 0x0B61CA),
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                                )
                        }
                    }
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        if isLoading {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)
                                .overlay { ProgressView("Loading GPS trail…") }
                        } else if displayCoordinates.isEmpty {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(hex: 0xF2F4F7))
                                .overlay {
                                    Text(errorMessage ?? "No GPS coordinates were recorded for this trip.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color(hex: 0x667085))
                                        .multilineTextAlignment(.center)
                                        .padding(24)
                                }
                        }
                    }

                    Text(routeCaption)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0x667085))
                }
                .padding(16)
            }
            .background(Color.white)
            .navigationTitle("Trip details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadRoute() }
    }

    private var recordedCoordinates: [CLLocationCoordinate2D] {
        route?.routePoints.compactMap { validCoordinate(lat: $0.lat, lng: $0.lng) } ?? []
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        recordedCoordinates.first
            ?? validCoordinate(lat: route?.startLat, lng: route?.startLng)
            ?? validCoordinate(lat: item.startLat, lng: item.startLng)
    }

    private var endCoordinate: CLLocationCoordinate2D? {
        recordedCoordinates.last
            ?? validCoordinate(lat: route?.endLat, lng: route?.endLng)
            ?? validCoordinate(lat: item.endLat, lng: item.endLng)
            ?? validCoordinate(lat: item.completionLat, lng: item.completionLng)
            ?? validCoordinate(lat: item.arrivalLat, lng: item.arrivalLng)
            ?? validCoordinate(lat: item.placeLat, lng: item.placeLng)
    }

    private var displayCoordinates: [CLLocationCoordinate2D] {
        if recordedCoordinates.count >= 2 { return recordedCoordinates }
        return [startCoordinate, endCoordinate].compactMap { $0 }.uniquedCoordinates()
    }

    private var routeCaption: String {
        if recordedCoordinates.count >= 2 {
            return "Recorded GPS trail · \(recordedCoordinates.count) points"
        }
        if displayCoordinates.count >= 2 {
            return "Only start and end coordinates were recorded; the line is an endpoint connection."
        }
        if displayCoordinates.count == 1 { return "Only one trip coordinate was recorded." }
        if errorMessage != nil, !displayCoordinates.isEmpty {
            return "The full GPS trail is unavailable; showing the recorded trip coordinates."
        }
        return errorMessage ?? "No recorded GPS trail is available."
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(Color(hex: 0x667085))
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: 0x101828))
        }
    }

    @MainActor
    private func loadRoute() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            isLoading = false
            return
        }
        do {
            route = try await MarketingConvexAPIService.getCpApprovalRoute(token: token, id: item.id)
            mapPosition = .automatic
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func validCoordinate(lat: Double?, lng: Double?) -> CLLocationCoordinate2D? {
        guard let lat, let lng, lat.isFinite, lng.isFinite,
              (-90...90).contains(lat), (-180...180).contains(lng),
              !(lat == 0 && lng == 0) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

private enum ApprovalFormatting {
    static func scheduled(_ item: CpApprovalItem) -> String {
        [item.scheduledDate?.blankToNil, clock(item.scheduledTime)]
            .compactMap { $0 }
            .filter { $0 != "Not recorded" }
            .joined(separator: " · ")
            .blankToNil ?? "Not recorded"
    }

    static func cpType(_ value: String?) -> String {
        guard let value = value?.blankToNil else { return "Not recorded" }
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func clock(_ value: String?) -> String {
        guard let value = value?.blankToNil else { return "Not recorded" }
        for format in ["HH:mm", "HH:mm:ss"] {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = format
            if let date = parser.date(from: value) {
                let display = DateFormatter()
                display.locale = Locale(identifier: "en_US_POSIX")
                display.dateFormat = "h:mm a"
                return display.string(from: date)
            }
        }
        return value
    }

    static func epoch(_ value: Double?) -> String {
        guard let value, value > 0 else { return "Not recorded" }
        let display = DateFormatter()
        display.dateFormat = "dd MMM yyyy, h:mm a"
        return display.string(from: Date(timeIntervalSince1970: value / 1000))
    }
}

private extension Array where Element == CLLocationCoordinate2D {
    func uniquedCoordinates() -> [CLLocationCoordinate2D] {
        reduce(into: []) { result, coordinate in
            guard !result.contains(where: {
                abs($0.latitude - coordinate.latitude) < 0.0000001 &&
                    abs($0.longitude - coordinate.longitude) < 0.0000001
            }) else { return }
            result.append(coordinate)
        }
    }
}

private extension String {
    var blankToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
