import AVFoundation
import Foundation
import SwiftUI

private struct SiteVisitQRLookupTimeout: Error {}

struct FrontDeskQRScannerView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var scannedValue: String?
    @State private var cameraAccessDenied = false
    @State private var scanLineAnimating = false
    @State private var showScanResult = false
    @State private var isResolvingInvitation = false
    @State private var invitation: FrontDeskInvitation?
    @State private var scanError: String?
    @State private var visitorActionError: String?
    @State private var isVisitorActionRunning = false
    @State private var isSiteVisitScan = false
    @State private var scannedSiteVisit: ScannedSiteVisit?
    @State private var showSiteVisitOutcome = false
    @State private var outcomeSiteVisitID: String?
    @State private var lookupTask: Task<Void, Never>?
    let showsCloseButton: Bool

    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            QRScannerCameraView(scannedValue: $scannedValue, cameraAccessDenied: $cameraAccessDenied)
                .ignoresSafeArea()

            scannerOverlay
            scannerHeader

            if cameraAccessDenied {
                cameraDeniedCard
            }

        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: scannedValue)
        .onChange(of: scannedValue) { _, value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            scanLineAnimating = false
            beginScanLookup(value)
        }
        .onDisappear {
            lookupTask?.cancel()
        }
        .sheet(isPresented: $showScanResult, onDismiss: resetScanner) {
            Group {
                if isSiteVisitScan {
                    SiteVisitCounsellingSheet(
                        visit: scannedSiteVisit,
                        isLoading: isResolvingInvitation,
                        errorMessage: scanError,
                        actionError: visitorActionError,
                        isActionRunning: isVisitorActionRunning,
                        canRecordOutcomeFallback: authStore.hasPermission("marketing.siteVisits.scanConsulting"),
                        onStart: startSiteVisitCounselling,
                        onOpenOutcome: openScannedSiteVisitOutcome,
                        onScanAnother: { showScanResult = false }
                    )
                } else {
                    FrontDeskInvitationSheet(
                        invitation: invitation,
                        rawValue: scannedValue,
                        isLoading: isResolvingInvitation,
                        errorMessage: scanError,
                        actionError: visitorActionError,
                        isActionRunning: isVisitorActionRunning,
                        canCheckIn: authStore.hasPermission("frontdesk.checkin"),
                        canCheckOut: authStore.hasPermission("frontdesk.checkout"),
                        onCheckIn: checkInInvitation,
                        onCheckOut: checkOutInvitation,
                        onScanAnother: { showScanResult = false }
                    )
                }
            }
            .presentationDetents([.fraction(0.62), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appElevatedSurface)
            .interactiveDismissDisabled(isVisitorActionRunning)
        }
        .sheet(isPresented: $showSiteVisitOutcome, onDismiss: resetScanner) {
            if let outcomeSiteVisitID {
                SiteVisitOutcomeSheet(siteVisitId: outcomeSiteVisitID) {
                    showSiteVisitOutcome = false
                }
                .appLibraryNativeSheet([.large])
            }
        }
    }

    private var canViewHistory: Bool {
        authStore.hasPermission("frontdesk.view")
    }

    private var scannerHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: showsCloseButton ? "xmark" : "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .accessibilityLabel(showsCloseButton ? "Close scanner" : "Back")
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Front Desk Scanner")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 2)

                HStack(spacing: 10) {
                    if canViewHistory {
                        NavigationLink {
                            FrontDeskQRHistoryView()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .background(.black.opacity(0.28), in: Circle())
                        }
                        .accessibilityLabel("Open scan history")
                    }

                    if scannedValue != nil {
                        Button {
                            showScanResult = false
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .background(.black.opacity(0.28), in: Circle())
                        }
                        .accessibilityLabel("Scan another QR code")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.top, 58)

            Spacer()
        }
        .ignoresSafeArea(edges: .top)
    }

    private var scannerOverlay: some View {
        GeometryReader { proxy in
            let boxSize = min(proxy.size.width * 0.72, 292)
            let centerYOffset = proxy.size.height * 0.07

            VStack(spacing: 22) {
                ScannerTargetView(
                    size: boxSize,
                    isAnimating: scanLineAnimating && scannedValue == nil
                )

                Text("Align QR code inside the box to scan")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: centerYOffset)
            .padding(.horizontal, 24)
            .background(
                Rectangle()
                    .fill(.black.opacity(scannedValue == nil ? 0.22 : 0.44))
                    .ignoresSafeArea()
            )
            .onAppear {
                restartScanLine()
            }
        }
    }

    private var cameraDeniedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))

            Text("Camera permission needed")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Enable camera access in Settings to scan Front Desk QR codes.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: 300)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    fileprivate static func inviteToken(from value: String) -> String? {
        let marker = "/frontdesk/invite/"
        guard let range = value.range(of: marker) else { return nil }
        return String(value[range.upperBound...])
            .split(separator: "?")
            .first?
            .split(separator: "#")
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    fileprivate static func siteVisitID(from value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.lowercased().hasPrefix("sv:") {
            return String(raw.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        let marker = "/site-visit/consulting/"
        guard let range = raw.range(of: marker, options: .caseInsensitive) else { return nil }
        return String(raw[range.upperBound...])
            .split(separator: "?").first?
            .split(separator: "#").first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            .nilIfBlank
    }

    private func beginScanLookup(_ value: String) {
        if let siteVisitID = Self.siteVisitID(from: value) {
            beginSiteVisitLookup(siteVisitID)
        } else {
            beginInvitationLookup(value)
        }
    }

    private func beginSiteVisitLookup(_ siteVisitID: String) {
        lookupTask?.cancel()
        invitation = nil
        scannedSiteVisit = nil
        scanError = nil
        visitorActionError = nil
        isSiteVisitScan = true
        isResolvingInvitation = true
        showScanResult = true

        lookupTask = Task {
            guard let token = authStore.currentSession?.token else {
                isResolvingInvitation = false
                scanError = "Please sign in again to validate this site visit."
                return
            }
            do {
                scannedSiteVisit = try await loadSiteVisitQRWithRetry(
                    token: token,
                    siteVisitID: siteVisitID
                )
            } catch {
                guard !Task.isCancelled else { return }
                scanError = error is SiteVisitQRLookupTimeout
                    ? "The SV details are taking too long to load. Check the connection and scan again."
                    : error.localizedDescription
            }
            isResolvingInvitation = false
        }
    }

    private func loadSiteVisitQRWithRetry(token: String, siteVisitID: String) async throws -> ScannedSiteVisit {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try await loadSiteVisitQRWithTimeout(token: token, siteVisitID: siteVisitID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                let retryable = error is URLError || error is SiteVisitQRLookupTimeout
                guard retryable, attempt == 0 else { throw error }
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        throw lastError ?? SiteVisitQRLookupTimeout()
    }

    private func loadSiteVisitQRWithTimeout(token: String, siteVisitID: String) async throws -> ScannedSiteVisit {
        try await withThrowingTaskGroup(of: ScannedSiteVisit.self) { group in
            group.addTask {
                try await MarketingConvexAPIService.scanSiteVisitQR(
                    token: token,
                    qrData: "SV:\(siteVisitID)"
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw SiteVisitQRLookupTimeout()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw SiteVisitQRLookupTimeout()
            }
            return result
        }
    }

    private func startSiteVisitCounselling() async {
        guard let token = authStore.currentSession?.token, let visit = scannedSiteVisit else { return }
        isVisitorActionRunning = true
        visitorActionError = nil
        do {
            try await MarketingConvexAPIService.markSiteVisitOnCounselling(token: token, id: visit.id)
        } catch {
            // Match Android: show the transition failure but never dead-end the
            // authorised operator; the outcome screen reloads server truth.
            visitorActionError = error.localizedDescription
        }
        isVisitorActionRunning = false
        openScannedSiteVisitOutcome()
    }

    private func openScannedSiteVisitOutcome() {
        guard let id = scannedSiteVisit?.id else { return }
        outcomeSiteVisitID = id
        showScanResult = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            showSiteVisitOutcome = true
        }
    }

    private func beginInvitationLookup(_ value: String) {
        lookupTask?.cancel()
        invitation = nil
        scanError = nil
        visitorActionError = nil
        isSiteVisitScan = false
        isResolvingInvitation = true
        showScanResult = true

        lookupTask = Task {
            guard let inviteToken = Self.inviteToken(from: value) else {
                isResolvingInvitation = false
                scanError = "This QR code is not a Front Desk invitation."
                FrontDeskQRHistoryStore.add(value)
                return
            }
            guard let token = authStore.currentSession?.token else {
                isResolvingInvitation = false
                scanError = "Please sign in again to view this invitation."
                return
            }

            do {
                let resolved = try await FrontDeskAPIService.invitation(
                    token: token,
                    inviteToken: inviteToken
                )
                guard !Task.isCancelled else { return }
                invitation = resolved
                isResolvingInvitation = false
            } catch {
                guard !Task.isCancelled else { return }
                scanError = error.localizedDescription
                isResolvingInvitation = false
            }
        }
    }

    private func checkInInvitation() async {
        guard let token = authStore.currentSession?.token,
              var invitation,
              let invitationID = invitation.invitationID else { return }

        isVisitorActionRunning = true
        visitorActionError = nil
        defer { isVisitorActionRunning = false }
        do {
            let result = try await FrontDeskAPIService.checkIn(
                token: token,
                invitationID: invitationID
            )
            invitation.status = "checked_in"
            invitation.checkinState = "in"
            invitation.checkinAt = Int64(Date().timeIntervalSince1970 * 1_000)
            invitation.passNumber = result.passNumber
            self.invitation = invitation
            FrontDeskQRHistoryStore.add(
                invitation: invitation,
                status: "checked_in",
                passNumber: result.passNumber
            )
        } catch {
            visitorActionError = error.localizedDescription
        }
    }

    private func checkOutInvitation() async {
        guard let token = authStore.currentSession?.token,
              var invitation,
              let invitationID = invitation.invitationID else { return }

        isVisitorActionRunning = true
        visitorActionError = nil
        defer { isVisitorActionRunning = false }
        do {
            let result = try await FrontDeskAPIService.checkOut(
                token: token,
                invitationID: invitationID
            )
            invitation.checkinState = "out"
            invitation.checkoutAt = result.checkoutAt ?? Int64(Date().timeIntervalSince1970 * 1_000)
            self.invitation = invitation
            FrontDeskQRHistoryStore.updateStatus(
                invitationID: invitationID,
                status: "checked_out"
            )
        } catch {
            visitorActionError = error.localizedDescription
        }
    }

    private func resetScanner() {
        lookupTask?.cancel()
        lookupTask = nil
        scannedValue = nil
        invitation = nil
        scannedSiteVisit = nil
        isSiteVisitScan = false
        scanError = nil
        visitorActionError = nil
        isResolvingInvitation = false
        isVisitorActionRunning = false
        restartScanLine()
    }

    private func restartScanLine() {
        scanLineAnimating = false
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 1.55).repeatForever(autoreverses: true)) {
                scanLineAnimating = true
            }
        }
    }
}

