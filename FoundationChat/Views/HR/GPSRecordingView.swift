import Combine
import MapKit
import SwiftUI
import PhotosUI

struct GPSRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tracker: LocationTracker?
    @State private var purpose = ""
    @State private var remarks = ""
    @State private var isStarting = false
    @State private var isEnding = false
    @State private var errorMessage: String?
    @State private var tripResult: GPSSessionEndResult?
    @State private var showTripSummary = false
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var elapsedText = "00:00:00"
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var showMarkLocationAlert = false
    @State private var markLocationDescription = ""

    private var isTripActive: Bool { tracker?.isTripActive ?? false }

    var body: some View {
        NavigationStack {
            if !isTripActive && tripResult == nil {
                startTripForm
            } else if isTripActive {
                activeTripView
            }
        }
        .alert("Trip Completed", isPresented: $showTripSummary) {
            Button("Done") { dismiss() }
        } message: {
            if let result = tripResult {
                Text("Waypoints: \(result.totalWaypoints ?? 0)\nDistance: \(String(format: "%.2f", result.totalDistanceKm ?? 0)) km\nDuration: \(result.totalDuration ?? "--")")
            }
        }
        .alert("Mark Location", isPresented: $showMarkLocationAlert) {
            TextField("Description", text: $markLocationDescription)
            Button("Mark") {
                tracker?.markLocation(description: markLocationDescription)
                markLocationDescription = ""
            }
            Button("Cancel", role: .cancel) { markLocationDescription = "" }
        }
    }

    private var startTripForm: some View {
        Form {
            Section("Trip Details") {
                TextField("Purpose (e.g., Client Visit)", text: $purpose)
                TextField("Remarks (optional)", text: $remarks, axis: .vertical)
                    .lineLimit(2...4)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }

            Section {
                Button {
                    Task { await startTrip() }
                } label: {
                    HStack {
                        Spacer()
                        if isStarting {
                            ProgressView()
                        } else {
                            Label("Start Trip", systemImage: "location.fill")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStarting)
            }
        }
        .navigationTitle("New Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var activeTripView: some View {
        VStack(spacing: 0) {
            // Map
            Map(position: $mapPosition) {
                if !routeCoordinates.isEmpty {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(.blue, lineWidth: 3)
                }
                if let loc = tracker?.lastLocation {
                    Annotation("You", coordinate: loc.coordinate) {
                        ZStack {
                            Circle().fill(.blue).frame(width: 16, height: 16)
                            Circle().strokeBorder(.white, lineWidth: 2).frame(width: 16, height: 16)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // Controls
            VStack(spacing: 12) {
                // Timer & stats
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(elapsedText)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                        Text("Ref: \(tracker?.activeRefNo ?? "--")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(tracker?.waypointCount ?? 0)")
                            .font(.title2.weight(.bold))
                        Text("waypoints")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        showMarkLocationAlert = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                            Text("Mark")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        VStack(spacing: 4) {
                            Image(systemName: "camera.circle.fill")
                                .font(.title2)
                            Text("Photo")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await endTrip() }
                    } label: {
                        VStack(spacing: 4) {
                            if isEnding {
                                ProgressView()
                            } else {
                                Image(systemName: "stop.circle.fill")
                                    .font(.title2)
                            }
                            Text("End Trip")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isEnding)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(purpose)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .onReceive(timer) { _ in
            updateElapsed()
            updateRoute()
        }
        .onChange(of: selectedPhoto) {
            Task { await uploadPhoto() }
        }
    }

    private func startTrip() async {
        isStarting = true
        errorMessage = nil

        guard HRAPIService.shared.isMmsLoggedIn else {
            errorMessage = "Please log in again to use GPS tracking."
            isStarting = false
            return
        }

        do {
            if tracker == nil {
                tracker = LocationTracker()
            }
            try await tracker?.startTrip(
                purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                remarks: remarks.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isStarting = false
    }

    private func endTrip() async {
        isEnding = true
        do {
            tripResult = try await tracker?.endTrip()
            showTripSummary = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isEnding = false
    }

    private func uploadPhoto() async {
        guard let item = selectedPhoto else { return }
        selectedPhoto = nil
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        do {
            _ = try await tracker?.capturePhoto(imageData: data)
        } catch {}
    }

    private func updateElapsed() {
        guard let start = tracker?.tripStartTime else { return }
        let interval = Date().timeIntervalSince(start)
        let h = Int(interval / 3600)
        let m = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        let s = Int(interval.truncatingRemainder(dividingBy: 60))
        elapsedText = String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func updateRoute() {
        if let loc = tracker?.lastLocation {
            let coord = loc.coordinate
            if routeCoordinates.isEmpty || routeCoordinates.last?.latitude != coord.latitude || routeCoordinates.last?.longitude != coord.longitude {
                routeCoordinates.append(coord)
            }
        }
    }
}
