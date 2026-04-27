import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// In-app navigation page for an active site visit.
///
/// Two entry modes (mirrors Android `TripNavigationFragment`):
/// - Existing scheduled visit: pass `visitId`.
/// - Ad-hoc trip from a place: pass `placeId` (creates the visit then starts it).
///
/// Once started: map renders origin + destination + a straight-line polyline.
/// "Mark Arrived" → camera → photo upload → request arrival OTP → OTP sheet
/// → verify → completeVisit → dismiss.
struct TripNavigationView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let visitIdArg: String?
    let placeIdArg: String?
    let placeName: String
    let placeAddress: String?
    let destination: CLLocationCoordinate2D?
    let initialStatus: String?

    @State private var resolvedVisitId: String?
    @State private var visitStarted = false
    @State private var statusLine: String = "Starting…"
    @State private var isLoadingStart = true
    @State private var startError: String?

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var locationManager = TripLocationManager()

    @State private var arrivalInProgress = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var pendingStorageId: String?
    @State private var arrivalStatusText: String?

    @State private var showOtpSheet = false
    @State private var otpPhoneMasked: String?
    @State private var otpExpiresIn: Int = 600
    @State private var otpResendCooldown: Int = 60
    @State private var otpLat: Double = 0
    @State private var otpLng: Double = 0

    @State private var errorMessage: String?

    private let geoAPI = GeoTrackAPIService.shared

    init(
        visitId: String? = nil,
        placeId: String? = nil,
        placeName: String,
        placeAddress: String? = nil,
        destination: CLLocationCoordinate2D? = nil,
        initialStatus: String? = nil
    ) {
        self.visitIdArg = visitId
        self.placeIdArg = placeId
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.destination = destination
        self.initialStatus = initialStatus
    }

    private var currentLocation: CLLocationCoordinate2D? {
        locationManager.currentLocation?.coordinate
    }

    private var hasActiveVisit: Bool {
        resolvedVisitId != nil && visitStarted
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {
                        mapSection
                        destinationCard
                        if let arrivalStatusText {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(arrivalStatusText).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                        }
                        actionButtons
                    }
                    .padding()
                }

                if isLoadingStart {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(statusLine).font(.subheadline).foregroundStyle(.white)
                    }
                    .padding(20)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Trip to \(placeName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(arrivalInProgress)
                }
            }
            .sheet(isPresented: $showCamera) {
                PunchCameraView(capturedImage: $capturedImage)
            }
            .sheet(isPresented: $showOtpSheet, onDismiss: {
                if !visitCompletedSuccessfully {
                    arrivalInProgress = false
                    arrivalStatusText = nil
                }
            }) {
                if let id = resolvedVisitId {
                    ArrivalOtpSheet(
                        visitId: id,
                        phoneMasked: otpPhoneMasked,
                        initialExpiresIn: otpExpiresIn,
                        initialResendCooldown: otpResendCooldown,
                        lat: otpLat,
                        lng: otpLng,
                        onVerified: { otp in
                            showOtpSheet = false
                            Task { await completeVisitAfterOtp(otp: otp) }
                        }
                    )
                }
            }
            .task {
                locationManager.requestLocation()
                await ensureVisitStarted()
            }
            .onChange(of: capturedImage) { _, image in
                guard let image else { return }
                Task { await uploadPhotoThenRequestOtp(image: image) }
            }
            .onChange(of: locationManager.currentLocation) { _, newLoc in
                guard let newLoc else { return }
                if mapPosition.followsUserLocation == false {
                    updateMapBounds(currentCoord: newLoc.coordinate)
                }
            }
        }
    }

    @State private var visitCompletedSuccessfully = false

    // MARK: - Map

    private var mapSection: some View {
        Map(position: $mapPosition) {
            if let dest = destination {
                Annotation(placeName, coordinate: dest) {
                    ZStack {
                        Circle().fill(.red).frame(width: 26, height: 26)
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.white)
                            .font(.title3)
                    }
                }
            }
            if let me = currentLocation {
                Annotation("You", coordinate: me) {
                    ZStack {
                        Circle().fill(.blue.opacity(0.25)).frame(width: 36, height: 36)
                        Circle().fill(.blue).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            if let dest = destination, let me = currentLocation {
                MapPolyline(coordinates: [me, dest])
                    .stroke(.purple, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if destination == nil {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Text("Destination unavailable")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    // MARK: - Destination Card

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(placeName).font(.headline)
                    Text(placeAddress?.isEmpty == false ? placeAddress! : "Address not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openInAppleMaps()
                } label: {
                    Label("Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(destination == nil)
            }
            HStack(spacing: 16) {
                Label(distanceText, systemImage: "ruler")
                Label(etaText, systemImage: "clock")
                Label(statusBadge, systemImage: "circle.fill")
                    .foregroundStyle(statusColor)
            }
            .font(.caption)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                onArrivalSwipeConfirmed()
            } label: {
                HStack {
                    if arrivalInProgress {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(arrivalInProgress ? "Working…" : "Mark Arrived")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!hasActiveVisit || arrivalInProgress || isLoadingStart)
        }
    }

    // MARK: - Visit lifecycle

    private func ensureVisitStarted() async {
        isLoadingStart = true
        statusLine = "Starting…"

        let alreadyInFlight = (initialStatus ?? "").uppercased() == "IN_PROGRESS"

        do {
            let token = try requireToken()

            // Resolve visit id (create one for ad-hoc trips).
            let effectiveVisitId: String
            if let existing = visitIdArg {
                effectiveVisitId = existing
            } else if let placeId = placeIdArg {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                let today = df.string(from: Date())
                geoAPI.tokenProvider = { token }
                effectiveVisitId = try await geoAPI.createVisit(
                    clientPlaceId: placeId,
                    scheduledDate: today,
                    notes: "Ad-hoc trip started from mobile"
                )
            } else {
                throw TripError.message("Missing visit or place identifier")
            }
            resolvedVisitId = effectiveVisitId

            if !alreadyInFlight {
                geoAPI.tokenProvider = { token }
                let loc = locationManager.currentLocation
                try await geoAPI.startVisit(
                    visitId: effectiveVisitId,
                    lat: loc?.coordinate.latitude,
                    lng: loc?.coordinate.longitude
                )
            }

            visitStarted = true
            statusLine = alreadyInFlight ? "In progress" : "On the way"
            isLoadingStart = false
        } catch {
            startError = error.localizedDescription
            errorMessage = "Failed to start trip: \(error.localizedDescription)"
            isLoadingStart = false
        }
    }

    // MARK: - Arrival flow

    private func onArrivalSwipeConfirmed() {
        guard let _ = resolvedVisitId, visitStarted else {
            errorMessage = "Trip is still starting"
            return
        }
        guard !arrivalInProgress else { return }
        arrivalInProgress = true
        errorMessage = nil
        capturedImage = nil
        showCamera = true
    }

    private func uploadPhotoThenRequestOtp(image: UIImage) async {
        guard let id = resolvedVisitId else {
            arrivalInProgress = false
            return
        }
        arrivalStatusText = "Uploading photo…"
        do {
            let token = try requireToken()
            guard let jpeg = image.jpegData(compressionQuality: 0.7) else {
                throw TripError.message("Could not encode photo")
            }
            let storageId = try await HRConvexAPIService.uploadPhoto(token: token, imageData: jpeg)
            pendingStorageId = storageId

            arrivalStatusText = "Sending OTP to client…"
            // Use freshest GPS for geofence check.
            locationManager.requestLocation()
            try? await Task.sleep(for: .milliseconds(500))
            guard let loc = locationManager.currentLocation else {
                throw TripError.message("Could not read your GPS. Try again in open sky.")
            }

            geoAPI.tokenProvider = { token }
            let resp = try await geoAPI.requestArrivalOtp(
                visitId: id,
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude
            )
            otpPhoneMasked = resp.contactPhoneMasked
            otpExpiresIn = resp.otpExpiresInSeconds ?? 600
            otpResendCooldown = resp.resendCooldownSeconds ?? 60
            otpLat = loc.coordinate.latitude
            otpLng = loc.coordinate.longitude
            arrivalStatusText = nil
            showOtpSheet = true
        } catch {
            arrivalInProgress = false
            arrivalStatusText = nil
            errorMessage = error.localizedDescription
            capturedImage = nil
        }
    }

    private func completeVisitAfterOtp(otp: String) async {
        guard let id = resolvedVisitId else { return }
        arrivalStatusText = "Completing visit…"
        do {
            let token = try requireToken()
            geoAPI.tokenProvider = { token }
            let loc = locationManager.currentLocation
            var remarks = "Arrival verified"
            if let storageId = pendingStorageId, !storageId.isEmpty {
                remarks += " | photo:\(storageId)"
            }
            if !otp.isEmpty {
                remarks += " | otp:\(otp)"
            }
            try await geoAPI.completeVisit(
                visitId: id,
                lat: loc?.coordinate.latitude,
                lng: loc?.coordinate.longitude,
                remarks: remarks
            )
            visitCompletedSuccessfully = true
            arrivalStatusText = nil
            dismiss()
        } catch {
            arrivalStatusText = nil
            arrivalInProgress = false
            errorMessage = "Failed to complete: \(error.localizedDescription)"
        }
    }

    // MARK: - Maps + helpers

    private func openInAppleMaps() {
        guard let dest = destination else { return }
        let location = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = placeName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func updateMapBounds(currentCoord: CLLocationCoordinate2D) {
        guard let dest = destination else {
            mapPosition = .camera(MapCamera(centerCoordinate: currentCoord, distance: 1500))
            return
        }
        let midLat = (currentCoord.latitude + dest.latitude) / 2.0
        let midLng = (currentCoord.longitude + dest.longitude) / 2.0
        let latDelta = abs(currentCoord.latitude - dest.latitude) * 1.6 + 0.005
        let lngDelta = abs(currentCoord.longitude - dest.longitude) * 1.6 + 0.005
        mapPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: midLng),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        ))
    }

    private var distanceMeters: Double? {
        guard let dest = destination, let me = currentLocation else { return nil }
        let a = CLLocation(latitude: me.latitude, longitude: me.longitude)
        let b = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        return a.distance(from: b)
    }

    private var distanceText: String {
        guard let m = distanceMeters else { return "—" }
        if m >= 1000 { return String(format: "%.1f km", m / 1000) }
        return "\(Int(m.rounded())) m"
    }

    private var etaText: String {
        guard let m = distanceMeters else { return "—" }
        // Rough urban-driving ETA: 30 km/h average (matches Android fallback).
        let minutes = Int((m / 500.0).rounded())
        if minutes < 1 { return "<1 min" }
        return "\(minutes) min"
    }

    private var statusBadge: String {
        if arrivalInProgress { return "Arriving" }
        if visitStarted { return "Active" }
        return "Starting"
    }

    private var statusColor: Color {
        if arrivalInProgress { return .orange }
        if visitStarted { return .green }
        return .gray
    }

    private func requireToken() throws -> String {
        if let token = authStore.currentSession?.token { return token }
        if let token = try KeychainTokenStore().load()?.token { return token }
        throw TripError.message("Not signed in")
    }
}

// MARK: - Errors

private enum TripError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

// MARK: - Location

@MainActor
@Observable
final class TripLocationManager: NSObject, CLLocationManagerDelegate {
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
        Task { @MainActor in currentLocation = loc }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Swallow: ETA/distance fall back to "—" when no fix available.
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
