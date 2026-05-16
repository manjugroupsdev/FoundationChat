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
/// "Mark Arrived" → request arrival OTP → camera → photo upload → OTP sheet
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
    let tripType: String?
    let clientPlaceVisitId: String?
    let cpClientMet: Bool?
    let cpOutcome: String?
    let requiresOpenAttendance: Bool
    let onTripChanged: (() -> Void)?

    @State private var resolvedVisitId: String?
    @State private var visitStarted = false
    @State private var statusLine: String = "Starting…"
    @State private var isLoadingStart = false
    @State private var startError: String?

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var locationManager = TripLocationManager()
    @State private var resolvedDestination: CLLocationCoordinate2D?
    @State private var resolvedAddress: String?
    @State private var routeInfo: GeoTrackDirectionsClient.DirectionsResult?
    @State private var isRouteLoading = false
    @State private var lastRouteKey: String?
    @State private var routeWarning: String?

    @State private var arrivalInProgress = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var pendingStorageId: String?
    @State private var arrivalStatusText: String?

    @State private var showOtpSheet = false
    @State private var showCpCompletionSheet = false
    @State private var showCpClientSeenSheet = false
    @State private var showCpTripCompletedSheet = false
    @State private var cpNoPathPhotoCapture = false
    @State private var completeWithClientNotSeenSheet = false
    @State private var otpPhoneMasked: String?
    @State private var otpExpiresIn: Int = 600
    @State private var otpResendCooldown: Int = 60
    @State private var otpLat: Double = 0
    @State private var otpLng: Double = 0

    @State private var errorMessage: String?

    private let geoAPI = GeoTrackAPIService.shared
    private let directionsClient = GeoTrackDirectionsClient()

    init(
        visitId: String? = nil,
        placeId: String? = nil,
        placeName: String,
        placeAddress: String? = nil,
        destination: CLLocationCoordinate2D? = nil,
        initialStatus: String? = nil,
        tripType: String? = nil,
        clientPlaceVisitId: String? = nil,
        cpClientMet: Bool? = nil,
        cpOutcome: String? = nil,
        requiresOpenAttendance: Bool = false,
        onTripChanged: (() -> Void)? = nil
    ) {
        self.visitIdArg = visitId
        self.placeIdArg = placeId
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.destination = destination
        self.initialStatus = initialStatus
        self.tripType = tripType
        self.clientPlaceVisitId = clientPlaceVisitId
        self.cpClientMet = cpClientMet
        self.cpOutcome = cpOutcome
        self.requiresOpenAttendance = requiresOpenAttendance
        self.onTripChanged = onTripChanged
    }

    private var currentLocation: CLLocationCoordinate2D? {
        locationManager.currentLocation?.coordinate
    }

    private var effectiveDestination: CLLocationCoordinate2D? {
        destination ?? resolvedDestination
    }

    private var hasActiveVisit: Bool {
        resolvedVisitId != nil && visitStarted
    }

    private var currentDistanceMeters: Double? {
        guard let dest = effectiveDestination, let me = currentLocation else { return nil }
        return CLLocation(latitude: me.latitude, longitude: me.longitude)
            .distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
    }

    private var canShowLiveRoute: Bool {
        guard let distance = currentDistanceMeters else { return false }
        return distance <= 300_000
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    tripInfoCard
                    mapSection
                    tripProgressCard
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
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(hex: 0xF2F5FA).ignoresSafeArea())
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showCamera) {
            PunchCameraView(capturedImage: $capturedImage)
        }
        .sheet(isPresented: $showCpClientSeenSheet, onDismiss: {
            if !arrivalInProgress && !visitCompletedSuccessfully {
                arrivalStatusText = nil
            }
        }) {
            CpClientSeenSheet(
                onYes: {
                    showCpClientSeenSheet = false
                    startCpYesPath()
                },
                onNo: {
                    showCpClientSeenSheet = false
                    startCpNoPath()
                }
            )
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.hidden)
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
        .sheet(isPresented: $showCpCompletionSheet, onDismiss: {
            if !visitCompletedSuccessfully {
                arrivalInProgress = false
                arrivalStatusText = nil
            }
        }) {
            if let cpVisitId = clientPlaceVisitId {
                CompleteCpVisitSheet(
                    cpVisitId: cpVisitId,
                    initialOutcome: cpOutcome,
                    onCompleted: {
                        Task { await completeVisitAfterCpOutcome() }
                    }
                )
                .environment(authStore)
            }
        }
        .sheet(isPresented: $showCpTripCompletedSheet) {
            CpTripCompletedSheet {
                showCpTripCompletedSheet = false
                dismiss()
            }
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.hidden)
        }
        .task {
            locationManager.requestLocation()
            initializeTripState()
            updateMapForKnownDestination()
            await refreshRouteIfPossible(force: true)
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            Task {
                if cpNoPathPhotoCapture {
                    await uploadPhotoThenCompleteWithoutClient(image: image)
                } else {
                    await uploadPhotoThenShowOtp(image: image)
                }
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLoc in
            guard let newLoc else { return }
            if mapPosition.followsUserLocation == false {
                updateMapBounds(currentCoord: newLoc.coordinate)
            }
            Task { await refreshRouteIfPossible() }
        }
    }

    @State private var visitCompletedSuccessfully = false

    // MARK: - Map

    private var tripTopBar: some View {
        ZStack {
            Text("Trip Details")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 32, height: 32)
                        .background(Color.white, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(arrivalInProgress || isLoadingStart)

                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 60)
        .background(.white)
    }

    private var mapSection: some View {
        Map(position: $mapPosition) {
            if let dest = effectiveDestination {
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
            if routeInfo?.polyline.isEmpty == false {
                MapPolyline(coordinates: routeInfo?.polyline ?? [])
                    .stroke(Color(hex: 0x0B56A8), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            } else if canShowLiveRoute, let dest = effectiveDestination, let me = currentLocation {
                MapPolyline(coordinates: [me, dest])
                    .stroke(Color(hex: 0x0B56A8).opacity(0.72), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [8, 8]))
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            if effectiveDestination == nil {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Text(isRouteLoading ? "Resolving destination…" : "Destination unavailable")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(hex: 0xEEF0F5), lineWidth: 1)
        )
    }

    private var tripInfoCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Text(String(clientDisplayName.prefix(1)).uppercased())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x475467))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: 0xF2F4F7), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(clientDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x111827))
                        .lineLimit(1)
                    Text("Client")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0x667085))
                }

                Spacer()

                statusPill
            }

            HStack(spacing: 10) {
                VStack(spacing: 14) {
                    tripMetric(icon: "building.2.fill", label: "Site/Client", value: placeName)
                    tripMetric(icon: "road.lanes", label: "Distance", value: distanceText)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color(hex: 0xE5E7EB))
                    .frame(width: 1, height: 86)

                VStack(spacing: 14) {
                    tripMetric(icon: "clock.fill", label: "Time", value: originText)
                    tripMetric(icon: "timer", label: "ETA", value: etaText)
                }
                .frame(maxWidth: .infinity)
            }

            if let routeWarning {
                Text(routeWarning)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xB54708))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: 0xEEF0F5), lineWidth: 1)
        )
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: 0x19B900))
                .frame(width: 5, height: 5)
            Text(statusBadge)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusTextColor)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(statusBackgroundColor, in: Capsule())
    }

    private func tripMetric(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))
                .frame(width: 40, height: 40)
                .background(Color(hex: 0xF2F4F7), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0x667085))
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0x111827))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
    }

    private var tripProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Trip Progress")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                Text(tripProgressStage.stateLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tripProgressStage.stateColor)
            }

            HStack(spacing: 8) {
                TripProgressStep(
                    title: "Start",
                    systemImage: "play.fill",
                    state: tripProgressStage.stepState(for: 0)
                )
                TripProgressLine(isActive: tripProgressStage.rawValue >= 1)
                TripProgressStep(
                    title: "Enroute",
                    systemImage: "location.fill",
                    state: tripProgressStage.stepState(for: 1)
                )
                TripProgressLine(isActive: tripProgressStage.rawValue >= 2)
                TripProgressStep(
                    title: "Reaching",
                    systemImage: "mappin.and.ellipse",
                    state: tripProgressStage.stepState(for: 2)
                )
                TripProgressLine(isActive: tripProgressStage.rawValue >= 3)
                TripProgressStep(
                    title: "Complete",
                    systemImage: "flag.fill",
                    state: tripProgressStage.stepState(for: 3)
                )
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: 0xEEF0F5), lineWidth: 1)
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                if hasActiveVisit {
                    if isCpVisit && tripProgressStage == .reached && shouldCollectCpOutcome {
                        showCpCompletionSheet = true
                    } else {
                        onArrivalSwipeConfirmed()
                    }
                } else {
                    Task { await ensureVisitStarted() }
                }
            } label: {
                HStack {
                    if arrivalInProgress || isLoadingStart {
                        ProgressView().tint(.white)
                    } else if hasActiveVisit {
                        Image(systemName: "checkmark.circle.fill")
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(primaryActionTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x1ECB09), Color(hex: 0x3D9D02)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .disabled(arrivalInProgress || isLoadingStart)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: - Visit lifecycle

    private func initializeTripState() {
        let normalizedStatus = normalizedInitialStatus
        resolvedVisitId = visitIdArg
        visitStarted = [
            "in-progress",
            "in_progress",
            "ongoing",
            "started",
            "active",
            "arrived",
            "arrival_verified",
            "arrival-verified",
            "completed",
            "complete",
            "done",
            "closed"
        ].contains(normalizedStatus)
        statusLine = visitStarted ? "In progress" : "Start"
        isLoadingStart = false
    }

    private func ensureVisitStarted() async {
        isLoadingStart = true
        statusLine = "Starting…"

        let normalizedStatus = normalizedInitialStatus
        let alreadyInFlight = [
            "in-progress",
            "in_progress",
            "ongoing",
            "started",
            "active",
            "arrived",
            "arrival_verified",
            "arrival-verified"
        ].contains(normalizedStatus)
        let alreadyCompleted = ["completed", "complete", "done", "closed"].contains(normalizedStatus)

        do {
            guard !alreadyCompleted else {
                resolvedVisitId = visitIdArg
                visitStarted = true
                isLoadingStart = false
                return
            }
            let token = try requireToken()
            if requiresOpenAttendance && !alreadyInFlight {
                let canStart = await hasOpenAttendanceSession(token: token)
                guard canStart else {
                    throw TripError.message("Please clock in before starting a trip.")
                }
            }

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
            onTripChanged?()
            await GeoTrackBootstrapCoordinator.shared.sync(reason: "visit-started", force: true)
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
        if isCpVisit {
            checkReachingAndAskClientSeen()
            return
        }
        Task { await requestArrivalOtpThenOpenCamera() }
    }

    private func checkReachingAndAskClientSeen() {
        locationManager.requestLocation()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard let dest = effectiveDestination, let loc = locationManager.currentLocation else {
                arrivalInProgress = false
                errorMessage = "Could not verify you are near the client place."
                return
            }
            let distance = CLLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                .distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
            guard distance <= 500 else {
                arrivalInProgress = false
                errorMessage = "You are \(formatDistance(distance)) away. Move within 500 m to complete."
                return
            }
            arrivalStatusText = nil
            showCpClientSeenSheet = true
        }
    }

    private func startCpYesPath() {
        cpNoPathPhotoCapture = false
        capturedImage = nil
        Task { await requestArrivalOtpThenOpenCamera() }
    }

    private func startCpNoPath() {
        cpNoPathPhotoCapture = true
        capturedImage = nil
        showCamera = true
    }

    private func requestArrivalOtpThenOpenCamera() async {
        guard let id = resolvedVisitId else {
            arrivalInProgress = false
            return
        }
        arrivalStatusText = "Checking location..."
        do {
            let token = try requireToken()
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
            arrivalStatusText = "Opening camera..."
            capturedImage = nil
            showCamera = true
        } catch {
            arrivalInProgress = false
            arrivalStatusText = nil
            errorMessage = error.localizedDescription
        }
    }

    private func uploadPhotoThenShowOtp(image: UIImage) async {
        arrivalStatusText = "Uploading photo…"
        do {
            let token = try requireToken()
            guard let jpeg = image.jpegData(compressionQuality: 0.7) else {
                throw TripError.message("Could not encode photo")
            }
            let storageId = try await HRConvexAPIService.uploadPhoto(token: token, imageData: jpeg)
            pendingStorageId = storageId
            arrivalStatusText = nil
            showOtpSheet = true
        } catch {
            arrivalInProgress = false
            arrivalStatusText = nil
            errorMessage = error.localizedDescription
            capturedImage = nil
        }
    }

    private func uploadPhotoThenCompleteWithoutClient(image: UIImage) async {
        guard let id = resolvedVisitId, let cpVisitId = clientPlaceVisitId else {
            arrivalInProgress = false
            cpNoPathPhotoCapture = false
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

            arrivalStatusText = "Completing visit…"
            try await MarketingConvexAPIService.markClientMet(
                token: token,
                request: MarkClientMetRequest(
                    id: cpVisitId,
                    clientMet: false,
                    clientNoShowReason: "Client not seen"
                )
            )
            try await MarketingConvexAPIService.setCpVisitOutcome(
                token: token,
                request: SetCpVisitOutcomeRequest(
                    id: cpVisitId,
                    outcome: "other",
                    postponeReasons: nil,
                    notes: "Client not seen"
                )
            )
            cpNoPathPhotoCapture = false
            completeWithClientNotSeenSheet = true
            await completeGeoTrackVisit(visitId: id)
        } catch {
            arrivalInProgress = false
            cpNoPathPhotoCapture = false
            arrivalStatusText = nil
            errorMessage = error.localizedDescription
            capturedImage = nil
        }
    }

    private func completeVisitAfterOtp(otp _: String) async {
        guard let id = resolvedVisitId else { return }
        if shouldCollectCpOutcome {
            arrivalStatusText = nil
            showCpCompletionSheet = true
            return
        }
        await completeGeoTrackVisit(visitId: id)
    }

    private func completeVisitAfterCpOutcome() async {
        guard let id = resolvedVisitId else { return }
        await completeGeoTrackVisit(visitId: id)
    }

    private func completeGeoTrackVisit(visitId id: String) async {
        arrivalStatusText = "Completing visit…"
        do {
            let token = try requireToken()
            geoAPI.tokenProvider = { token }
            let loc = locationManager.currentLocation
            // Keep parity with Android by sending the photo id as a dedicated field.
            // The OTP itself is verified before completion, so remarks stay user-readable.
            let remarks = "Arrival verified"
            try await geoAPI.completeVisit(
                visitId: id,
                lat: loc?.coordinate.latitude,
                lng: loc?.coordinate.longitude,
                remarks: remarks,
                arrivalPhotoStorageId: pendingStorageId
            )
            visitCompletedSuccessfully = true
            arrivalStatusText = nil
            onTripChanged?()
            if completeWithClientNotSeenSheet {
                completeWithClientNotSeenSheet = false
                showCpTripCompletedSheet = true
            } else {
                dismiss()
            }
        } catch {
            arrivalStatusText = nil
            arrivalInProgress = false
            errorMessage = "Failed to complete: \(error.localizedDescription)"
        }
    }

    // MARK: - Maps + helpers

    private func openInAppleMaps() {
        guard let dest = effectiveDestination else { return }
        let location = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = placeName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func updateMapBounds(currentCoord: CLLocationCoordinate2D) {
        guard let dest = effectiveDestination else {
            mapPosition = .camera(MapCamera(centerCoordinate: currentCoord, distance: 1500))
            return
        }
        guard canShowLiveRoute else {
            mapPosition = .camera(MapCamera(centerCoordinate: dest, distance: 1800))
            routeWarning = "Current GPS is far from destination. Set simulator/device location near the visit to show live route."
            return
        }
        routeWarning = nil
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
        if let routeInfo { return Double(routeInfo.distanceMeters) }
        return currentDistanceMeters
    }

    private var distanceText: String {
        if let routeInfo { return routeInfo.distanceText }
        guard let m = distanceMeters else { return "—" }
        if m >= 1000 { return String(format: "%.1f km", m / 1000) }
        return "\(Int(m.rounded())) m"
    }

    private var etaText: String {
        if let routeInfo { return routeInfo.durationText }
        guard let m = distanceMeters else { return "—" }
        // Rough urban-driving ETA: 30 km/h average (matches Android fallback).
        let minutes = Int((m / 500.0).rounded())
        if minutes < 1 { return "<1 min" }
        return "\(minutes) min"
    }

    private var displayAddress: String {
        if let resolvedAddress, !resolvedAddress.isEmpty { return resolvedAddress }
        if let placeAddress, !placeAddress.isEmpty { return placeAddress }
        return "Address not available"
    }

    private var shouldCollectCpOutcome: Bool {
        guard let clientPlaceVisitId, !clientPlaceVisitId.isEmpty else { return false }
        guard cpClientMet != true || (cpOutcome ?? "").isEmpty else { return false }
        return (tripType ?? "").lowercased() == "client_place"
    }

    private var isCpVisit: Bool {
        guard clientPlaceVisitId?.isEmpty == false else { return false }
        return (tripType ?? "").lowercased() == "client_place"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
        return "\(Int(meters.rounded())) m"
    }

    private func refreshRouteIfPossible(force: Bool = false) async {
        guard let current = currentLocation else { return }
        guard let token = try? requireToken() else { return }
        geoAPI.tokenProvider = { token }

        let dest: CLLocationCoordinate2D?
        if let effectiveDestination {
            dest = effectiveDestination
        } else if let address = placeAddress, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isRouteLoading = true
            let geocode = await directionsClient.geocodeAddress(address)
            resolvedDestination = geocode?.coordinate
            resolvedAddress = geocode?.formattedAddress
            dest = geocode?.coordinate
            updateMapForKnownDestination()
        } else {
            dest = nil
        }

        guard let dest else {
            isRouteLoading = false
            return
        }

        guard canShowLiveRoute else {
            routeInfo = nil
            isRouteLoading = false
            updateMapForKnownDestination()
            routeWarning = "Current GPS is far from destination. Set simulator/device location near the visit to show live route."
            return
        }
        routeWarning = nil

        let routeKey = "\(Int(current.latitude * 10_000)):\(Int(current.longitude * 10_000)):\(Int(dest.latitude * 10_000)):\(Int(dest.longitude * 10_000))"
        guard force || routeKey != lastRouteKey else {
            isRouteLoading = false
            return
        }
        lastRouteKey = routeKey
        isRouteLoading = true
        defer { isRouteLoading = false }

        routeInfo = await directionsClient.fetchDriving(origin: current, destination: dest)
        updateMapBounds(currentCoord: current)
    }

    private var statusBadge: String {
        if arrivalInProgress { return "Arriving" }
        switch tripProgressStage {
        case .complete: return "Complete"
        case .reached, .reaching: return "Reaching"
        case .started: return "Enroute"
        case .notStarted: return "Start"
        }
    }

    private var tripProgressStage: TripProgressStage {
        let normalizedStatus = normalizedInitialStatus
        if visitCompletedSuccessfully || ["completed", "complete", "done", "closed"].contains(normalizedStatus) {
            return .complete
        }
        if arrivalInProgress {
            return .reached
        }
        if ["arrived", "arrival_verified", "arrival-verified"].contains(normalizedStatus) {
            return .reached
        }
        if visitStarted {
            if let meters = currentDistanceMeters, meters <= 500 {
                return .reaching
            }
            return .started
        }
        return .notStarted
    }

    private var normalizedInitialStatus: String {
        (initialStatus ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var clientDisplayName: String {
        let formatted = placeName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        return formatted.isEmpty ? "Client" : formatted
    }

    private var originText: String {
        if isRouteLoading { return "Routing..." }
        if currentLocation != nil { return "Current Location" }
        return "Locating..."
    }

    private var primaryActionTitle: String {
        if isLoadingStart { return "Starting..." }
        if arrivalInProgress { return "Working..." }
        if !hasActiveVisit { return "Start Trip" }
        if isCpVisit && tripProgressStage == .reached && shouldCollectCpOutcome {
            return "Complete CP details"
        }
        return "Swipe to Complete Trip"
    }

    private var statusTextColor: Color {
        switch tripProgressStage {
        case .notStarted: return Color(hex: 0x169B2F)
        case .started, .reaching, .reached: return Color(hex: 0xB54708)
        case .complete: return Color(hex: 0x475467)
        }
    }

    private var statusBackgroundColor: Color {
        switch tripProgressStage {
        case .notStarted: return Color(hex: 0xE8F7EC)
        case .started, .reaching, .reached: return Color(hex: 0xFFF4E5)
        case .complete: return Color(hex: 0xF2F4F7)
        }
    }

    private var statusColor: Color {
        if arrivalInProgress { return .orange }
        switch tripProgressStage {
        case .complete: return .secondary
        case .started, .reaching, .reached: return .green
        case .notStarted: return .gray
        }
    }

    private func requireToken() throws -> String {
        if let token = authStore.currentSession?.token { return token }
        if let token = try KeychainTokenStore().load()?.token { return token }
        throw TripError.message("Not signed in")
    }

    private func hasOpenAttendanceSession(token: String) async -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        async let attendance = try? HRConvexAPIService.getTodayAttendance(token: token)
        async let sessions = try? HRConvexAPIService.getDaySessions(token: token, date: today)
        let todayAttendance = await attendance
        let daySessions = await sessions
        return todayAttendance?.isOpen == true || daySessions?.hasOpenSession == true
    }

    private func updateMapForKnownDestination() {
        if let dest = effectiveDestination {
            mapPosition = .camera(MapCamera(centerCoordinate: dest, distance: 1800))
        }
    }
}

private enum TripProgressStage: Int {
    case notStarted = 0
    case started = 1
    case reaching = 2
    case reached = 3
    case complete = 4

    var stateLabel: String {
        switch self {
        case .notStarted: return "Not Started"
        case .started: return "Started"
        case .reaching: return "En Route"
        case .reached: return "Reached"
        case .complete: return "Completed"
        }
    }

    var stateColor: Color {
        self == .notStarted ? Color(hex: 0x8E8E93) : Color(hex: 0x19B900)
    }

    func stepState(for index: Int) -> TripProgressStepState {
        if self == .complete { return .done }
        if index < rawValue { return .done }
        if index == rawValue, rawValue >= 1, rawValue <= 3 { return .active }
        return .inactive
    }
}

private enum TripProgressStepState {
    case done
    case active
    case inactive

    var tint: Color {
        switch self {
        case .done: return Color(hex: 0x19B900)
        case .active: return Color(hex: 0x19B900)
        case .inactive: return Color(hex: 0x8E8E93)
        }
    }

    var iconForeground: Color {
        switch self {
        case .done: return .white
        case .active: return Color(hex: 0x19B900)
        case .inactive: return Color(hex: 0x8E8E93)
        }
    }

    var iconBackground: Color {
        switch self {
        case .done: return Color(hex: 0x19B900)
        case .active: return .white
        case .inactive: return Color(hex: 0xF2F4F7)
        }
    }

    var borderColor: Color {
        switch self {
        case .active: return Color(hex: 0x19B900)
        case .done: return Color(hex: 0x19B900)
        case .inactive: return Color(hex: 0xD0D5DD)
        }
    }
}

private struct TripProgressStep: View {
    let title: String
    let systemImage: String
    let state: TripProgressStepState

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(state.iconBackground)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(state.borderColor, lineWidth: state == .active ? 1.4 : 0))
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state.iconForeground)
            }
            Text(title)
                .font(.system(size: 10, weight: state == .inactive ? .regular : .medium))
                .foregroundStyle(state.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: 58)
    }
}