private struct SiteVisitCounsellingSheet: View {
    let visit: ScannedSiteVisit?
    let isLoading: Bool
    let errorMessage: String?
    let actionError: String?
    let isActionRunning: Bool
    let canRecordOutcomeFallback: Bool
    let onStart: () async -> Void
    let onOpenOutcome: () -> Void
    let onScanAnother: () -> Void

    @State private var countdown = 5

    private var normalizedStatus: String {
        visit?.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var isOngoing: Bool { normalizedStatus == "on_counselling" }
    private var isCompleted: Bool {
        normalizedStatus == "completed" || visit?.outcome?.nilIfBlank != nil
    }
    private var canStart: Bool { visit?.canStartCounselling == true && !isOngoing && !isCompleted }
    private var canOpenOutcome: Bool {
        ((visit?.canRecordOutcome == true) || canRecordOutcomeFallback) && isOngoing && !isCompleted
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Validating site visit...")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    ContentUnavailableView("SV QR Unavailable", systemImage: "qrcode", description: Text(errorMessage))
                } else if let visit {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "person.2.badge.gearshape.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x0B61CA))
                                    .frame(width: 46, height: 46)
                                    .background(Color(hex: 0xEAF4FF), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(clientName(visit))
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.primary)
                                    Text(projectName(visit))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let temperature = visit.lead?.temperature?.nilIfBlank {
                                    Text("\(temperature.uppercased()) LEAD")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(temperatureColor(temperature))
                                        .padding(.horizontal, 9)
                                        .frame(height: 27)
                                        .background(temperatureColor(temperature).opacity(0.1), in: Capsule())
                                }
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                detailCard("Mobile", phone(visit), "phone.fill")
                                detailCard("Occupation", visit.lead?.profession?.nilIfBlank ?? visit.client?.profession?.nilIfBlank ?? "Not provided", "briefcase.fill")
                                detailCard("BDO", visit.bdoStaff?.name?.nilIfBlank ?? visit.telecallerStaff?.name?.nilIfBlank ?? "Not assigned", "person.fill")
                                detailCard("Site Incharge", visit.inchargeStaff?.name?.nilIfBlank ?? "Not assigned", "person.badge.shield.checkmark.fill")
                            }

                            detailRow("Schedule", [visit.scheduledDate?.nilIfBlank, visit.scheduledTime?.nilIfBlank].compactMap { $0 }.joined(separator: " - "), "calendar")
                            detailRow("Additional visitors", additionalVisitors(visit), "person.3.fill")
                            detailRow("Food preference", visit.foodPreferences?.nilIfBlank ?? "Not provided", "fork.knife")

                            if let actionError {
                                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(hex: 0xB42318))
                            }

