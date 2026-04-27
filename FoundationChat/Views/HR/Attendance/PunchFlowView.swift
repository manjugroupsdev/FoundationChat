import CoreLocation
import MapKit
import SwiftUI

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
    @State private var errorMessage: String?
    @State private var statusText: String?
    @State private var locationManager = PunchLocationManager()

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
            .sheet(isPresented: $showCamera) {
                PunchCameraView(capturedImage: $capturedImage)
            }
            .task {
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
                            Text("Getting location...")
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
                    Text("Waiting for GPS...")
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

        Task {
            defer {
                isSubmitting = false
                statusText = nil
            }
            do {
                statusText = "Uploading photo..."
                guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
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
                        photo: photoStorageId
                    )
                case .punchOut:
                    try await HRConvexAPIService.punchOut(
                        token: token,
                        latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude,
                        address: address,
                        photo: photoStorageId
                    )
                }

                onComplete?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