private struct TripProgressLine: View {
    let isActive: Bool

    var body: some View {
        Capsule()
            .fill(isActive ? Color(hex: 0x19B900) : Color(hex: 0xD0D5DD))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)
    }
}

// MARK: - Errors

private enum TripError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

private struct CpClientSeenSheet: View {
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0xEAF3FF))
                    .frame(width: 62, height: 62)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }
            .padding(.top, 18)

            Text("Have you seen the client?")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: 0x1D2939))

            Text("Please confirm if you have seen or met the client at this location.")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x475467))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            HStack(spacing: 12) {
                Button(action: onYes) {
                    Label("Yes, I saw", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color(hex: 0x19B900), in: RoundedRectangle(cornerRadius: 12))

                Button(action: onNo) {
                    Label("No I didn't", systemImage: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: 0x19B900))
                .background(Color(hex: 0xEAF8E8), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
        .background(.white)
    }
}

private struct CpTripCompletedSheet: View {
    let onBackHome: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0xEAF8E8))
                    .frame(width: 68, height: 68)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x19B900))
            }
            .padding(.top, 22)

            Text("CP Visit Completed")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: 0x1D2939))

            Text("Client not seen flow has been recorded.")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x475467))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button(action: onBackHome) {
                Label("Back Home", systemImage: "house.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color(hex: 0x19B900), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 18)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
        .background(.white)
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
