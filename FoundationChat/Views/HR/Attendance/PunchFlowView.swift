import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct PunchFlowView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let mode: PunchMode
    var onComplete: (() -> Void)?

    enum PunchMode {
        case punchIn
        case punchOut
    }

    @State private var capturedImage: UIImage?
    @State private var captureTimestamp: Date?
    @State private var showCamera = false
    @State private var showConfirmation = false
    @State private var location: CLLocation?
    @State private var address: String?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isSubmitting = false
    @State private var isStatusLoading = false
    @State private var errorMessage: String?
    @State private var statusText: String?
    @State private var currentAttendance: ConvexTodayAttendance?
    @State private var locationManager = PunchLocationManager()
    @State private var showSuccessSheet = false
    @State private var completedAt: Date?
    @State private var didQueueOffline = false

    private var title: String {
        mode == .punchIn ? "Clock In" : "Clock Out"
    }

    private var canCaptureSelfie: Bool {
        location != nil && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    currentStatusSection
                    mapSection
                    locationInfoSection
                    selfiePromptSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .navigationDestination(isPresented: $showConfirmation) {
                if let capturedImage, let location, let captureTimestamp {
                    SelfieClockInDetailView(
                        mode: mode,
                        selfie: capturedImage,
                        location: location,
                        address: address,
                        timestamp: captureTimestamp,
                        isSubmitting: isSubmitting,
                        statusText: statusText,
                        errorMessage: errorMessage,
                        onRetake: {
                            self.capturedImage = nil
                            self.captureTimestamp = nil
                            self.errorMessage = nil
                            self.showConfirmation = false
                            self.showCamera = true
                        },
                        onConfirm: { submit() },
                        onCancel: { dismiss() }
                    )
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                PunchCameraView(capturedImage: $capturedImage)
            }
            .sheet(isPresented: $showSuccessSheet, onDismiss: finishAfterSuccess) {
                PunchSuccessSheet(
                    mode: mode,
                    completedAt: completedAt ?? Date(),
                    address: address,
                    offline: didQueueOffline,
                    onDone: finishAfterSuccess
                )
                .appLibraryNativeSheet([.height(310)])
                .interactiveDismissDisabled(isSubmitting)
            }
            .task {
                await loadCurrentAttendanceStatus()
                locationManager.requestLocation()
            }
            .onChange(of: locationManager.currentLocation) { _, newLoc in
                guard let newLoc else { return }
                location = newLoc
                mapPosition = .camera(MapCamera(
                    centerCoordinate: newLoc.coordinate,
                    distance: 500
                ))
                Task {
                    let geocoder = CLGeocoder()
                    if let placemarks = try? await geocoder.reverseGeocodeLocation(newLoc),
                       let place = placemarks.first {
                        let parts = [place.name, place.locality, place.administrativeArea].compactMap { $0 }
                        address = parts.joined(separator: ", ")
                    }
                }
            }
            .onChange(of: capturedImage) { _, newImage in
                guard newImage != nil else { return }
                captureTimestamp = Date()
                errorMessage = nil
                showConfirmation = true
            }
        }
        .appFormActivity()
    }

    // MARK: - Current status

    private var currentStatusSection: some View {
        HStack(spacing: 12) {
            Image(systemName: currentStatusIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(currentStatusColor)
                .frame(width: 42, height: 42)
                .background(currentStatusColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Current Attendance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(isStatusLoading ? "Checking status..." : currentStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isStatusLoading {
                ProgressView()
            } else {
                Text(currentStatusBadge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(currentStatusColor)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(currentStatusColor.opacity(0.12), in: Capsule())
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Map

    private var mapSection: some View {
        Map(position: $mapPosition) {
            if let location {
                Annotation("You", coordinate: location.coordinate) {
                    ZStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 20, height: 20)
                        Circle()
                            .stroke(.white, lineWidth: 3)
                            .frame(width: 20, height: 20)
                        Circle()
                            .fill(.blue.opacity(0.2))
                            .frame(width: 50, height: 50)
                    }
                }
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if location == nil {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(locationPlaceholderText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
    }

    // MARK: - Location Info

    private var locationInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                if let address {
                    Text(address)
                        .font(.subheadline)
                } else if location != nil {
                    Text("Resolving address...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(locationPlaceholderText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "location.fill")
                    .foregroundStyle(.blue)
            }

            if let location {
                HStack(spacing: 16) {
                    Label(String(format: "%.4f", location.coordinate.latitude), systemImage: "arrow.up.right")
                    Label(String(format: "%.4f", location.coordinate.longitude), systemImage: "arrow.down.left")
                    Label(String(format: "%.0fm", location.horizontalAccuracy), systemImage: "scope")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Selfie prompt

    private var selfiePromptSection: some View {
        Button {
            showCamera = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                    .foregroundStyle(mode == .punchIn ? .green : .orange)
                Text("Take Selfie")
                    .font(.headline)
                Text(location == nil ? "Waiting for GPS..." : "Front camera required for attendance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .background(
                (mode == .punchIn ? Color.green : Color.orange).opacity(canCaptureSelfie ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canCaptureSelfie)
    }

    // MARK: - Submit

    private func submit() {
        guard let token = authStore.currentSession?.token,
              let loc = location,
              let image = capturedImage else { return }

        isSubmitting = true
        errorMessage = nil

        // Capture the REAL tap time up front. Everything below (photo upload, the
        // punch call) can be slowed by a weak network; recording this device time
        // means the punch lands at the moment the staff acted, not when the server
        // finally receives it. We reuse the on-device selfie-capture time (also
        // network-independent) and fall back to now. Mirrors Android
        // HomeViewModel.punch()'s `punchIso = isoNow()`.
        let tapTime = captureTimestamp ?? Date()
        let clientPunchTime = PunchTimestamp.iso(from: tapTime)
        let deviceId = GeoTrackBootstrapCoordinator.shared.deviceId

        Task {
            defer {
                isSubmitting = false
                statusText = nil
            }
            // Encode the selfie once — reused for the online upload AND, on a network
            // failure, for the offline queue so the proof photo isn't lost either.
            let jpegData = image.attendanceUploadJPEGData(maxEdge: 1280, quality: 0.68)
            do {
                statusText = "Checking attendance..."
                let latestAttendance = try await HRConvexAPIService.getTodayAttendance(token: token)
                let today = Self.dateKeyFormatter.string(from: Date())
                let daySessions = try? await HRConvexAPIService.getDaySessions(token: token, date: today)
                let firstPunchIn = daySessions?.firstPunchIn ?? latestAttendance?.firstPunchIn ?? latestAttendance?.punchInTime
                let hasPunchedInToday = firstPunchIn?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let clockedOutOnMobile = AttendanceTrackingGate.isClockedOutOnMobile(
                    daySessions: daySessions?.sessions,
                    attendanceSessions: latestAttendance?.sessions
                )
                switch mode {
                case .punchIn where hasPunchedInToday:
                    throw HRConvexAPIError.server("You have already clocked in today.")
                case .punchOut where !hasPunchedInToday:
                    throw HRConvexAPIError.server("No attendance found for today.")
                case .punchOut where clockedOutOnMobile:
                    throw HRConvexAPIError.server("You are already clocked out today.")
                default:
                    break
                }

                statusText = "Uploading photo..."
                guard let jpegData else {
                    throw HRConvexAPIError.server("Failed to encode selfie")
                }
                let photoStorageId = try await HRConvexAPIService.uploadPhoto(
                    token: token, imageData: jpegData
                )

                statusText = mode == .punchIn ? "Clocking in..." : "Clocking out..."

                switch mode {
                case .punchIn:
                    _ = try await HRConvexAPIService.punchIn(
                        token: token,
                        latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude,
                        address: address,
                        source: "mobile",
                        photo: photoStorageId,
                        deviceId: deviceId,
                        clientPunchTime: clientPunchTime
                    )
                case .punchOut:
                    try await HRConvexAPIService.punchOut(
                        token: token,
                        latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude,
                        address: address,
                        photo: photoStorageId,
                        deviceId: deviceId,
                        clientPunchTime: clientPunchTime
                    )
                }

                statusText = mode == .punchIn ? "Starting tracking..." : "Stopping tracking..."
                await GeoTrackBootstrapCoordinator.shared.sync(
                    reason: mode == .punchIn ? "attendance-punch-in" : "attendance-punch-out",
                    force: true
                )
                await loadCurrentAttendanceStatus()
                didQueueOffline = false
                onComplete?()
                completedAt = tapTime
                showSuccessSheet = true
            } catch let error as HRConvexAPIError {
                // Server was REACHED and rejected the punch (already clocked in/out,
                // HTTP error, unauthorized). Surface it — a genuine rejection must
                // not be silently queued.
                errorMessage = error.localizedDescription
            } catch {
                // Network / connectivity failure — DON'T lose the punch. Queue it with
                // the real tap time (and selfie) so it syncs when connectivity returns
                // and records the time the staff actually punched. Mirrors Android
                // HomeViewModel.enqueueOfflinePunch().
                let queued = await PendingPunchStore.shared.insert(
                    isPunchIn: mode == .punchIn,
                    clientPunchTime: clientPunchTime,
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude,
                    address: address,
                    photoData: jpegData,
                    deviceId: deviceId
                )
                if queued {
                    didQueueOffline = true
                    onComplete?()
                    completedAt = tapTime
                    showSuccessSheet = true
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func finishAfterSuccess() {
        showSuccessSheet = false
        dismiss()
    }

    @MainActor
    private func loadCurrentAttendanceStatus() async {
        guard let token = authStore.currentSession?.token else {
            currentAttendance = nil
            return
        }
        isStatusLoading = true
        defer { isStatusLoading = false }
        currentAttendance = try? await HRConvexAPIService.getTodayAttendance(token: token)
    }

    private var currentStatusText: String {
        if currentAttendance?.isOpen == true {
            if let time = formatAttendanceTime(currentAttendance?.firstPunchIn ?? currentAttendance?.punchInTime) {
                return "Clocked in at \(time)"
            }
            return "Active attendance session"
        }
        if currentAttendance?.hasPunchedIn == true {
            if let time = formatAttendanceTime(currentAttendance?.lastPunchOut ?? currentAttendance?.punchOutTime) {
                return "Clocked out at \(time)"
            }
            return "Attendance completed for today"
        }
        return "Not clocked in yet"
    }

    private var currentStatusBadge: String {
        if currentAttendance?.isOpen == true { return "Active" }
        if currentAttendance?.hasPunchedIn == true { return "Done" }
        return "Pending"
    }

    private var currentStatusIcon: String {
        if currentAttendance?.isOpen == true { return "clock.badge.checkmark.fill" }
        if currentAttendance?.hasPunchedIn == true { return "checkmark.seal.fill" }
        return "clock.fill"
    }

    private var currentStatusColor: Color {
        if currentAttendance?.isOpen == true { return .green }
        if currentAttendance?.hasPunchedIn == true { return .blue }
        return .orange
    }

    private var locationPlaceholderText: String {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "Location permission required"
        case .notDetermined:
            return "Checking location permission..."
        default:
            return "Getting location..."
        }
    }

    private func formatAttendanceTime(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? {
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: raw)
        }()
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

private struct PunchSuccessSheet: View {
    let mode: PunchFlowView.PunchMode
    let completedAt: Date
    let address: String?
    var offline: Bool = false
    let onDone: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private var title: String {
        if offline {
            return mode == .punchIn ? "Clock In Saved" : "Clock Out Saved"
        }
        return mode == .punchIn ? "Clock In Success" : "Clock Out Success"
    }

    private var message: String {
        if offline {
            return mode == .punchIn
                ? "Saved offline at this time — it will sync automatically when you're back online."
                : "Saved offline at this time — it will sync automatically when you're back online."
        }
        return mode == .punchIn
            ? "Your attendance is active and tracking has been synced."
            : "Your attendance session is closed and tracking has been synced."
    }

    private var accent: Color {
        mode == .punchIn ? .green : .orange
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.top, 18)

            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x475467))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            VStack(spacing: 8) {
                Label(Self.timeFormatter.string(from: completedAt), systemImage: "clock.fill")
                if let address, !address.isEmpty {
                    Label(address, systemImage: "location.fill")
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: 0x344054))
            .padding(.horizontal, 18)

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accent)
            .padding(.horizontal, 18)
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
        .background(.white)
    }
}

private extension UIImage {
    func attendanceUploadJPEGData(maxEdge: CGFloat, quality: CGFloat) -> Data? {
        let largestEdge = max(size.width, size.height)
        guard largestEdge > 0 else {
            return jpegData(compressionQuality: quality)
        }

        let scaleFactor = min(1, maxEdge / largestEdge)
        guard scaleFactor < 1 else {
            return jpegData(compressionQuality: quality)
        }

        let targetSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

// MARK: - Location Manager

@MainActor
@Observable
final class PunchLocationManager: NSObject, CLLocationManagerDelegate {
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        let status = manager.authorizationStatus
        authorizationStatus = status
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            currentLocation = loc
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[punch-location] error: \(error.localizedDescription)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }
}