                            Text(accessMessage(visit))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle((canStart || canOpenOutcome || isCompleted) ? Color(hex: 0x667085) : Color(hex: 0xB54708))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Start Counselling")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if !isLoading {
                    VStack(spacing: 10) {
                        if canStart {
                            Button { Task { await onStart() } } label: {
                                if isActionRunning { ProgressView().frame(maxWidth: .infinity) }
                                else { Text("Start counselling").frame(maxWidth: .infinity) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(Color(hex: 0x2DAE12))
                            .disabled(isActionRunning)
                        }
                        Button("Scan another QR", action: onScanAnother)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                    .padding(16)
                    .background(.bar)
                }
            }
        }
        .task(id: canOpenOutcome) {
            guard canOpenOutcome else { return }
            countdown = 5
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                countdown -= 1
            }
            onOpenOutcome()
        }
    }

    private func clientName(_ visit: ScannedSiteVisit) -> String {
        visit.lead?.clientName?.nilIfBlank
            ?? visit.lead?.contactName?.nilIfBlank
            ?? visit.client?.clientName?.nilIfBlank
            ?? "Client name unavailable"
    }

    private func projectName(_ visit: ScannedSiteVisit) -> String {
        visit.project?.projectName?.nilIfBlank ?? visit.project?.name?.nilIfBlank ?? "Project unavailable"
    }

    private func phone(_ visit: ScannedSiteVisit) -> String {
        visit.lead?.mobileNumber?.nilIfBlank
            ?? visit.lead?.mobileNumberNormalized?.nilIfBlank
            ?? visit.client?.mobileNumber?.nilIfBlank
            ?? visit.client?.mobileNumberNormalized?.nilIfBlank
            ?? "Not provided"
    }

    private func additionalVisitors(_ visit: ScannedSiteVisit) -> String {
        let primary = clientName(visit)
        let visitors = (visit.attendees ?? []).filter {
            $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(primary) != .orderedSame
        }
        let rows = visitors.enumerated().map { index, attendee in
            let name = attendee.name?.nilIfBlank ?? "Visitor \(index + 1)"
            let details = [attendee.relation?.nilIfBlank, attendee.age?.nilIfBlank.map { "Age \($0)" }].compactMap { $0 }
            return details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"
        }
        if !rows.isEmpty { return rows.joined(separator: "\n") }
        let count = max((visit.expectedAttendeeCount ?? 1) - 1, 0)
        return count == 0 ? "No additional visitors listed" : "\(count) additional visitor\(count == 1 ? "" : "s")"
    }

    private func accessMessage(_ visit: ScannedSiteVisit) -> String {
        if isCompleted { return "The site visit outcome has been recorded." }
        if canOpenOutcome { return "You will be redirected to the outcome page in \(countdown)s" }
        if canStart { return "Confirm only when counselling is actually starting." }
        let incharge = visit.inchargeStaff?.name?.nilIfBlank ?? "the Site Incharge"
        if isOngoing { return "Counselling is in progress. You don't have access to close this site visit — please contact \(incharge)." }
        return "You don't have access to start counselling or close this site visit. Please contact \(incharge)."
    }

    private func detailCard(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title.uppercased(), systemImage: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: 0x98A2B3))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color(hex: 0x0B61CA)).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0x98A2B3))
                Text(value.nilIfBlank ?? "Not provided").font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
            }
        }
    }

    private func temperatureColor(_ value: String) -> Color {
        switch value.lowercased() {
        case "hot": return Color(hex: 0xDC2626)
        case "warm": return Color(hex: 0xD97706)
        default: return Color(hex: 0x0B61CA)
        }
    }
}

