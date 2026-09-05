import CoreLocation
import MapKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @Environment(\.openURL) private var openURL

    let visitIdArg: String?
    let placeIdArg: String?
    let placeName: String
    let placeAddress: String?
    let mapsLink: String?
    let destination: CLLocationCoordinate2D?
    let initialStatus: String?
    let tripType: String?
    let travelMode: String?
    let vehiclePreference: String?
    let clientPlaceVisitId: String?
    let cpClientMet: Bool?
    let cpOutcome: String?
    let cpVisitCategory: String?
    let cpType: String?
    let lmoName: String?
    /// Who the visit is ASSIGNED to. A manager opening someone else's trip
    /// had no way to tell whose it was — the card showed the client and the
    /// LMO but never the field staff. Optional so existing call sites that
    /// don't have it keep compiling; the row simply hides.
    let fieldStaffName: String?
    let deadline: String?
    let fleetOnSiteAt: Int64?
    let usesAgencyFleetDriverAPI: Bool
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
    @State private var hasAttemptedRouteFetch = false
    @State private var lastRouteKey: String?
    @State private var routeWarning: String?

    @State private var arrivalInProgress = false
    @State private var arrivalSwipeResetToken = 0
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var pendingStorageId: String?
    @State private var arrivalStatusText: String?
    @State private var showDriverStartTripSheet = false
    @State private var showDriverEndTripSheet = false
    @State private var pendingCompletionVisitId: String?
    @State private var driverStartKm: Double?
    @State private var fleetDriverPhase = "scheduled"
    @State private var fleetPickupSecondsRemaining = 0
    @State private var isDriverEndSubmitting = false

    @State private var showOtpSheet = false
    @State private var showSiteVisitOutcomeSheet = false
    @State private var showCpCompletionSheet = false
    @State private var activeSpecialCpCompletion: CpSpecialCompletionKind?
    @State private var showCollectionDecision = false
    @State private var collectionNotCollectedChoice = false
    @State private var showCpClientSeenSheet = false
    @State private var showGeofenceReasonAlert = false
    @State private var geofenceReason = ""
    @State private var geofenceDistanceText = ""
    @State private var showCpTripCompletedSheet = false
    @State private var pendingCpRevisit: CpRevisitInfo?
    @State private var pendingCpTripCompletion: CpTripCompletionPayload?
    @State private var showCpPendingApproval = false
    @State private var showCpRevisitConfirmation = false
    @State private var cpNoPathPhotoCapture = false
    @State private var repairVerifiedArrivalProof = false
    /// Set when COMPLETION (not arrival) was rejected for a missing photo
    /// proof: after the repair capture uploads, finish the visit with the
    /// proof attached instead of replaying the arrival/outcome steps.
    @State private var resumeCompletionAfterProofRepair = false
    @State private var completeWithClientNotSeenSheet = false
    @State private var otpPhoneMasked: String?
    @State private var otpLat: Double = 0
    @State private var otpLng: Double = 0

    @State private var errorMessage: String?
    @State private var jointWorkflow: JointCpWorkflow?
    @State private var isJointMutationInProgress = false
    @State private var autoOpenedJointReviewRevision: Int64?

    private let geoAPI = GeoTrackAPIService.shared
    private let directionsClient = GeoTrackDirectionsClient()

    init(
        visitId: String? = nil,
        placeId: String? = nil,
        placeName: String,
        placeAddress: String? = nil,
        mapsLink: String? = nil,
        destination: CLLocationCoordinate2D? = nil,
        initialStatus: String? = nil,
        tripType: String? = nil,
        travelMode: String? = nil,
        vehiclePreference: String? = nil,
        clientPlaceVisitId: String? = nil,
        cpClientMet: Bool? = nil,
        cpOutcome: String? = nil,
        cpVisitCategory: String? = nil,
        cpType: String? = nil,
        lmoName: String? = nil,
        fieldStaffName: String? = nil,
        deadline: String? = nil,
        fleetOnSiteAt: Int64? = nil,
        usesAgencyFleetDriverAPI: Bool = false,
        requiresOpenAttendance: Bool = false,
        onTripChanged: (() -> Void)? = nil
    ) {
        self.visitIdArg = visitId
        self.placeIdArg = placeId
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.mapsLink = mapsLink
        self.destination = destination
        self.initialStatus = initialStatus
        self.tripType = tripType
        self.travelMode = travelMode
        self.vehiclePreference = vehiclePreference
        self.clientPlaceVisitId = clientPlaceVisitId
        self.cpClientMet = cpClientMet
        self.cpOutcome = cpOutcome
        self.cpVisitCategory = cpVisitCategory
        self.cpType = cpType
        self.lmoName = lmoName
        self.fieldStaffName = fieldStaffName
        self.deadline = deadline
        self.fleetOnSiteAt = fleetOnSiteAt
        self.usesAgencyFleetDriverAPI = usesAgencyFleetDriverAPI
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

    private var isJointCpWorkflow: Bool {
        cpType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_") == "joint_cp"
            || jointWorkflow != nil
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
                        VStack(spacing: 8) {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                            if locationManager.needsSettings {
                                Button("Open Location Settings") {
                                    locationManager.openSettings()
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
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
        .background(Color.appScreenBackground.ignoresSafeArea())
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(isPresented: $showCamera) {
            PunchCameraView(capturedImage: $capturedImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showCpClientSeenSheet, onDismiss: {
            if !arrivalInProgress && !visitCompletedSuccessfully {
                arrivalStatusText = nil
                resetArrivalSwipe()
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
            .appLibraryNativeSheet([.height(270)])
        }
        .alert("You're away from the client", isPresented: $showGeofenceReasonAlert) {
            TextField("Reason for completing here", text: $geofenceReason)
            Button("Cancel", role: .cancel) {
                arrivalInProgress = false
                arrivalStatusText = nil
                resetArrivalSwipe()
            }
            Button("Complete anyway") {
                proceedAfterGeofenceReason()
            }
        } message: {
            Text("You are \(geofenceDistanceText) from the client's saved location. Completing from here is allowed but is held for GM approval. Add a reason to continue.")
        }
        .sheet(isPresented: $showOtpSheet, onDismiss: {
            if !visitCompletedSuccessfully {
                arrivalInProgress = false
                arrivalStatusText = nil
                resetArrivalSwipe()
            }
        }) {
            if let id = resolvedVisitId {
                ArrivalOtpSheet(
                    visitId: id,
                    phoneMasked: otpPhoneMasked,
                    lat: otpLat,
                    lng: otpLng,
                    clientPlaceVisitId: clientPlaceVisitId,
                    // Arrival photo was uploaded in uploadPhotoThenShowOtp before this
                    // sheet opened; forward its storage id so the OTP verify links the
                    // photo immediately (Android parity). Still re-sent at completeVisit
                    // below as an idempotent belt-and-braces.
                    arrivalPhotoStorageId: pendingStorageId,
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
                resetArrivalSwipe()
            }
        }) {
            if let cpVisitId = clientPlaceVisitId {
                CompleteCpVisitSheet(
                    cpVisitId: cpVisitId,
                    initialOutcome: jointWorkflow?.outcome ?? cpOutcome,
                    cpType: cpType,
                    jointCtaMode: jointWorkflow?.actorRole == "outcome_owner"
                        ? "send_review"
                        : (jointWorkflow?.actorRole == "reviewer" ? "complete_review" : nil),
                    jointOutcomeSummary: jointWorkflow?.outcomeSummary,
                    onTerminalClosed: {
                        finishAfterAtomicCpTerminalOutcome()
                    },
                    onTripCompletion: { payload in
                        pendingCpTripCompletion = payload
                    },
                    onCompleted: { revisit in
                        pendingCpRevisit = revisit
                        Task { await handleCpOutcomeSaved() }
                    }
                )
                .environment(authStore)
            }
        }
        .sheet(item: $activeSpecialCpCompletion, onDismiss: {
            collectionNotCollectedChoice = false
            if !visitCompletedSuccessfully {
                arrivalInProgress = false
                arrivalStatusText = nil
                resetArrivalSwipe()
            }
        }) { kind in
            if let cpVisitId = clientPlaceVisitId {
                SpecialCpCompletionSheet(
                    kind: kind,
                    cpVisitId: cpVisitId,
                    arrivalProofStorageId: pendingStorageId,
                    initialCollectionNotCollected: collectionNotCollectedChoice,
                    onTripCompletion: { payload in
                        pendingCpTripCompletion = payload
                    },
                    onCompleted: { replacementProofId, revisit in
                        if let replacementProofId {
                            pendingStorageId = replacementProofId
                        }
                        pendingCpRevisit = revisit
                        Task { await completeVisitAfterCpOutcome() }
                    }
                )
                .environment(authStore)
            }
        }
        .confirmationDialog(
            "Collection done?",
            isPresented: $showCollectionDecision,
            titleVisibility: .visible
        ) {
            Button("Yes, open Payment Entry") {
                collectionNotCollectedChoice = false
                activeSpecialCpCompletion = .collection
            }
            Button("No, nothing collected") {
                collectionNotCollectedChoice = true
                activeSpecialCpCompletion = .collection
            }
            Button("Cancel", role: .cancel) {
                arrivalInProgress = false
                arrivalStatusText = nil
                resetArrivalSwipe()
            }
        } message: {
            Text("Choose Yes only when an amount was collected from the client.")
        }
        .sheet(isPresented: $showSiteVisitOutcomeSheet, onDismiss: {
            if !visitCompletedSuccessfully {
                arrivalInProgress = false
                arrivalStatusText = nil
                resetArrivalSwipe()
            }
        }) {
            if let id = resolvedVisitId {
                SiteVisitOutcomeSheet(
                    siteVisitId: id,
                    onCompleted: {
                        Task { await completeVisitAfterSiteVisitOutcome() }
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
            .appLibraryNativeSheet([.height(260)])
        }
        .alert(cpRevisitDialogTitle, isPresented: $showCpRevisitConfirmation) {
            Button("Done") {
                pendingCpRevisit = nil
                dismiss()
            }
        } message: {
            Text(cpRevisitDialogMessage)
        }
        .alert("Waiting for GM approval", isPresented: $showCpPendingApproval) {
            Button("Done") { dismiss() }
        } message: {
            Text("The visit outcome was saved. It will be completed after GM approval.")
        }
        .sheet(isPresented: $showDriverStartTripSheet) {
            DriverOdometerSheet(
                phase: .start,
                minimumKm: nil,
                isSubmitting: isLoadingStart
            ) { proof in
                showDriverStartTripSheet = false
                Task { await ensureVisitStarted(startProof: proof) }
            }
            .appLibraryNativeSheet([.large])
        }
        .sheet(isPresented: $showDriverEndTripSheet, onDismiss: {
            if pendingCompletionVisitId != nil && !visitCompletedSuccessfully && !isDriverEndSubmitting {
                pendingCompletionVisitId = nil
                arrivalInProgress = false
                arrivalStatusText = nil
                resetArrivalSwipe()
            }
        }) {
            DriverOdometerSheet(
                phase: .end,
                minimumKm: driverStartKm,
                isSubmitting: isDriverEndSubmitting
            ) { proof in
                if let pendingCompletionVisitId {
                    Task { await completeGeoTrackVisit(visitId: pendingCompletionVisitId, endProof: proof) }
                }
            }
            .appLibraryNativeSheet([.large])
        }
        .task {
            locationManager.requestLocation()
            initializeTripState()
            updateMapForKnownDestination()
            await refreshRouteIfPossible(force: true)
        }
        .task(id: clientPlaceVisitId) {
            guard isJointCpWorkflow else { return }
            while !Task.isCancelled {
                await refreshJointWorkflow()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            Task {
                if repairVerifiedArrivalProof {
                    await uploadAndRepairVerifiedArrival(image: image)
                } else if cpNoPathPhotoCapture {
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
                .foregroundStyle(.primary)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 32, height: 32)
                        .background(Color.appSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(arrivalInProgress || isLoadingStart)

                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 60)
        .background(Color.appSurface)
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
            } else if hasAttemptedRouteFetch, !isRouteLoading, canShowLiveRoute, let dest = effectiveDestination, let me = currentLocation {
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
        .overlay(alignment: .topTrailing) {
            if mapsLink?.nilIfBlank != nil || effectiveDestination != nil {
                Button {
                    openDestinationInMaps()
                } label: {
                    Label("Open Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: 0x0B61CA))
                .padding(10)
                .accessibilityHint("Opens the saved destination in Maps")
            }
        }
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 18))
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
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
                    .background(Color.appFieldBackground, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(clientDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("Client")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusPill
            }

            HStack(spacing: 10) {
                VStack(spacing: 14) {
                    tripMetric(icon: "building.2.fill", label: "Type", value: cpTypeDisplayLabel)
                    tripMetric(icon: "road.lanes", label: "Distance", value: distanceText)
                    if let fieldStaffName = fieldStaffName?.nilIfBlank {
                        tripMetric(
                            icon: "person.fill",
                            label: "Field Staff",
                            value: fieldStaffName
                        )
                    }
                    if let lmoName = lmoName?.nilIfBlank {
                        tripMetric(icon: "person.badge.key.fill", label: "LMO", value: lmoName)
                    }
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color(hex: 0xE5E7EB))
                    .frame(
                        width: 1,
                        // Grows with the taller column so the divider doesn't
                        // stop short once Field Staff is present.
                        height: {
                            let left = 2
                                + (fieldStaffName?.nilIfBlank != nil ? 1 : 0)
                                + (lmoName?.nilIfBlank != nil ? 1 : 0)
                            let right = 2 + (deadline?.nilIfBlank != nil ? 1 : 0)
                            return CGFloat(max(left, right) - 2) * 54 + 86
                        }()
                    )

                VStack(spacing: 14) {
                    tripMetric(icon: "location.fill", label: "Location", value: destinationSummary)
                    tripMetric(icon: "timer", label: "ETA", value: etaText)
                    if let deadline = deadline?.nilIfBlank {
                        tripMetric(icon: "calendar.badge.clock", label: "Deadline", value: deadline)
                    }
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
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appSeparator, lineWidth: 1)
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
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.appFieldBackground, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
    }

    private var tripProgressCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Trip Progress")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text(tripProgressStage.stateLabel)
                    .font(.system(size: 13, weight: .medium))
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
        .padding(16)
        .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if hasActiveVisit {
                if tripProgressStage == .complete && (!isJointCpWorkflow || jointWorkflow?.state == "completed") {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Trip Completed")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(.secondary)
                    .background(Color.appFieldBackground, in: Capsule())
                } else if let workflow = jointWorkflow {
                    jointWorkflowAction(workflow)
                } else if isFleetDriverMode && !isCpVisit && fleetDriverPhase == "on_site" {
                    Button {
                        Task { await markFleetDriverPickedFromSite() }
                    } label: {
                        Label(
                            fleetPickupSecondsRemaining > 0
                                ? "Picked from Site in \(fleetPickupSecondsRemaining)s"
                                : "Picked from Site",
                            systemImage: "person.2.fill"
                        )
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color(hex: 0x1BCA0B))
                    .disabled(arrivalInProgress || fleetPickupSecondsRemaining > 0)
                } else if isFleetDriverMode && !isCpVisit && fleetDriverPhase == "picked_from_site" {
                    Button {
                        if let id = resolvedVisitId { requestDriverEndProofThenComplete(visitId: id) }
                    } label: {
                        Label("End Trip", systemImage: "flag.checkered")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color(hex: 0x1BCA0B))
                } else if isCpVisit && tripProgressStage == .reached && shouldCollectCpOutcome {
                    Button {
                        showCpCompletionSheet = true
                    } label: {
                        HStack {
                            if arrivalInProgress {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
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
                            colors: [Color(hex: 0x1BCA0B), Color(hex: 0x3D9D02)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Capsule()
                    )
                    .disabled(arrivalInProgress)
                } else {
                    SwipeToConfirmTripButton(
                        title: primaryActionTitle,
                        busyTitle: arrivalStatusText ?? "Working...",
                        isBusy: arrivalInProgress,
                        resetToken: arrivalSwipeResetToken
                    ) {
                        onArrivalSwipeConfirmed()
                    }
                    .disabled(arrivalInProgress)
                }
            } else {
                Button {
                    if isCpVisit {
                        Task { await ensureCpVisitStarted() }
                    } else {
                        showDriverStartTripSheet = true
                    }
                } label: {
                    HStack {
                        if isLoadingStart {
                            ProgressView().tint(.white)
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
                        colors: [Color(hex: 0x1BCA0B), Color(hex: 0x3D9D02)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Capsule()
                )
                .disabled(isLoadingStart)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func jointWorkflowAction(_ workflow: JointCpWorkflow) -> some View {
        let canEnterOutcome = workflow.actorRole == "outcome_owner" && workflow.canSubmitOutcome == true
        let canReview = workflow.actorRole == "reviewer" && workflow.canReview == true
        if canEnterOutcome || canReview {
            Button {
                showCpCompletionSheet = true
            } label: {
                HStack {
                    if isJointMutationInProgress { ProgressView().tint(.white) }
                    Image(systemName: canReview ? "doc.text.magnifyingglass" : "square.and.arrow.up")
                    Text(canReview ? "Review outcome" : "Enter outcome")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Color(hex: 0x1BCA0B))
            .disabled(isJointMutationInProgress)
        } else if workflow.actorRole == "outcome_owner" && workflow.canRequestOtp == true {
            SwipeToConfirmTripButton(
                title: primaryActionTitle,
                busyTitle: arrivalStatusText ?? "Checking both staff locations...",
                isBusy: arrivalInProgress,
                resetToken: arrivalSwipeResetToken
            ) {
                onArrivalSwipeConfirmed()
            }
            .disabled(arrivalInProgress)
        } else {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(jointWaitingMessage(workflow))
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .padding(.horizontal, 12)
            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func jointWaitingMessage(_ workflow: JointCpWorkflow) -> String {
        if workflow.state == "completed" {
            return "Outcome reviewed by \(workflow.reviewedByTemplateName ?? workflow.reviewedByName ?? "reviewer")"
        }
        if workflow.actorRole == "reviewer" {
            return "Waiting for \(workflow.outcomeOwnerName ?? "BDO") outcome"
        }
        if workflow.actorRole == "outcome_owner" {
            return "Complete OTP and photo while both partners are within 50 metres"
        }
        return "Waiting for Joint CP workflow update"
    }

    // MARK: - Visit lifecycle

    private func initializeTripState() {
        let normalizedStatus = normalizedInitialStatus
        fleetDriverPhase = normalizedStatus.replacingOccurrences(of: "-", with: "_")
        if fleetDriverPhase == "on_site", let fleetOnSiteAt {
            let timestampSeconds = fleetOnSiteAt > 10_000_000_000
                ? TimeInterval(fleetOnSiteAt) / 1_000
                : TimeInterval(fleetOnSiteAt)
            let elapsed = max(0, Date().timeIntervalSince1970 - timestampSeconds)
            fleetPickupSecondsRemaining = max(0, 60 - Int(elapsed))
            if fleetPickupSecondsRemaining > 0 { beginFleetPickupCountdown() }
        }
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
            "on_site",
            "on-site",
            "picked_from_site",
            "picked-from-site",
            "completed",
            "complete",
            "done",
            "closed"
        ].contains(normalizedStatus)
        statusLine = visitStarted ? "In progress" : "Start"
        isLoadingStart = false
    }

    private func ensureVisitStarted(startProof: DriverOdometerProof) async {
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
                let photoId = try await uploadOdometerPhoto(startProof.image)
                if usesAgencyFleetDriverAPI {
                    _ = try await FleetConvexAPIService.markArrived(
                        token: token,
                        scope: .agency,
                        siteVisitId: effectiveVisitId
                    )
                    _ = try await FleetConvexAPIService.startTrip(
                        token: token,
                        scope: .agency,
                        siteVisitId: effectiveVisitId,
                        startKm: startProof.km,
                        photoIds: [photoId]
                    )
                } else {
                    try await geoAPI.markMmsFleetDriverArrived(siteVisitId: effectiveVisitId)
                    try await geoAPI.startMmsFleetDriverTrip(
                        siteVisitId: effectiveVisitId,
                        photoIds: [photoId],
                        startKm: startProof.km
                    )
                    try await geoAPI.startVisit(
                        visitId: effectiveVisitId,
                        lat: loc?.coordinate.latitude,
                        lng: loc?.coordinate.longitude
                    )
                    await syncMarketingSiteVisitStarted(token: token, siteVisitId: effectiveVisitId)
                }
            }

            driverStartKm = startProof.km
            fleetDriverPhase = "in_progress"
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

    /// Android parity for field-staff CP visits: validate attendance, start
    /// the CP visit directly, and begin tracking. Odometer/photo capture is
    /// reserved for actual fleet-driver trips.
    private func ensureCpVisitStarted() async {
        guard !isLoadingStart else { return }
        isLoadingStart = true
        statusLine = "Starting…"

        let normalizedStatus = normalizedInitialStatus
        let alreadyInFlight = [
            "in-progress", "in_progress", "ongoing", "started", "active",
            "arrived", "arrival_verified", "arrival-verified", "on_site",
            "on-site", "reaching"
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
            if !alreadyInFlight {
                let hasClockedInToday = await AttendanceTrackingGate.isClockedInForToday(token: token)
                guard hasClockedInToday else {
                    throw TripError.message("Please clock in before starting a trip.")
                }
            }

            let effectiveVisitId: String
            if let visitIdArg, !visitIdArg.isEmpty {
                effectiveVisitId = visitIdArg
            } else if let placeIdArg, !placeIdArg.isEmpty {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                geoAPI.tokenProvider = { token }
                effectiveVisitId = try await geoAPI.createVisit(
                    clientPlaceId: placeIdArg,
                    scheduledDate: formatter.string(from: Date()),
                    notes: "Ad-hoc trip started from mobile"
                )
            } else {
                throw TripError.message("Missing visit or place identifier")
            }

            resolvedVisitId = effectiveVisitId
            if !alreadyInFlight {
                geoAPI.tokenProvider = { token }
                let location = try await locationManager.freshPreciseLocation()
                try await geoAPI.startVisit(
                    visitId: effectiveVisitId,
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude
                )
            }

            visitStarted = true
            statusLine = "On the way"
            isLoadingStart = false
            onTripChanged?()
            await GeoTrackBootstrapCoordinator.shared.sync(reason: "cp-visit-started", force: true)
            await refreshRouteIfPossible(force: true)
        } catch {
            startError = error.localizedDescription
            errorMessage = "Failed to start trip: \(error.localizedDescription)"
            statusLine = "Start"
            isLoadingStart = false
        }
    }

    private func syncMarketingSiteVisitStarted(token: String, siteVisitId: String) async {
        guard shouldSyncMarketingSiteVisitLifecycle else { return }
        do {
            if isOwnVehicleSiteVisit {
                try await MarketingConvexAPIService.markSiteVisitClientStarted(token: token, id: siteVisitId)
            } else {
                try await MarketingConvexAPIService.markSiteVisitPickedUp(token: token, id: siteVisitId)
            }
        } catch {
            // Keep the existing trip flow working if marketing status was
            // already advanced by another client or backend sync.
        }
    }

    private func syncMarketingSiteVisitArrived(siteVisitId: String) async {
        guard shouldSyncMarketingSiteVisitLifecycle else { return }
        do {
            let token = try requireToken()
            try await MarketingConvexAPIService.markSiteVisitArrivedSite(token: token, id: siteVisitId)
        } catch {
            // Outcome capture should still open if the backend already moved
            // this Site Visit to on-site through another path.
        }
    }

    // MARK: - Arrival flow

    private func onArrivalSwipeConfirmed() {
        guard let _ = resolvedVisitId, visitStarted else {
            errorMessage = "Trip is still starting"
            resetArrivalSwipe()
            return
        }
        guard !arrivalInProgress else { return }
        arrivalInProgress = true
        errorMessage = nil
        capturedImage = nil
        if isFleetDriverMode && !isCpVisit {
            Task { await markFleetDriverOnSite() }
            return
        }
        if isJointCpWorkflow {
            Task { await preflightJointCpArrival() }
            return
        }
        if isCpVisit {
            checkReachingAndAskClientSeen()
            return
        }
        Task { await requestArrivalOtpThenOpenCamera() }
    }

    @MainActor
    private func markFleetDriverOnSite() async {
        guard let id = resolvedVisitId else {
            arrivalInProgress = false
            resetArrivalSwipe()
            return
        }
        arrivalStatusText = "Updating on-site…"
        do {
            let token = try requireToken()
            geoAPI.tokenProvider = { token }
            if usesAgencyFleetDriverAPI {
                _ = try await FleetConvexAPIService.markOnSite(token: token, scope: .agency, siteVisitId: id)
            } else {
                try await geoAPI.markMmsFleetDriverOnSite(siteVisitId: id)
            }
            fleetDriverPhase = "on_site"
            fleetPickupSecondsRemaining = 60
            beginFleetPickupCountdown()
            statusLine = "On Site"
            arrivalStatusText = nil
            arrivalInProgress = false
            onTripChanged?()
        } catch {
            arrivalStatusText = nil
            arrivalInProgress = false
            errorMessage = "Failed to mark on-site: \(error.localizedDescription)"
            resetArrivalSwipe()
        }
    }

    @MainActor
    private func markFleetDriverPickedFromSite() async {
        guard let id = resolvedVisitId, !arrivalInProgress else { return }
        arrivalInProgress = true
        arrivalStatusText = "Updating return pickup…"
        do {
            let token = try requireToken()
            geoAPI.tokenProvider = { token }
            if usesAgencyFleetDriverAPI {
                _ = try await FleetConvexAPIService.markPickedFromSite(token: token, scope: .agency, siteVisitId: id)
            } else {
                try await geoAPI.markMmsFleetDriverPickedFromSite(siteVisitId: id)
            }
            fleetDriverPhase = "picked_from_site"
            statusLine = "Picked from Site"
            arrivalStatusText = nil
            arrivalInProgress = false
            onTripChanged?()
        } catch {
            arrivalStatusText = nil
            arrivalInProgress = false
            errorMessage = "Failed to mark picked from site: \(error.localizedDescription)"
        }
    }

    private func beginFleetPickupCountdown() {
        Task { @MainActor in
            while fleetPickupSecondsRemaining > 0 && fleetDriverPhase == "on_site" {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                fleetPickupSecondsRemaining = max(0, fleetPickupSecondsRemaining - 1)
            }
        }
    }

    private func checkReachingAndAskClientSeen() {
        Task {
            do {
                guard let dest = effectiveDestination else {
                    throw TripLocationError.destinationUnavailable
                }
                let loc = try await locationManager.freshPreciseLocation()
                let directDistance = CLLocation(
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude
                )
                .distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
                await refreshRouteIfPossible(force: true)
                let distance = distanceMeters ?? directDistance
                if distance > 500 {
                    arrivalStatusText = nil
                    geofenceDistanceText = formatDistance(distance)
                    geofenceReason = ""
                    resetArrivalSwipe()
                    showGeofenceReasonAlert = true
                    return
                }
                arrivalStatusText = nil
                showCpClientSeenSheet = true
            } catch {
                arrivalInProgress = false
                errorMessage = error.localizedDescription
                resetArrivalSwipe()
            }
        }
    }

    /// Beyond-geofence completion: best-effort stash the staff's reason on the visit
    /// (so the approving GM sees why they completed away from the client), then run
    /// the normal client-seen → photo → OTP flow.
    private func proceedAfterGeofenceReason() {
        let reason = geofenceReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token = authStore.currentSession?.token,
           let cpId = clientPlaceVisitId ?? resolvedVisitId,
           !reason.isEmpty {
            Task { try? await MarketingConvexAPIService.setCpGeofenceRemark(token: token, id: cpId, remark: reason) }
        }
        arrivalStatusText = nil
        showCpClientSeenSheet = true
    }

    private func startCpYesPath() {
        cpNoPathPhotoCapture = false
        capturedImage = nil
        Task { await requestArrivalOtpThenOpenCamera() }
    }

    private func startCpNoPath() {
        repairVerifiedArrivalProof = false
        resumeCompletionAfterProofRepair = false
        showOtpSheet = false
        cpNoPathPhotoCapture = true
        capturedImage = nil
        showCamera = true
    }

    @MainActor
    private func refreshJointWorkflow() async {
        guard isJointCpWorkflow,
              let token = authStore.currentSession?.token,
              let cpId = clientPlaceVisitId
        else { return }
        do {
            let workflow = try await MarketingConvexAPIService.getJointCpWorkflow(token: token, id: cpId)
            jointWorkflow = workflow
            if workflow.state == "completed" {
                statusLine = "Complete"
            } else if workflow.actorRole == "reviewer",
                      workflow.canReview == true,
                      let revision = workflow.outcomeRevision,
                      autoOpenedJointReviewRevision != revision {
                autoOpenedJointReviewRevision = revision
                showCpCompletionSheet = true
            }
        } catch {
            // Additive endpoint: preserve the live trip on mixed deployments.
        }
    }

    @MainActor
    private func preflightJointCpArrival() async {
        guard let token = authStore.currentSession?.token,
              let cpId = clientPlaceVisitId,
              let fieldVisitId = resolvedVisitId
        else {
            arrivalInProgress = false
            errorMessage = "Joint CP visit information is missing"
            resetArrivalSwipe()
            return
        }
        if let workflow = jointWorkflow, workflow.canRequestOtp != true {
            arrivalInProgress = false
            errorMessage = jointWaitingMessage(workflow)
            resetArrivalSwipe()
            return
        }
        arrivalStatusText = "Checking both staff locations..."
        do {
            let location = try await locationManager.freshPreciseLocation()
            let workflow = try await MarketingConvexAPIService.preflightJointCpArrival(
                token: token,
                request: JointCpLocationRequest(
                    id: cpId,
                    fieldVisitId: fieldVisitId,
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude,
                    accuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
                    capturedAt: Int64(location.timestamp.timeIntervalSince1970 * 1_000)
                )
            )
            jointWorkflow = workflow
            guard workflow.isWithinCompletionRadius == true else {
                let measured = workflow.separationMeters.map { String(format: "%.0f m", $0) }
                throw TripError.message(
                    measured.map {
                        "Joint CP completion is blocked. Both staff must be within 50 metres. Current separation: \($0)."
                    } ?? "Both Joint CP staff need a fresh location within 50 metres."
                )
            }
            arrivalStatusText = nil
            checkReachingAndAskClientSeen()
        } catch {
            arrivalInProgress = false
            arrivalStatusText = nil
            errorMessage = error.localizedDescription
            resetArrivalSwipe()
        }
    }

    private func requestArrivalOtpThenOpenCamera() async {
        guard let id = resolvedVisitId else {
            arrivalInProgress = false
            resetArrivalSwipe()
            return
        }
        arrivalStatusText = "Checking location..."
        do {
            let token = try requireToken()
            let loc = try await locationManager.freshPreciseLocation()

            geoAPI.tokenProvider = { token }
            let resp = try await geoAPI.requestArrivalOtp(
                visitId: id,
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude
            )
            otpPhoneMasked = resp.contactPhoneMasked
            otpLat = loc.coordinate.latitude
            otpLng = loc.coordinate.longitude
            if specialCpCompletionKind == .giftDistribution {
                // Android captures the gift handover after OTP. Avoid making
                // staff take and upload an extra arrival selfie first.
                pendingStorageId = nil
                arrivalStatusText = nil
                showOtpSheet = true
                return
            }
            arrivalStatusText = "Opening camera..."
            capturedImage = nil
            showCamera = true
        } catch {
            let serverMessage = error.localizedDescription.lowercased()
            if serverMessage.contains("already verified") || serverMessage.contains("finish the outcome") {
                // Android resumes an interrupted CP at the outcome step rather
                // than forcing another location/photo/OTP loop.
                arrivalStatusText = nil
                if isCpVisit,
                   specialCpCompletionKind != .giftDistribution {
                    if let pendingStorageId {
                        await attachLegacyArrivalProofAndResume(storageId: pendingStorageId)
                    } else {
                        repairVerifiedArrivalProof = true
                        capturedImage = nil
                        showCamera = true
                    }
                    return
                }
                await completeVisitAfterOtp(otp: "")
                return
            }
            arrivalInProgress = false
            arrivalStatusText = nil
            errorMessage = error.localizedDescription
            resetArrivalSwipe()
        }
    }

    private func uploadPhotoThenShowOtp(image: UIImage) async {
        arrivalStatusText = "Uploading photo…"
        do {
            let token = try requireToken()
            guard let jpeg = await optimizedArrivalImageData(image) else {
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
            resetArrivalSwipe()
        }
    }

    private func uploadPhotoThenCompleteWithoutClient(image: UIImage) async {
        guard let id = resolvedVisitId, let cpVisitId = clientPlaceVisitId else {
            arrivalInProgress = false
            cpNoPathPhotoCapture = false
            resetArrivalSwipe()
            return
        }
        arrivalStatusText = "Uploading photo…"
        do {
            let token = try requireToken()
            guard let jpeg = await optimizedArrivalImageData(image) else {
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
            pendingCpRevisit = try await MarketingConvexAPIService.setCpVisitOutcome(
                token: token,
                request: SetCpVisitOutcomeRequest(
                    id: cpVisitId,
                    outcome: specialCpCompletionKind?.terminalOutcome ?? "other",
                    postponeReasons: nil,
                    notes: specialCpCompletionKind?.clientNotSeenNotes ?? "Client not seen",
                    arrivalPhotoStorageId: storageId
                )
            )
            pendingCpTripCompletion = CpTripCompletionPayload(
                clientMet: false,
                outcome: specialCpCompletionKind?.terminalOutcome ?? "other",
                notes: specialCpCompletionKind?.clientNotSeenNotes ?? "Client not seen",
                postponeReasons: nil,
                followUpDate: nil,
                followUpTime: nil
            )
            cpNoPathPhotoCapture = false
            if isJointCpWorkflow {
                arrivalInProgress = false
                await submitJointCpForReview()
                return
            }
            completeWithClientNotSeenSheet = true
            await completeVisitUsingCorrectFlow(visitId: id)
        } catch {
            arrivalInProgress = false
            cpNoPathPhotoCapture = false
            arrivalStatusText = nil
            errorMessage = error.localizedDescription
            capturedImage = nil
            resetArrivalSwipe()
        }
    }

    private func optimizedArrivalImageData(_ image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let longest = max(image.size.width, image.size.height)
            let scale = longest > 0 ? min(1, 1_600 / longest) : 1
            let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: target)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
            return resized.jpegData(compressionQuality: 0.8)
        }.value
    }

    private func uploadAndRepairVerifiedArrival(image: UIImage) async {
        arrivalStatusText = "Repairing arrival proof…"
        do {
            let token = try requireToken()
            guard let jpeg = await optimizedArrivalImageData(image) else {
                throw TripError.message("Could not encode photo")
            }
            let storageId = try await HRConvexAPIService.uploadPhoto(token: token, imageData: jpeg)
            pendingStorageId = storageId
            if resumeCompletionAfterProofRepair, let id = resolvedVisitId {
                // Completion-time repair: the outcome is already recorded, so
                // complete directly with the proof attached (the complete
                // endpoint persists arrivalPhotoStorageId) — no replay of the
                // arrival / outcome steps.
                resumeCompletionAfterProofRepair = false
                repairVerifiedArrivalProof = false
                capturedImage = nil
                await completeFieldVisit(visitId: id)
                return
            }
            await attachLegacyArrivalProofAndResume(storageId: storageId)
        } catch {
            resumeCompletionAfterProofRepair = false
            repairVerifiedArrivalProof = false
            arrivalInProgress = false
            arrivalStatusText = nil
            capturedImage = nil
            errorMessage = error.localizedDescription
            resetArrivalSwipe()
        }
    }

    private func attachLegacyArrivalProofAndResume(storageId: String) async {
        guard let id = resolvedVisitId else { return }
        do {
            let token = try requireToken()
            geoAPI.tokenProvider = { token }
            let coordinate = locationManager.currentLocation?.coordinate
            try await geoAPI.completeVisit(
                visitId: id,
                lat: coordinate?.latitude ?? otpLat,
                lng: coordinate?.longitude ?? otpLng,
                remarks: "Arrival verified",
                arrivalPhotoStorageId: storageId
            )
            repairVerifiedArrivalProof = false
            arrivalStatusText = nil
            await completeVisitAfterOtp(otp: "")
        } catch {
            repairVerifiedArrivalProof = false
            arrivalInProgress = false
            arrivalStatusText = nil
            errorMessage = "Could not attach arrival selfie: \(error.localizedDescription)"
            resetArrivalSwipe()
        }
    }

    private func completeVisitAfterOtp(otp _: String) async {
        guard let id = resolvedVisitId else { return }
        if shouldCollectCpOutcome {
            arrivalStatusText = nil
            if let specialCpCompletionKind {
                if specialCpCompletionKind == .collection {
                    showCollectionDecision = true
                } else {
                    activeSpecialCpCompletion = specialCpCompletionKind
                }
                return
            }
            showCpCompletionSheet = true
            return
        }
        if !isCpVisit {
            arrivalStatusText = nil
            await syncMarketingSiteVisitArrived(siteVisitId: id)
            showSiteVisitOutcomeSheet = true
            return
        }
        await completeVisitUsingCorrectFlow(visitId: id)
    }

    private func completeVisitAfterCpOutcome() async {
        guard let id = resolvedVisitId else { return }
        await completeVisitUsingCorrectFlow(visitId: id)
    }

    private func completeVisitAfterSiteVisitOutcome() async {
        guard let id = resolvedVisitId else { return }
        await completeVisitUsingCorrectFlow(visitId: id)
    }

    @MainActor
    private func handleCpOutcomeSaved() async {
        guard isJointCpWorkflow, let workflow = jointWorkflow else {
            await completeVisitAfterCpOutcome()
            return
        }
        if workflow.actorRole == "outcome_owner" {
            await submitJointCpForReview()
        } else if workflow.actorRole == "reviewer" {
            await completeJointCpReview()
        } else {
            errorMessage = "The backend did not assign your Joint CP workflow role"
        }
    }

    @MainActor
    private func submitJointCpForReview() async {
        guard !isJointMutationInProgress,
              let token = authStore.currentSession?.token,
              let cpId = clientPlaceVisitId,
              let fieldVisitId = resolvedVisitId
        else { return }
        isJointMutationInProgress = true
        arrivalStatusText = "Sending outcome for review..."
        defer {
            isJointMutationInProgress = false
            arrivalStatusText = nil
        }
        do {
            let location = try await locationManager.freshPreciseLocation()
            let updated = try await MarketingConvexAPIService.submitJointCpReview(
                token: token,
                request: JointCpSubmitReviewRequest(
                    id: cpId,
                    fieldVisitId: fieldVisitId,
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude,
                    accuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
                    capturedAt: Int64(location.timestamp.timeIntervalSince1970 * 1_000),
                    arrivalPhotoStorageId: pendingStorageId,
                    expectedOutcomeRevision: jointWorkflow?.outcomeRevision
                ),
                idempotencyKey: UUID().uuidString
            )
            jointWorkflow = updated
            statusLine = "Waiting for review"
            onTripChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func completeJointCpReview() async {
        guard !isJointMutationInProgress,
              let token = authStore.currentSession?.token,
              let cpId = clientPlaceVisitId,
              let revision = jointWorkflow?.outcomeRevision
        else {
            errorMessage = "Refresh the submitted outcome before completing"
            return
        }
        isJointMutationInProgress = true
        arrivalStatusText = "Completing Joint CP..."
        defer {
            isJointMutationInProgress = false
            arrivalStatusText = nil
        }
        do {
            let updated = try await MarketingConvexAPIService.completeJointCpReview(
                token: token,
                request: JointCpCompleteReviewRequest(id: cpId, expectedOutcomeRevision: revision),
                idempotencyKey: UUID().uuidString
            )
            jointWorkflow = updated
            visitCompletedSuccessfully = true
            statusLine = "Complete"
            onTripChanged?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishAfterAtomicCpTerminalOutcome() {
        visitCompletedSuccessfully = true
        arrivalInProgress = false
        arrivalStatusText = nil
        onTripChanged?()
        Task {
            await GeoTrackBootstrapCoordinator.shared.sync(reason: "cp-terminal-outcome", force: true)
        }
        dismiss()
    }

    private var cpRevisitDialogTitle: String {
        pendingCpRevisit?.dialogTitle ?? "Revisit scheduled"
    }

    private var cpRevisitDialogMessage: String {
        pendingCpRevisit?.dialogMessage ?? ""
    }

    /// Android only asks for end-KM/odometer proof in `session.isDriverMode`.
    /// CP and normal field-staff visits finish directly after their outcome.
    private func completeVisitUsingCorrectFlow(visitId id: String) async {
        if isFleetDriverMode && !isCpVisit {
            requestDriverEndProofThenComplete(visitId: id)
        } else {
            await completeFieldVisit(visitId: id)
        }
    }

    private func requestDriverEndProofThenComplete(visitId id: String) {
        pendingCompletionVisitId = id
        arrivalStatusText = nil
        showDriverEndTripSheet = true
    }

    /// Field-staff completion parity with Android `finalizeCompleteVisit()`.
    /// Arrival photo and OTP are already recorded in their dedicated fields;
    /// there is no vehicle odometer step for CP staff.
    private func completeFieldVisit(visitId id: String) async {
        arrivalStatusText = "Completing visit…"
        do {
            let token = try requireToken()
            geoAPI.tokenProvider = { token }
            // Arrival location was already freshly verified before OTP. Reuse
            // it here instead of making completion wait for another GPS fix.
            let location = locationManager.currentLocation?.coordinate
            let completion = try await geoAPI.completeVisit(
                visitId: id,
                lat: location?.latitude ?? otpLat,
                lng: location?.longitude ?? otpLng,
                remarks: "Arrival verified",
                arrivalPhotoStorageId: pendingStorageId,
                clientMet: pendingCpTripCompletion?.clientMet,
                outcome: pendingCpTripCompletion?.outcome,
                outcomeNotes: pendingCpTripCompletion?.notes,
                postponeReasons: pendingCpTripCompletion?.postponeReasons,
                followUpDate: pendingCpTripCompletion?.followUpDate,
                followUpTime: pendingCpTripCompletion?.followUpTime
            )
            if pendingCpTripCompletion != nil {
                let confirmed = completion.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard ["completed", "pending_gm_approval", "postponed", "cancelled", "canceled"].contains(confirmed ?? "") else {
                    throw TripError.message("The trip was saved, but the CP outcome state was not confirmed. Refresh before retrying.")
                }
            }

            visitCompletedSuccessfully = true
            arrivalStatusText = nil
            arrivalInProgress = false
            onTripChanged?()
            Task {
                await GeoTrackBootstrapCoordinator.shared.sync(reason: "field-visit-completed", force: true)
            }

            let isPendingApproval = completion.status?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "pending_gm_approval"
            if pendingCpRevisit != nil {
                completeWithClientNotSeenSheet = false
                showCpRevisitConfirmation = true
            } else if completeWithClientNotSeenSheet {
                completeWithClientNotSeenSheet = false
                showCpTripCompletedSheet = true
            } else if isPendingApproval {
                showCpPendingApproval = true
            } else {
                dismiss()
            }
        } catch {
            arrivalStatusText = nil
            let message = Self.cleanServerMessage(error.localizedDescription)
            // The server requires an arrival photo proof and this session has
            // none to attach: `pendingStorageId` is in-memory only, so it is
            // nil whenever the OTP was verified in an earlier session / on
            // another device, or the trip screen was reopened to complete —
            // and some CP kinds skip the arrival selfie entirely. Don't
            // dead-end on the raw error (the reported "CP not able to close"):
            // capture the proof now and complete with it attached, the same
            // repair the arrival step already performs.
            if message.lowercased().contains("photo proof") {
                resumeCompletionAfterProofRepair = true
                repairVerifiedArrivalProof = true
                capturedImage = nil
                arrivalStatusText = "Photo proof required — opening camera…"
                showCamera = true
                return
            }
            arrivalInProgress = false
            errorMessage = "Failed to complete: \(message)"
            resetArrivalSwipe()
        }
    }

    /// The backend wraps thrown errors as "Uncaught Error: <message> at …";
    /// show the sentence, not the wrapper and stack tail.
    private static func cleanServerMessage(_ raw: String) -> String {
        var text = raw
        for prefix in ["Uncaught ConvexError: ", "Uncaught Error: "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        let newline: Character = "\u{0A}"
        return text.split(separator: newline, maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? raw
    }

    private func completeGeoTrackVisit(visitId id: String, endProof: DriverOdometerProof) async {
        arrivalStatusText = "Completing visit…"
        isDriverEndSubmitting = true
        do {
            let token = try requireToken()
            geoAPI.tokenProvider = { token }
            let loc = locationManager.currentLocation
            let odometerPhotoId = try await uploadOdometerPhoto(endProof.image)
            if usesAgencyFleetDriverAPI {
                _ = try await FleetConvexAPIService.endTrip(
                    token: token,
                    scope: .agency,
                    siteVisitId: id,
                    endKm: endProof.km,
                    photoIds: [odometerPhotoId]
                )
            } else {
                try await geoAPI.endMmsFleetDriverTrip(
                    siteVisitId: id,
                    photoIds: [odometerPhotoId],
                    endKm: endProof.km
                )
            }
            // Keep parity with Android by sending the photo id as a dedicated field.
            // The OTP itself is verified before completion, so remarks stay user-readable.
            let remarks = "Arrival verified"
            if !usesAgencyFleetDriverAPI {
                try await geoAPI.completeVisit(
                    visitId: id,
                    lat: loc?.coordinate.latitude,
                    lng: loc?.coordinate.longitude,
                    remarks: remarks,
                    arrivalPhotoStorageId: pendingStorageId
                )
            }
            visitCompletedSuccessfully = true
            fleetDriverPhase = "completed"
            arrivalStatusText = nil
            pendingCompletionVisitId = nil
            isDriverEndSubmitting = false
            showDriverEndTripSheet = false
            onTripChanged?()
            if pendingCpRevisit != nil {
                completeWithClientNotSeenSheet = false
                showCpRevisitConfirmation = true
            } else if completeWithClientNotSeenSheet {
                completeWithClientNotSeenSheet = false
                showCpTripCompletedSheet = true
            } else {
                dismiss()
            }
        } catch {
            arrivalStatusText = nil
            arrivalInProgress = false
            isDriverEndSubmitting = false
            errorMessage = "Failed to complete: \(error.localizedDescription)"
            resetArrivalSwipe()
        }
    }

    private func uploadOdometerPhoto(_ image: UIImage) async throws -> String {
        let token = try requireToken()
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else {
            throw TripError.message("Could not encode odometer photo")
        }
        if usesAgencyFleetDriverAPI {
            return try await FleetDispatchAPIService.uploadAgencyPhoto(token: token, data: jpeg)
        }
        return try await HRConvexAPIService.uploadPhoto(token: token, imageData: jpeg)
    }

    private func resetArrivalSwipe() {
        arrivalSwipeResetToken += 1
    }

    // MARK: - Maps + helpers

    private func openDestinationInMaps() {
        if let mapsLink = mapsLink?.nilIfBlank, let url = URL(string: mapsLink) {
            openURL(url)
            return
        }
        guard let dest = effectiveDestination else { return }
        let placemark = MKPlacemark(coordinate: dest)
        let item = MKMapItem(placemark: placemark)
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

    private var destinationSummary: String {
        placeAddress?.nilIfBlank ?? placeName.nilIfBlank ?? "Location not set"
    }

    private var cpTypeDisplayLabel: String {
        switch cpType?.normalizedTripCpMarker {
        case "sv_cum_cp": return "SV cum CP"
        case "follow_up": return "Follow-up"
        case "booking_cp": return "Booking CP"
        case "collection_cp": return "Collection CP"
        case "old_client": return "Old Client"
        case "gift_distribution": return "Gift Distribution"
        default:
            return cpVisitCategory?.normalizedTripCpMarker == "sv_cum_cp"
                ? "SV confirmation CP"
                : isCpVisit ? "Direct CP" : "Site Visit"
        }
    }

    private var shouldCollectCpOutcome: Bool {
        guard let clientPlaceVisitId, !clientPlaceVisitId.isEmpty else { return false }
        guard cpClientMet != true || (cpOutcome ?? "").isEmpty else { return false }
        return true
    }

    private var specialCpCompletionKind: CpSpecialCompletionKind? {
        CpSpecialCompletionKind(cpType: cpType)
    }

    private var isCpVisit: Bool {
        guard clientPlaceVisitId?.isEmpty == false else { return false }
        return true
    }

    private var isFleetDriverMode: Bool {
        authStore.currentSession?.user.isFleetDriverMode == true
    }

    private var shouldSyncMarketingSiteVisitLifecycle: Bool {
        visitIdArg?.isEmpty == false && !isCpVisit
    }

    private var isOwnVehicleSiteVisit: Bool {
        let markers = [travelMode, vehiclePreference, tripType]
            .compactMap { $0?.normalizedTripCpMarker }
        let ownVehicleMarkers: Set<String> = ["own_vehicle", "own", "self", "self_vehicle"]
        return markers.contains { ownVehicleMarkers.contains($0) }
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
            hasAttemptedRouteFetch = false
            return
        }

        guard canShowLiveRoute else {
            routeInfo = nil
            isRouteLoading = false
            hasAttemptedRouteFetch = false
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
        hasAttemptedRouteFetch = true
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
            if let meters = distanceMeters, meters <= 500 {
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
        if isFleetDriverMode && !isCpVisit {
            return fleetDriverPhase == "in_progress" ? "Swipe if Onsite Reached" : "Continue Trip"
        }
        if isCpVisit && tripProgressStage == .reached && shouldCollectCpOutcome {
            return cpOutcomeActionTitle
        }
        return "Swipe to Complete Trip"
    }

    private var cpOutcomeActionTitle: String {
        switch cpType?.normalizedTripCpMarker {
        case "collection_cp": return "Submit Payment Entry"
        case "old_client": return "Add Visit Remarks"
        case "gift_distribution": return "Confirm Gift Distribution"
        default:
            return cpVisitCategory?.normalizedTripCpMarker == "sv_cum_cp" ? "Complete SV details" : "Complete CP details"
        }
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
        case .complete: return Color.appFieldBackground
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
        await AttendanceTrackingGate.hasOpenSessionForToday(token: token)
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
        case .inactive: return Color.appFieldBackground
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
                    .frame(width: 32, height: 32)
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

private struct SwipeToConfirmTripButton: View {
    let title: String
    let busyTitle: String
    let isBusy: Bool
    let resetToken: Int
    let onConfirm: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isLocked = false

    private let height: CGFloat = 48
    private let inset: CGFloat = 4
    private let thumbSize: CGFloat = 40
    private let confirmThreshold: CGFloat = 0.85

    var body: some View {
        GeometryReader { proxy in
            let travel = max(0, proxy.size.width - thumbSize - inset * 2)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white)
                    .overlay(Capsule().stroke(Color(hex: 0xE5E7EB), lineWidth: 1))

                Text(isBusy ? busyTitle : title)
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x19B900))
                    .opacity(isLocked && !isBusy ? 0 : 1.0 - min(offset / max(travel, 1.0), 1.0))

                Image(systemName: "chevron.right.2")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0x19B900))
                    .frame(width: 24, height: 24)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                    .opacity(isBusy ? 0 : 1.0 - min(offset / max(travel, 1.0), 1.0))

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    .overlay(
                        Image(systemName: isBusy ? "hourglass" : "chevron.right.2")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0x19B900))
                    )
                    .padding(.leading, inset)
                    .offset(x: offset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !isBusy && !isLocked else { return }
                                offset = min(max(value.translation.width, 0), travel)
                            }
                            .onEnded { _ in
                                guard !isBusy && !isLocked else { return }
                                if offset >= travel * confirmThreshold {
                                    isLocked = true
                                    withAnimation(.easeOut(duration: 0.12)) {
                                        offset = travel
                                    }
                                    onConfirm()
                                } else {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        offset = 0
                                    }
                                }
                            }
                    )
            }
            .onChange(of: resetToken) { _, _ in
                isLocked = false
                withAnimation(.easeOut(duration: 0.16)) {
                    offset = 0
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel(title)
        .accessibilityHint("Swipe right to confirm")
    }
}

// MARK: - Errors

private enum TripError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

private enum TripLocationError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case preciseLocationDisabled
    case fixTimedOut
    case destinationUnavailable
    case outsideArrivalRadius(CLLocationDistance)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "Location Services are off. Turn them on in Settings to continue."
        case .permissionDenied:
            return "Location access is required. Open Settings and allow location while using the app."
        case .preciseLocationDisabled:
            return "Precise Location is required to verify that you are within 500 m of the client."
        case .fixTimedOut:
            return "Could not get a fresh GPS location. Move to open sky and try again."
        case .destinationUnavailable:
            return "The client location is missing. Add an exact map location before completing this visit."
        case .outsideArrivalRadius(let distance):
            if distance >= 1_000 {
                let value = (distance / 1_000).formatted(.number.precision(.fractionLength(1)))
                return "You are \(value) km away. Move within 500 m to complete."
            }
            let value = distance.formatted(.number.precision(.fractionLength(0)))
            return "You are \(value) m away. Move within 500 m to complete."
        case .unavailable(let message):
            return message
        }
    }
}

private struct DriverOdometerProof {
    let km: Double
    let image: UIImage
}

private enum DriverOdometerPhase {
    case start
    case end

    var title: String {
        switch self {
        case .start: return "Todays Start Update"
        case .end: return "Todays End Update"
        }
    }

    var kmTitle: String {
        switch self {
        case .start: return "Start Km *"
        case .end: return "End Trip Km *"
        }
    }

    var helperText: String {
        switch self {
        case .start: return "Enter odometer start details for the trip."
        case .end: return "Enter odometer end details for the trip."
        }
    }

    var photoHelp: String {
        switch self {
        case .start: return "To start request, document dashboard photo from direct vehicle odometer."
        case .end: return "To complete request, document dashboard photo from direct vehicle odometer."
        }
    }

    var photoTitle: String {
        switch self {
        case .start: return "Start Photo *"
        case .end: return "End Photo *"
        }
    }

    var ctaTitle: String {
        "Submit"
    }
}

private struct DriverOdometerSheet: View {
    let phase: DriverOdometerPhase
    let minimumKm: Double?
    let isSubmitting: Bool
    let onSubmit: (DriverOdometerProof) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kmText = ""
    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    kmField
                    photoSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xB42318))
                    }

                    Button {
                        submit()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                            }
                            Text(isSubmitting ? "Saving..." : phase.ctaTitle)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSubmitting)
                }
                .padding(20)
            }
            .navigationTitle(phase.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .fullScreenCover(isPresented: $showCamera) {
                PunchCameraView(capturedImage: $capturedImage)
                    .ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 50, height: 50)
                .background(Color(hex: 0x0B61CA).opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(phase.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(phase.helperText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var kmField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(phase.kmTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            TextField("Enter Details", text: $kmText)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
                )

            if let minimumKm, phase == .end {
                Text("Starting KM: \(formatKm(minimumKm))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(phase.photoTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Button {
                showCamera = true
            } label: {
                HStack(spacing: 12) {
                    if let capturedImage {
                        Image(uiImage: capturedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .frame(width: 58, height: 58)
                            .background(Color(hex: 0x0B61CA).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(capturedImage == nil ? "Upload Image" : "Retake Image")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(phase.photoHelp)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                }
                .padding(12)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.appSeparator, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func submit() {
        errorMessage = nil
        let trimmed = kmText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let km = Double(trimmed), km >= 0 else {
            errorMessage = "Please enter a valid \(phase.kmTitle.lowercased())."
            return
        }
        if let minimumKm, phase == .end, km < minimumKm {
            errorMessage = "Ending KM cannot be less than starting KM (\(formatKm(minimumKm)))."
            return
        }
        guard let capturedImage else {
            errorMessage = "Please capture a photo of the odometer."
            return
        }
        onSubmit(DriverOdometerProof(km: km, image: capturedImage))
    }

    private func formatKm(_ km: Double) -> String {
        if km.rounded() == km { return "\(Int(km)) KM" }
        return String(format: "%.1f KM", km)
    }
}

private struct CpClientSeenSheet: View {
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 38, height: 5)
                .padding(.top, 8)

            Image(systemName: "person.2.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 60, height: 60)
                .background(Color(hex: 0x0B61CA).opacity(0.10), in: Circle())

            VStack(spacing: 6) {
                Text("Did you meet the client?")
                    .font(.title3.weight(.semibold))

                Text("Confirm whether the client is available at this location before continuing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button(action: onYes) {
                    Label("Yes, client met", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(hex: 0x2DAE12))

                Button(action: onNo) {
                    Label("No, client not available", systemImage: "xmark.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color(hex: 0xB42318))
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }
}

private struct CpTripCompletedSheet: View {
    let onBackHome: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Color(hex: 0x2DAE12))
                .frame(width: 72, height: 72)
                .background(Color(hex: 0x2DAE12).opacity(0.10), in: Circle())
            .padding(.top, 22)

            Text("CP Visit Completed")
                .font(.title3.weight(.semibold))

            Text("The client-not-available outcome has been recorded and the trip is closed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button(action: onBackHome) {
                Label("Back Home", systemImage: "house.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(hex: 0x2DAE12))
            .padding(.horizontal, 20)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
        .background(Color.appSurface)
    }
}

private enum CpSpecialCompletionKind: String, Identifiable {
    case collection
    case oldClient
    case giftDistribution

    init?(cpType: String?) {
        switch cpType.normalizedTripCpMarker {
        case "collection_cp": self = .collection
        case "old_client": self = .oldClient
        case "gift_distribution": self = .giftDistribution
        default: return nil
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collection: return "Payment Entry"
        case .oldClient: return "Old Client Visit"
        case .giftDistribution: return "Gift Distribution"
        }
    }

    var subtitle: String {
        switch self {
        case .collection: return "Submit payment collected from the client."
        case .oldClient: return "Add remarks from the old-client visit."
        case .giftDistribution: return "Confirm the gift handover."
        }
    }

    var primaryTitle: String {
        switch self {
        case .collection: return "Submit Payment"
        case .oldClient: return "Save Remarks"
        case .giftDistribution: return "Confirm Gift"
        }
    }

    var terminalOutcome: String {
        switch self {
        case .collection: return "collection_done"
        case .oldClient: return "old_client_visited"
        case .giftDistribution: return "gift_distributed"
        }
    }

    var clientNotSeenNotes: String {
        switch self {
        case .collection: return "Collection visit — client not present"
        case .oldClient: return "Old client visit — client not present"
        case .giftDistribution: return "Gift distribution — client not present"
        }
    }
}

private struct SpecialCpCompletionSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let kind: CpSpecialCompletionKind
    let cpVisitId: String
    let arrivalProofStorageId: String?
    let initialCollectionNotCollected: Bool
    let onTripCompletion: (CpTripCompletionPayload) -> Void
    let onCompleted: (String?, CpRevisitInfo?) -> Void

    @State private var cpVisit: CpVisitDetail?
    @State private var cases: [PostSaleCaseSummary] = []
    @State private var selectedCaseId = ""
    @State private var amount = ""
    @State private var paymentMode = "upi"
    @State private var reference = ""
    @State private var bankName = ""
    @State private var branchName = ""
    @State private var paymentInstrumentDate = Date()
    @State private var remarks = ""
    @State private var oldClientOutcome = "old_client_visited"
    @State private var proofImage: UIImage?
    @State private var collectionProofFile: PostSalesUploadedFile?
    @State private var collectionNotCollected: Bool
    @State private var showProofCamera = false
    @State private var showCollectionProofImporter = false
    @State private var isUploadingCollectionProof = false
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    // Collection follow-up: when the staff returns to collect a pending balance
    // (nothing collected, or a partial). Defaults to tomorrow.
    @State private var followUpDate =
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    init(
        kind: CpSpecialCompletionKind,
        cpVisitId: String,
        arrivalProofStorageId: String?,
        initialCollectionNotCollected: Bool = false,
        onTripCompletion: @escaping (CpTripCompletionPayload) -> Void,
        onCompleted: @escaping (String?, CpRevisitInfo?) -> Void
    ) {
        self.kind = kind
        self.cpVisitId = cpVisitId
        self.arrivalProofStorageId = arrivalProofStorageId
        self.initialCollectionNotCollected = initialCollectionNotCollected
        self.onTripCompletion = onTripCompletion
        self.onCompleted = onCompleted
        _collectionNotCollected = State(initialValue: initialCollectionNotCollected)
    }

    private var selectedCasePending: Double { selectedCase?.balanceAmount ?? 0 }

    private var cpVisitDetailCacheKey: String {
        "marketing.site-visit.detail.\(cpVisitId)"
    }

    private func collectionCasesCacheKey(phone: String) -> String {
        let staffId = authStore.viewer?.subject ?? authStore.currentSession?.user._id ?? "anonymous"
        return "postsales.collection-cases.\(staffId).\(phone)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isLoading {
                        ProgressView("Loading details...")
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else if kind == .collection {
                        collectionFields
                    } else {
                        remarksFields
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 96)
            }

            footer
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .task { await load() }
        .fullScreenCover(isPresented: $showProofCamera) {
            PunchCameraView(capturedImage: $proofImage)
        }
        .fileImporter(
            isPresented: $showCollectionProofImporter,
            allowedContentTypes: [.pdf, .jpeg, .png, .webP],
            allowsMultipleSelection: false
        ) { result in
            Task { await importCollectionProof(result) }
        }
        .onChange(of: proofImage) { _, image in
            if image != nil { collectionProofFile = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(collectionNotCollected ? "Collection not done" : kind.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                Text(
                    collectionNotCollected
                        ? "Choose a follow-up date and close this visit at ₹0."
                        : kind.subtitle
                )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(TripGlassCircleButtonStyle())
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var collectionFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            if collectionNotCollected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing collected")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: 0xB54708))
                    Text("This visit will close as Not Collected with amount ₹0. Choose when the collection should be followed up.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(hex: 0xB54708).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

                sheetTextField(
                    "Reason (optional)",
                    text: $remarks,
                    placeholder: "Why was no amount collected?",
                    axis: .vertical
                )
            } else if cases.isEmpty {
                // Amber, not red: an empty lookup is usually recoverable. It
                // can mean the number is stored in a shape the search missed,
                // that the booking sits outside this staff's scope, or that a
                // read-heavy query failed. Saying "no booking exists" as a
                // hard error is what made staff distrust this screen.
                VStack(alignment: .leading, spacing: 10) {
                    Text("No booking found for this client's mobile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xB54708))
                    Text("If the client does have a booking, retry — the lookup can miss a number saved with a country code.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0x92400E))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await load() }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: 0xB54708))
                    .disabled(isLoading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(hex: 0xB54708).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Booking")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Menu {
                        ForEach(cases) { item in
                            Button(item.title) {
                                selectedCaseId = item.id
                            }
                        }
                    } label: {
                        pickerRow(selectedCase?.title ?? "Select Booking", subtitle: selectedCase?.subtitle)
                    }
                }
            }

            if !collectionNotCollected {
                sheetTextField("Amount *", text: $amount, placeholder: "Enter amount", keyboard: .decimalPad)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Payment Mode")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Menu {
                        Picker("Payment Mode", selection: $paymentMode) {
                            ForEach(collectionPaymentModes, id: \.id) { mode in
                                Text(mode.label).tag(mode.id)
                            }
                        }
                    } label: {
                        pickerRow(selectedPaymentModeLabel, subtitle: nil)
                    }
                }

                sheetTextField(
                    paymentReferenceTitle,
                    text: $reference,
                    placeholder: paymentReferencePlaceholder
                )
                if isInstrumentPayment {
                    sheetTextField("Bank Name *", text: $bankName, placeholder: "Enter bank name")
                    sheetTextField("Branch Name *", text: $branchName, placeholder: "Enter branch name")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cheque / DD Date *")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        DatePicker(
                            "Cheque / DD Date",
                            selection: $paymentInstrumentDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 54)
                        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
                        }
                    }
                }
                proofCapture(
                    title: "Payment Proof",
                    help: "Capture the receipt, cheque, or transfer confirmation."
                )
                sheetTextField("Notes", text: $remarks, placeholder: "Payment notes", axis: .vertical)
            }

            if let selectedCase {
                Text("Payable \(AppModuleFormatters.rupees(selectedCase.totalAmount ?? 0)) · Paid \(AppModuleFormatters.rupees(selectedCase.approvedCollectedAmount ?? 0)) · Pending \(AppModuleFormatters.rupees(selectedCase.balanceAmount ?? 0))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if needsCollectionFollowUp {
                VStack(alignment: .leading, spacing: 6) {
                Text("Follow-up visit (if a balance remains)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                DatePicker(
                    "Follow-up",
                    selection: $followUpDate,
                    in: Date()...(Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date()),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var remarksFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            if kind == .oldClient {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Outcome")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Picker("Outcome", selection: $oldClientOutcome) {
                        Text("Visited").tag("old_client_visited")
                        Text("Others").tag("other")
                    }
                    .pickerStyle(.segmented)
                    Text(
                        oldClientOutcome == "other"
                            ? "Add remarks to explain why this Old Client CP is being closed."
                            : "Confirm the Old Client visit and save the staff remarks."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(kind == .giftDistribution ? "Gift handover will be marked completed for this CP visit." : "Remarks are saved against this CP visit.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if kind == .giftDistribution {
                proofCapture(
                    title: "Gift Handover Photo *",
                    help: "Capture the gift being handed to the OTP-verified client."
                )
            }
            sheetTextField(kind == .giftDistribution ? "Notes" : "Remarks *", text: $remarks, placeholder: kind == .giftDistribution ? "Optional handover notes" : "Enter visit remarks", axis: .vertical)
        }
    }

    private func proofCapture(title: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Button {
                showProofCamera = true
            } label: {
                HStack(spacing: 12) {
                    if let proofImage {
                        Image(uiImage: proofImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(.rect(cornerRadius: 12))
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .frame(width: 58, height: 58)
                            .background(Color(hex: 0x0B61CA).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(proofImage == nil ? "Capture photo" : "Retake photo")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(help)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color(hex: 0x98A2B3))
                }
                .padding(12)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            if kind == .collection {
                Button {
                    showCollectionProofImporter = true
                } label: {
                    Label("Attach PDF or image", systemImage: "paperclip")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
            if isUploadingCollectionProof {
                ProgressView("Uploading proof...")
                    .font(.caption)
            } else if let collectionProofFile, kind == .collection {
                Label(collectionProofFile.fileName, systemImage: "doc.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()
                .overlay(Color.appSeparator)
            Button {
                Task { await submit(notCollected: false) }
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(submitTitle)
                }
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color(hex: 0x1BCA0B), in: Capsule())
            .disabled(
                isSaving || isLoading || isUploadingCollectionProof ||
                    (kind == .collection && !collectionNotCollected && selectedCaseId.isEmpty) ||
                    (kind == .collection && !collectionNotCollected && !hasValidCollectionPayment)
            )
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 14)
        .background(Color.white)
    }

    private var submitTitle: String {
        if kind == .collection && collectionNotCollected {
            return "Mark Not Collected"
        }
        if kind == .oldClient && oldClientOutcome == "other" {
            return "Complete with Remarks"
        }
        return kind.primaryTitle
    }

    private var selectedCase: PostSaleCaseSummary? {
        cases.first { $0.id == selectedCaseId }
    }

    private var collectionPaymentModes: [(id: String, label: String)] {
        [
            ("upi", "UPI"),
            ("cash", "Cash"),
            ("neft", "NEFT"),
            ("rtgs", "RTGS"),
            ("cheque", "Cheque"),
            ("dd", "DD"),
            ("bank", "Bank")
        ]
    }

    private var selectedPaymentModeLabel: String {
        collectionPaymentModes.first { $0.id == paymentMode }?.label ?? paymentMode.uppercased()
    }

    private var isCashPayment: Bool { paymentMode == "cash" }

    private var isInstrumentPayment: Bool { paymentMode == "cheque" || paymentMode == "dd" }

    private var paymentReferenceTitle: String {
        if isCashPayment { return "Reference (optional)" }
        if isInstrumentPayment { return "\(selectedPaymentModeLabel) Number *" }
        return "Transaction ID *"
    }

    private var paymentReferencePlaceholder: String {
        if isCashPayment { return "Optional receipt / reference" }
        if isInstrumentPayment { return "Enter \(selectedPaymentModeLabel) number" }
        return "UTR / transaction reference"
    }

    private var hasValidCollectionPayment: Bool {
        guard (Double(amount) ?? 0) > 0 else { return false }
        if !isCashPayment && reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if isInstrumentPayment {
            return !bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var needsCollectionFollowUp: Bool {
        guard kind == .collection else { return false }
        if collectionNotCollected { return true }
        guard let amountValue = Double(amount), amountValue > 0 else { return false }
        return selectedCasePending > 0.005 && amountValue < selectedCasePending - 0.005
    }

    private func pickerRow(_ title: String, subtitle: String?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
        )
    }

    private func sheetTextField(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType = .default,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            TextField(placeholder, text: text, axis: axis)
                .font(.system(size: 15, weight: .medium))
                .keyboardType(keyboard)
                .lineLimit(axis == .vertical ? 3...5 : 1...1)
                .padding(.horizontal, 14)
                .padding(.vertical, axis == .vertical ? 12 : 0)
                .frame(minHeight: axis == .vertical ? 92 : 54, alignment: axis == .vertical ? .top : .center)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: 0xD0D5DD), lineWidth: 1)
                )
        }
    }

    @MainActor
    private func load() async {
        // The No path does not need client booking data. Keep it instant and
        // show only follow-up date + optional reason.
        if kind == .collection && collectionNotCollected { return }
        guard !isLoading else { return }
        guard let token = authStore.currentSession?.token else { return }

        if cpVisit == nil,
           let cachedDetail = LocalCache.get(cpVisitDetailCacheKey, as: CpVisitDetail.self) {
            cpVisit = cachedDetail
            restoreCachedCollectionCases(from: cachedDetail)
        }

        isLoading = cpVisit == nil || (kind == .collection && cases.isEmpty)
        defer { isLoading = false }
        do {
            let detail = try await MarketingConvexAPIService.getCpVisitDetail(token: token, id: cpVisitId)
            cpVisit = detail
            LocalCache.put(cpVisitDetailCacheKey, detail)
            guard kind == .collection, !collectionNotCollected else { return }
            let phone = collectionPhone(from: detail)
            guard let phone else {
                errorMessage = "Client mobile is missing for payment collection."
                return
            }
            cases = try await PostSalesConvexAPIService.getCasesByMobile(token: token, mobile: phone)
            LocalCache.put(collectionCasesCacheKey(phone: phone), cases)
            // An empty `cases` used to CLOSE the CP as "rejected - client has
            // no confirmed booking", automatically and irreversibly. An empty
            // list is not proof of that: it also happens when the lookup is
            // scoped away from this staff, when the number is stored in a
            // shape the search missed, or when a read-heavy query fails. Field
            // staff reported exactly that - a real booking, and a CP closed out
            // from under them.
            //
            // Now it simply stays empty, which drives the recoverable notice in
            // collectionFields, and the staff decides.
            if let first = cases.first,
               !cases.contains(where: { $0.id == selectedCaseId }) {
                selectedCaseId = first.id
            }
        } catch {
            if cpVisit == nil || (kind == .collection && cases.isEmpty) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func collectionPhone(from detail: CpVisitDetail) -> String? {
        [
            detail.client?.mobileNumber,
            detail.lead?.mobileNumber,
            detail.clientPlace?.contactPhone
        ]
        .compactMap { $0 }
        .map(AppModuleFormatters.normalizePhone)
        .first { $0.count == 10 }
    }

    @MainActor
    private func restoreCachedCollectionCases(from detail: CpVisitDetail) {
        guard kind == .collection,
              let phone = collectionPhone(from: detail),
              let cached = LocalCache.get(
                collectionCasesCacheKey(phone: phone),
                as: [PostSaleCaseSummary].self
              )
        else { return }
        cases = cached
        if !cached.contains(where: { $0.id == selectedCaseId }) {
            selectedCaseId = cached.first?.id ?? ""
        }
    }

    @MainActor
    private func submit(notCollected: Bool) async {
        guard let token = authStore.currentSession?.token else { return }
        if kind == .oldClient, remarks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter visit remarks."
            return
        }
        if kind == .giftDistribution, proofImage == nil {
            errorMessage = "Capture the gift handover photo."
            return
        }

        let effectiveNotCollected = notCollected || collectionNotCollected
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_IN")
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.locale = Locale(identifier: "en_IN")
        let followUpDateValue = dateFormatter.string(from: followUpDate)
        let followUpTimeValue = timeFormatter.string(from: followUpDate)

        isSaving = true
        defer { isSaving = false }
        do {
            var notes = remarks.trimmingCharacters(in: .whitespacesAndNewlines)
            var replacementProofId: String?
            var outcome = kind == .oldClient ? oldClientOutcome : kind.terminalOutcome
            var sendFollowUp = false

            if kind == .collection {
                if effectiveNotCollected {
                    outcome = "not_collected"
                    sendFollowUp = true
                    notes = notes.isEmpty ? "Not collected" : "Not collected — \(notes)"
                } else {
                    guard !selectedCaseId.isEmpty else {
                        errorMessage = "Select the booking you collected against."
                        return
                    }
                    guard let amountValue = Double(amount), amountValue > 0 else {
                        errorMessage = "Enter the amount received (greater than zero)."
                        return
                    }
                    let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !isCashPayment && trimmedReference.isEmpty {
                        errorMessage = "Transaction ID is required (UTR / Cheque / Ref no)."
                        return
                    }
                    let trimmedBankName = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isInstrumentPayment && (trimmedBankName.isEmpty || trimmedBranchName.isEmpty) {
                        errorMessage = "Enter bank, branch and cheque/DD date."
                        return
                    }
                    let paymentProofId: String?
                    if let uploadedProofId = collectionProofFile?.storageId {
                        paymentProofId = uploadedProofId
                    } else {
                        paymentProofId = try await uploadProofIfPresent(token: token)
                    }
                    let submission = try await PostSalesConvexAPIService.submitCollection(
                        token: token,
                        request: SubmitCollectionRequest(
                            cpVisitId: cpVisitId,
                            caseId: selectedCaseId,
                            amount: amountValue,
                            paymentMode: paymentMode,
                            transactionReference: trimmedReference.nilIfEmpty,
                            bankName: isInstrumentPayment ? trimmedBankName.nilIfEmpty : nil,
                            branchName: isInstrumentPayment ? trimmedBranchName.nilIfEmpty : nil,
                            paymentInstrumentDate: isInstrumentPayment ? collectionDateString(paymentInstrumentDate) : nil,
                            proofStorageId: paymentProofId,
                            proofFileName: collectionProofFile?.fileName
                                ?? (paymentProofId == nil ? nil : "cp-collection-proof.jpg"),
                            notes: notes.nilIfEmpty
                        )
                    )
                    sendFollowUp = selectedCasePending > 0.005
                        && amountValue < selectedCasePending - 0.005
                    notes = [
                        "Collection submitted: \(AppModuleFormatters.rupees(amountValue))",
                        submission.reference.isEmpty ? nil : "Receipt: \(submission.reference)",
                        submission.alreadySubmitted ? "Collection was already submitted" : nil,
                        trimmedReference.nilIfEmpty,
                        notes.nilIfEmpty
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                }
            } else if kind == .giftDistribution {
                replacementProofId = try await uploadProofIfPresent(token: token)
                notes = notes.isEmpty
                    ? "Gift distributed — handover photo attached"
                    : "Gift distributed — handover photo attached\n\(notes)"
            }

            try await MarketingConvexAPIService.markClientMet(
                token: token,
                request: MarkClientMetRequest(id: cpVisitId, clientMet: true)
            )
            let revisit = try await MarketingConvexAPIService.setCpVisitOutcome(
                token: token,
                request: SetCpVisitOutcomeRequest(
                    id: cpVisitId,
                    outcome: outcome,
                    postponeReasons: nil,
                    notes: notes.nilIfEmpty,
                    arrivalPhotoStorageId: kind == .giftDistribution ? replacementProofId : nil,
                    followUpDate: sendFollowUp ? followUpDateValue : nil,
                    followUpTime: sendFollowUp ? followUpTimeValue : nil
                )
            )
            onTripCompletion(
                CpTripCompletionPayload(
                    clientMet: true,
                    outcome: outcome,
                    notes: notes.nilIfEmpty,
                    postponeReasons: nil,
                    followUpDate: sendFollowUp ? followUpDateValue : nil,
                    followUpTime: sendFollowUp ? followUpTimeValue : nil
                )
            )
            onCompleted(replacementProofId, revisit)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadProofIfPresent(token: String) async throws -> String? {
        guard let proofImage else { return nil }
        guard let data = proofImage.jpegData(compressionQuality: 0.72) else {
            throw TripError.message("Could not encode proof photo")
        }
        return try await HRConvexAPIService.uploadPhoto(token: token, imageData: data)
    }

    @MainActor
    private func importCollectionProof(_ result: Result<[URL], Error>) async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            guard let url = try result.get().first else { return }
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = values.fileSize ?? 0
            let allowedTypes: Set<UTType> = [.pdf, .jpeg, .png, .webP]
            guard let type = UTType(filenameExtension: url.pathExtension),
                  allowedTypes.contains(type) else {
                errorMessage = "Proof must be PDF, JPG, PNG or WebP."
                return
            }
            guard fileSize <= 10 * 1024 * 1024 else {
                errorMessage = "Proof must be 10 MB or smaller."
                return
            }
            isUploadingCollectionProof = true
            defer { isUploadingCollectionProof = false }
            collectionProofFile = try await PostSalesStorageService.uploadFile(token: token, fileURL: url)
            proofImage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func collectionDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct TripGlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .fill(configuration.isPressed ? Color.white.opacity(0.28) : Color.white.opacity(0.08))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.9 : 0.72), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.04 : 0.10),
                radius: configuration.isPressed ? 5 : 12,
                x: 0,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.18, extraBounce: 0.22), value: configuration.isPressed)
    }
}

private extension Optional where Wrapped == String {
    var normalizedTripCpMarker: String {
        self?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        ?? ""
    }
}

private extension String {
    var normalizedTripCpMarker: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Location

@MainActor
@Observable
final class TripLocationManager: NSObject, CLLocationManagerDelegate {
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var pendingLocation: CheckedContinuation<CLLocation, any Error>?
    private var locationTimeoutTask: Task<Void, Never>?

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

    var needsSettings: Bool {
        authorizationStatus == .denied
            || authorizationStatus == .restricted
            || (
                (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways)
                    && manager.accuracyAuthorization == .reducedAccuracy
            )
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Android uses FusedLocationProvider.getCurrentLocation(HIGH_ACCURACY)
    /// before proximity checks. Mirror that behavior by waiting for a fresh,
    /// precise Core Location fix instead of sleeping and reading stale state.
    func freshPreciseLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus
        authorizationStatus = status
        guard status != .denied && status != .restricted else {
            throw TripLocationError.permissionDenied
        }

        if status == .authorizedWhenInUse || status == .authorizedAlways,
           manager.accuracyAuthorization == .reducedAccuracy {
            throw TripLocationError.preciseLocationDisabled
        }

        pendingLocation?.resume(throwing: TripLocationError.unavailable("A newer location request replaced the previous one."))
        pendingLocation = nil
        locationTimeoutTask?.cancel()

        return try await withCheckedThrowingContinuation { continuation in
            pendingLocation = continuation

            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }

            locationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let pending = self.pendingLocation else { return }
                    self.pendingLocation = nil
                    pending.resume(throwing: TripLocationError.fixTimedOut)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in
            currentLocation = loc
            locationTimeoutTask?.cancel()
            locationTimeoutTask = nil
            pendingLocation?.resume(returning: loc)
            pendingLocation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationTimeoutTask?.cancel()
            locationTimeoutTask = nil
            pendingLocation?.resume(throwing: TripLocationError.unavailable(error.localizedDescription))
            pendingLocation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if manager.accuracyAuthorization == .reducedAccuracy {
                    locationTimeoutTask?.cancel()
                    locationTimeoutTask = nil
                    pendingLocation?.resume(throwing: TripLocationError.preciseLocationDisabled)
                    pendingLocation = nil
                } else {
                    manager.requestLocation()
                }
            } else if status == .denied || status == .restricted {
                locationTimeoutTask?.cancel()
                locationTimeoutTask = nil
                pendingLocation?.resume(throwing: TripLocationError.permissionDenied)
                pendingLocation = nil
            }
        }
    }
}