private struct FrontDeskInvitationSheet: View {
    let invitation: FrontDeskInvitation?
    let rawValue: String?
    let isLoading: Bool
    let errorMessage: String?
    let actionError: String?
    let isActionRunning: Bool
    let canCheckIn: Bool
    let canCheckOut: Bool
    let onCheckIn: () async -> Void
    let onCheckOut: () async -> Void
    let onScanAnother: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: 0xEAF4FF), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Visitor Invitation")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(invitation.map(statusSubtitle) ?? "Front Desk verification")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let invitation {
                    statusBadge(invitation)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)

            Divider()

            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading invitation...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Invitation Unavailable", systemImage: "qrcode")
                    } description: {
                        Text(errorMessage)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let invitation {
                    invitationDetails(invitation)
                }
            }

            actionBar
        }
        .background(Color.appSurface)
    }

    private func invitationDetails(_ invitation: FrontDeskInvitation) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Invited People (\(1 + (invitation.additionalVisitors?.count ?? 0)))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)

                    visitorCard(
                        name: invitation.visitorName ?? "Visitor",
                        company: invitation.visitorCompany,
                        phone: invitation.visitorPhone,
                        email: invitation.visitorEmail,
                        age: invitation.visitorAge,
                        isPrimary: true
                    )

                    ForEach(Array((invitation.additionalVisitors ?? []).enumerated()), id: \.offset) { _, visitor in
                        visitorCard(
                            name: visitor.name ?? "Guest",
                            company: invitation.visitorCompany,
                            phone: visitor.phone,
                            email: visitor.email,
                            age: visitor.age,
                            isPrimary: false
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Visit Information")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)

                    detailRow(icon: "person.fill", title: "Host", value: hostLabel(invitation))
                    detailRow(icon: "tag.fill", title: "Category", value: categoryLabel(invitation))
                    detailRow(icon: "calendar", title: "Expected", value: expectedWindow(invitation))
                    if let passNumber = invitation.passNumber?.nilIfBlank {
                        detailRow(icon: "number", title: "Pass Number", value: passNumber)
                    }
                    if let notes = invitation.meetingNotes?.nilIfBlank {
                        detailRow(icon: "doc.text.fill", title: "Notes", value: notes)
                    }
                }

                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0xB42318))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(hex: 0xFEF3F2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func visitorCard(
        name: String,
        company: String?,
        phone: String?,
        email: String?,
        age: Int?,
        isPrimary: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(initials(name))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 44, height: 44)
                .background(Color(hex: 0xEAF4FF), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    if isPrimary {
                        Text("Primary")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .padding(.horizontal, 6)
                            .frame(height: 19)
                            .background(Color(hex: 0xEAF4FF), in: Capsule())
                    }
                }

                if let company = company?.nilIfBlank {
                    Text(company)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                let contact = [phone?.nilIfBlank, email?.nilIfBlank, age.map { "Age \($0)" }]
                    .compactMap { $0 }
                    .joined(separator: "  •  ")
                if !contact.isEmpty {
                    Text(contact)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appSeparator, lineWidth: 1)
        }
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 30, height: 30)
                .background(Color(hex: 0xEAF4FF), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: 0x98A2B3))
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if let invitation, showsCheckOut(invitation) {
                actionButton(title: "Check Out", color: Color(hex: 0xE85D04), action: onCheckOut)
            } else if let invitation, showsCheckIn(invitation) {
                actionButton(title: "Check In", color: Color(hex: 0x16A34A), action: onCheckIn)
            }

            Button(action: onScanAnother) {
                Label("Scan Another", systemImage: "qrcode.viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(hex: 0xEAF4FF), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isActionRunning)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.appSurface)
        .overlay(alignment: .top) { Divider() }
    }

    private func actionButton(
        title: String,
        color: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                Text(title)
                    .opacity(isActionRunning ? 0 : 1)
                if isActionRunning {
                    ProgressView().tint(.white)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isActionRunning)
    }

    private func statusBadge(_ invitation: FrontDeskInvitation) -> some View {
        let checkedOut = isCheckedOut(invitation)
        let checkedIn = isCheckedIn(invitation)
        let title = checkedOut ? "Checked Out" : (checkedIn ? "Checked In" : "Invited")
        let foreground = checkedOut ? Color(hex: 0x475467) : (checkedIn ? Color(hex: 0x15803D) : Color(hex: 0x0B61CA))
        let background = checkedOut ? Color(hex: 0xF2F4F7) : (checkedIn ? Color(hex: 0xDCFCE7) : Color(hex: 0xEAF4FF))
        return Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(background, in: Capsule())
    }

    private func statusSubtitle(_ invitation: FrontDeskInvitation) -> String {
        if isCheckedOut(invitation) {
            return [timestampLabel("In", value: invitation.checkinAt), timestampLabel("Out", value: invitation.checkoutAt)]
                .compactMap { $0 }
                .joined(separator: "  •  ")
        }
        if isCheckedIn(invitation), let label = timestampLabel("Checked in", value: invitation.checkinAt) {
            return label
        }
        return "Verify visitor details"
    }

    private func showsCheckIn(_ invitation: FrontDeskInvitation) -> Bool {
        canCheckIn && !isCheckedIn(invitation) && !isCheckedOut(invitation)
    }

    private func showsCheckOut(_ invitation: FrontDeskInvitation) -> Bool {
        canCheckOut && isCheckedIn(invitation) && !isCheckedOut(invitation)
    }

    private func isCheckedIn(_ invitation: FrontDeskInvitation) -> Bool {
        invitation.checkinState?.lowercased() == "in"
            || invitation.status?.lowercased() == "checked_in"
    }

    private func isCheckedOut(_ invitation: FrontDeskInvitation) -> Bool {
        invitation.checkinState?.lowercased() == "out"
            || invitation.status?.lowercased() == "checked_out"
    }

    private func hostLabel(_ invitation: FrontDeskInvitation) -> String {
        [invitation.hostName?.nilIfBlank, invitation.hostDepartment?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: "  •  ")
            .nilIfBlank ?? "Not specified"
    }

    private func categoryLabel(_ invitation: FrontDeskInvitation) -> String {
        [invitation.categoryName?.nilIfBlank, invitation.purposeName?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: "  •  ")
            .nilIfBlank ?? "Visitor"
    }

    private func expectedWindow(_ invitation: FrontDeskInvitation) -> String {
        let time = [invitation.expectedTimeFrom?.nilIfBlank, invitation.expectedTimeTo?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " - ")
        return [invitation.expectedDate?.nilIfBlank, time.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: ", ")
            .nilIfBlank ?? "Not specified"
    }

    private func initials(_ name: String) -> String {
        let value = name.split(separator: " ").prefix(2).compactMap(\.first)
        let initials = String(value).uppercased()
        return initials.isEmpty ? "V" : initials
    }

    private func timestampLabel(_ prefix: String, value: Int64?) -> String? {
        guard let value, value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? Double(value) / 1_000 : Double(value)
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, h:mm a"
        return "\(prefix) \(formatter.string(from: Date(timeIntervalSince1970: seconds)))"
    }
}

private struct ScannerTargetView: View {
    let size: CGFloat
    let isAnimating: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.94), lineWidth: 3.5)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.black.opacity(0.08))
                .frame(width: size - 6, height: size - 6)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color(hex: 0x22C55E), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size - 48, height: 3)
                .shadow(color: Color(hex: 0x22C55E).opacity(0.95), radius: 10)
                .offset(y: isAnimating ? (size / 2 - 30) : -(size / 2 - 30))
        }
        .frame(width: size, height: size)
        .drawingGroup()
    }
}

private struct FrontDeskQRHistoryView: View {
    @State private var items = FrontDeskQRHistoryStore.load()
    @State private var showClearConfirmation = false

    var body: some View {
        ZStack {
            Color.appScreenBackground.ignoresSafeArea()

            if items.isEmpty {
                ContentUnavailableView(
                    "No Scan History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Your scanned QR codes and visitor logs will show up here.")
                )
                .foregroundStyle(.secondary)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink {
                                FrontDeskQRHistoryDetailView(item: item)
                            } label: {
                                FrontDeskQRHistoryRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle("Scan History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.appElevatedSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(Color(hex: 0xF04438))
                }
            }
        }
        .alert("Clear Scan History", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                FrontDeskQRHistoryStore.clear()
                items = []
            }
        } message: {
            Text("Are you sure you want to delete all scans?")
        }
        .onAppear {
            items = FrontDeskQRHistoryStore.load()
        }
    }
}

private struct FrontDeskQRHistoryRow: View {
    let item: FrontDeskQRHistoryItem

    private var payload: FrontDeskQRHistoryPayload {
        item.payload
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(payload.initials)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 48, height: 48)
                .background(Color(hex: 0xEAF4FF), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(payload.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let status = payload.statusLabel {
                        Text(status.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(status.foreground)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(status.background, in: Capsule())
                    }
                }

                if let details = payload.details {
                    Text(details)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let host = payload.hostLine {
                    Text(host)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                        .lineLimit(1)
                }

                Text(item.timestamp)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x98A2B3))
                .padding(.top, 17)
        }
        .padding(14)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.appSeparator, lineWidth: 1)
        }
    }
}

private struct FrontDeskQRHistoryDetailView: View {
    let item: FrontDeskQRHistoryItem

    private var payload: FrontDeskQRHistoryPayload {
        item.payload
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Text(payload.initials)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 68, height: 68)
                        .background(Color(hex: 0xEAF4FF), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(payload.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)

                        if let details = payload.details {
                            Text(details)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                detailCard(title: "Contact", rows: payload.contactRows)
                detailCard(title: "Visit", rows: payload.visitRows)

                if !payload.secondaryVisitors.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Secondary Visitors")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)

                        ForEach(payload.secondaryVisitors, id: \.self) { visitor in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(visitor.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text([visitor.phone, visitor.email, visitor.age].compactMap { $0 }.joined(separator: " • "))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.appFieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(16)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Color.appScreenBackground.ignoresSafeArea())
        .navigationTitle("Visitor Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appElevatedSurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func detailCard(title: String, rows: [FrontDeskQRDetailRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: row.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: 0xEAF4FF), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x98A2B3))
                        Text(row.value)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private enum FrontDeskQRHistoryStore {
    private static let key = "frontdesk.qr.history.items"

    static func load() -> [FrontDeskQRHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([FrontDeskQRHistoryItem].self, from: data) else {
            return []
        }
        return items
    }

    static func add(_ value: String) {
        var items = load()
        let item = FrontDeskQRHistoryItem(value: value, timestamp: displayFormatter.string(from: Date()))
        items.insert(item, at: 0)
        if items.count > 100 {
            items = Array(items.prefix(100))
        }
        save(items)
    }

    static func add(
        invitation: FrontDeskInvitation,
        status: String,
        passNumber: String?
    ) {
        var payload: [String: Any] = [
            "isStructured": true,
            "invitationId": invitation.invitationID ?? "",
            "status": status,
            "primaryName": invitation.visitorName ?? "",
            "primaryCompany": invitation.visitorCompany ?? "",
            "primaryPhone": invitation.visitorPhone ?? "",
            "primaryEmail": invitation.visitorEmail ?? "",
            "primaryAge": invitation.visitorAge.map(String.init) ?? "",
            "visitorType": invitation.categoryName ?? "",
            "purpose": invitation.purposeName ?? "",
            "hostPerson": invitation.hostName ?? "",
            "expectedTime": expectedWindow(invitation),
            "meetingNotes": invitation.meetingNotes ?? ""
        ]
        payload["secondaryList"] = (invitation.additionalVisitors ?? []).map { visitor in
            [
                "name": visitor.name ?? "",
                "phone": visitor.phone ?? "",
                "email": visitor.email ?? "",
                "age": visitor.age.map(String.init) ?? ""
            ]
        }
        if let passNumber = passNumber?.nilIfBlank {
            payload["passNumber"] = passNumber
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let value = String(data: data, encoding: .utf8) else { return }
        add(value)
    }

    static func updateStatus(invitationID: String, status: String) {
        var items = load()
        guard let index = items.firstIndex(where: { item in
            guard let data = item.value.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return payload["invitationId"] as? String == invitationID
        }) else { return }

        let item = items[index]
        guard let data = item.value.data(using: .utf8),
              var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        payload["status"] = status
        guard let updatedData = try? JSONSerialization.data(withJSONObject: payload),
              let value = String(data: updatedData, encoding: .utf8) else { return }
        items[index] = FrontDeskQRHistoryItem(id: item.id, value: value, timestamp: item.timestamp)
        save(items)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ items: [FrontDeskQRHistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func expectedWindow(_ invitation: FrontDeskInvitation) -> String {
        let time = [invitation.expectedTimeFrom?.nilIfBlank, invitation.expectedTimeTo?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " - ")
        return [invitation.expectedDate?.nilIfBlank, time.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy hh:mm a"
        return formatter
    }()
}

private struct FrontDeskQRHistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let value: String
    let timestamp: String

    init(id: UUID = UUID(), value: String, timestamp: String) {
        self.id = id
        self.value = value
        self.timestamp = timestamp
    }

    var payload: FrontDeskQRHistoryPayload {
        FrontDeskQRHistoryPayload(value: value)
    }
}

private struct FrontDeskQRHistoryPayload {
    let value: String
    private let json: [String: Any]

    init(value: String) {
        self.value = value
        if let data = value.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["isStructured"] as? Bool == true {
            json = object
        } else {
            json = [:]
        }
    }

    var isStructured: Bool {
        !json.isEmpty
    }

    var title: String {
        string("primaryName") ?? string("visitorName") ?? FrontDeskQRScannerView.inviteToken(from: value) ?? value
    }

    var details: String? {
        if isStructured {
            let company = string("primaryCompany")
            let type = string("visitorType")
            let purpose = string("purpose")
            let typePurpose = [type, purpose.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
            return [company, typePurpose.nilIfBlank].compactMap { $0 }.joined(separator: " • ").nilIfBlank
        }
        return FrontDeskQRScannerView.inviteToken(from: value).map { "Invite token: \($0)" }
    }

    var hostLine: String? {
        guard let host = string("hostPerson") else { return nil }
        return "Host: \(host)"
    }

    var initials: String {
        let words = title
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let text = String(words).uppercased()
        return text.isEmpty ? "#" : text
    }

    var statusLabel: FrontDeskQRStatusLabel? {
        switch string("status") {
        case "checked_out":
            return FrontDeskQRStatusLabel(title: "Checked Out", foreground: Color(hex: 0x475467), background: Color(hex: 0xF2F4F7))
        case "checked_in":
            return FrontDeskQRStatusLabel(title: "Checked In", foreground: Color(hex: 0x15803D), background: Color(hex: 0xDCFCE7))
        default:
            return nil
        }
    }

    var contactRows: [FrontDeskQRDetailRow] {
        [
            detail("Phone", value: string("primaryPhone"), icon: "phone.fill"),
            detail("Email", value: string("primaryEmail"), icon: "envelope.fill"),
            detail("Age", value: string("primaryAge").map { "Age: \($0)" }, icon: "calendar")
        ].compactMap { $0 }
    }

    var visitRows: [FrontDeskQRDetailRow] {
        [
            detail("Category", value: [string("visitorType"), string("purpose")].compactMap { $0 }.joined(separator: " • ").nilIfBlank, icon: "tag.fill"),
            detail("Host", value: string("hostPerson"), icon: "person.fill"),
            detail("Expected Time", value: string("expectedTime"), icon: "clock.fill"),
            detail("Pass Number", value: string("passNumber"), icon: "number"),
            detail("Notes", value: string("meetingNotes"), icon: "doc.text.fill")
        ].compactMap { $0 }
    }

    var secondaryVisitors: [FrontDeskQRSecondaryVisitor] {
        guard let array = json["secondaryList"] as? [[String: Any]] else { return [] }
        return array.compactMap { object in
            let name = (object["name"] as? String)?.nilIfBlank
            guard let name else { return nil }
            return FrontDeskQRSecondaryVisitor(
                name: name,
                phone: (object["phone"] as? String)?.nilIfBlank,
                email: (object["email"] as? String)?.nilIfBlank,
                age: (object["age"] as? String)?.nilIfBlank.map { "Age: \($0)" }
            )
        }
    }

    private func string(_ key: String) -> String? {
        (json[key] as? String)?.nilIfBlank
    }

    private func detail(_ label: String, value: String?, icon: String) -> FrontDeskQRDetailRow? {
        guard let value else { return nil }
        return FrontDeskQRDetailRow(label: label, value: value, icon: icon)
    }
}

private struct FrontDeskQRStatusLabel {
    let title: String
    let foreground: Color
    let background: Color
}

private struct FrontDeskQRDetailRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
}

private struct FrontDeskQRSecondaryVisitor: Hashable {
    let name: String
    let phone: String?
    let email: String?
    let age: String?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct QRScannerCameraView: UIViewControllerRepresentable {
    @Binding var scannedValue: String?
    @Binding var cameraAccessDenied: Bool

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScan = { value in
            scannedValue = value
        }
        controller.onDenied = {
            cameraAccessDenied = true
        }
        return controller
    }

    func updateUIViewController(_ controller: QRScannerViewController, context: Context) {
        controller.isPaused = scannedValue != nil
    }
}

private final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onDenied: (() -> Void)?
    var isPaused = false {
        didSet {
            updateSessionRunningState()
        }
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(
        label: "com.manju.chat.frontdesk.camera",
        qos: .userInitiated
    )
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateSessionRunningState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.startSession() : self?.onDenied?()
                }
            }
        default:
            onDenied?()
        }
    }

    private func startSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onDenied?()
            return
        }

        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        updateSessionRunningState()
    }

    private func updateSessionRunningState() {
        let shouldRun = isViewLoaded && view.window != nil && !isPaused && previewLayer != nil
        sessionQueue.async { [session] in
            if shouldRun, !session.isRunning {
                session.startRunning()
            } else if !shouldRun, session.isRunning {
                session.stopRunning()
            }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isPaused,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        isPaused = true
        onScan?(value)
    }
}

#Preview {
    FrontDeskQRScannerView()
}
