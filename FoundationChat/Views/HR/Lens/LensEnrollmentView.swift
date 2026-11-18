import SwiftUI
import UIKit

/// Apps → HR → Lens Enrollment. Super admins and `lens.enroll` only (the
/// server enforces the same rule). Pick a staff member, record the guided
/// head turn, review the auto-captured photos and upload them.
struct LensEnrollmentView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var items: [LensStaff] = []
    @State private var nextCursor: String?
    @State private var search = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var selected: LensStaff?
    @State private var pendingChoice: LensStaff?
    @State private var sendingId: String?

    var body: some View {
        List {
            if !hasLoaded && isLoading {
                ForEach(0..<8, id: \.self) { _ in LensStaffSkeletonRow() }
                    .listRowBackground(Color.appSurface)
            } else if items.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(items) { staff in
                    Button {
                        guard staff.canEnroll else { return }
                        // Photos already saved and waiting: offer to send them instead of recording again.
                        if staff.waitingPhotos > 0 { pendingChoice = staff } else { selected = staff }
                    } label: {
                        LensStaffRow(staff: staff, isSending: sendingId == staff.id)
                    }
                    .buttonStyle(.plain)
                    .disabled(!staff.canEnroll || sendingId != nil)
                    .listRowBackground(Color.appSurface)
                    .onAppear {
                        if staff.id == items.last?.id { Task { await loadMore() } }
                    }
                }
                if isLoadingMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appScreenBackground)
        .navigationTitle("Lens Enrollment")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, employee code or phone")
        .refreshable { await reload() }
        .task(id: search) {
            if hasLoaded { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .floaterAlert($errorMessage)
        .confirmationDialog(
            "Photos waiting for Lens",
            isPresented: Binding(get: { pendingChoice != nil }, set: { if !$0 { pendingChoice = nil } }),
            titleVisibility: .visible,
            presenting: pendingChoice
        ) { staff in
            Button("Send to Lens") { Task { await sendPending(staff) } }
            Button("Record again") { selected = staff }
            Button("Cancel", role: .cancel) {}
        } message: { staff in
            Text("\(staff.waitingPhotos) photos of \(staff.displayName) are saved on the profile and waiting for Lens.")
        }
        .fullScreenCover(item: $selected) { staff in
            LensEnrollmentFlowView(staff: staff) {
                Task { await reload() }
            }
            .environment(authStore)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color.appTertiaryText)
            Text(search.isEmpty ? "No staff to show" : "No staff match \"\(search)\"")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.appSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func reload() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            let page = try await LensEnrollmentAPIService.staff(token: token, search: search, cursor: nil)
            items = page.items
            nextCursor = page.nextCursor
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendPending(_ staff: LensStaff) async {
        guard sendingId == nil, let token = authStore.currentSession?.token else { return }
        sendingId = staff.id
        Floater.shared.info("Sending the photos to Lens…")
        do {
            let result = try await LensEnrollmentAPIService.sendPending(token: token, staffId: staff.staffId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Floater.shared.success("Sent to Lens: \(result.addedSamples) added, \(result.faceSamples ?? result.addedSamples) photos for the cameras.")
        } catch is CancellationError {
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            Floater.shared.warning(error.localizedDescription)
        }
        sendingId = nil
        await reload()
    }

    private func loadMore() async {
        guard !isLoadingMore, !isLoading, let cursor = nextCursor,
              let token = authStore.currentSession?.token else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await LensEnrollmentAPIService.staff(token: token, search: search, cursor: cursor)
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LensStaffRow: View {
    let staff: LensStaff
    var isSending = false

    var body: some View {
        HStack(spacing: 12) {
            ConversationAvatarView(initials: staff.initials, source: staff.photoUrl, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(staff.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appPrimaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(staff.canEnroll ? Color.appSecondaryText : Color(hex: 0xDC2626))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            badge
        }
        .padding(.vertical, 4)
        .opacity(staff.canEnroll ? 1 : 0.55)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard let code = staff.code else { return "No employee code — can't enroll" }
        return [code, staff.department].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    @ViewBuilder
    private var badge: some View {
        if isSending {
            ProgressView()
        } else if staff.isEnrolled {
            Label("\(staff.enrollment?.faceSamples ?? 0)", systemImage: "faceid")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x15803D))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.adaptiveTint(0xDCFCE7), in: Capsule())
                .accessibilityLabel("Enrolled, \(staff.enrollment?.faceSamples ?? 0) photos")
        } else if staff.canEnroll && staff.waitingPhotos > 0 {
            // Saved while Lens was down / not configured: not lost, waiting.
            Text("Saved · waiting for Lens")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0xB45309))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.adaptiveTint(0xFEF3C7), in: Capsule())
        } else if staff.canEnroll {
            Text("Not enrolled")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appSecondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.appFieldBackground, in: Capsule())
        }
    }
}

private struct LensStaffSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.adaptiveTint(0xE9EEF8)).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color.adaptiveTint(0xE9EEF8)).frame(width: 150, height: 14)
                RoundedRectangle(cornerRadius: 4).fill(Color.adaptiveTint(0xEEF2F8)).frame(width: 110, height: 11)
            }
            Spacer()
            Capsule().fill(Color.adaptiveTint(0xEEF2F8)).frame(width: 70, height: 22)
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Record → review → upload → result

struct LensEnrollmentFlowView: View {
    let staff: LensStaff
    let onFinished: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case capture([LensPose])
        case review
        case uploading
        case result(LensEnrollResult)
        case saved
        case failure(String)
    }

    @State private var phase: Phase = .capture(LensPose.guidedOrder)
    @State private var shots: [LensPose: LensShot] = [:]
    @State private var replace = false
    @State private var lastError: LensEnrollError?
    @State private var didEnroll = false

    var body: some View {
        Group {
            switch phase {
            case .capture(let targets):
                LensCaptureView(
                    staffName: staff.displayName,
                    targets: targets,
                    onDone: { captured in
                        if targets.count == LensPose.guidedOrder.count {
                            shots = captured
                        } else {
                            for (pose, shot) in captured { shots[pose] = shot }
                        }
                        phase = .review
                    },
                    onCancel: {
                        // Cancelling a retake goes back to review; cancelling
                        // the first recording closes the flow.
                        if shots.isEmpty { close() } else { phase = .review }
                    }
                )
            case .review, .uploading:
                NavigationStack { reviewScreen }
            case .result(let result):
                NavigationStack { resultScreen(result) }
            case .saved:
                NavigationStack { savedScreen }
            case .failure(let message):
                NavigationStack { failureScreen(message) }
            }
        }
        .interactiveDismissDisabled(phase == .uploading)
    }

    private func close() {
        if didEnroll { onFinished() }
        dismiss()
    }

    // MARK: Review

    private var requiredMissing: [LensPose] {
        LensPose.guidedOrder.filter { $0.isRequired && shots[$0] == nil }
    }

    private var reviewScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                staffHeader

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(LensPose.guidedOrder) { pose in
                        LensShotCard(pose: pose, shot: shots[pose], disabled: phase == .uploading) {
                            phase = .capture([pose])
                        }
                    }
                }

                if staff.isEnrolled {
                    Toggle(isOn: $replace) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Replace earlier photos")
                                .font(.system(size: 15, weight: .semibold))
                            Text("\(staff.enrollment?.faceSamples ?? 0) photos are already enrolled")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                    .tint(Color(hex: 0x0B61CA))
                    .padding(14)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(phase == .uploading)
                }

                if !requiredMissing.isEmpty {
                    Label("Retake \(requiredMissing.map { $0.title.lowercased() }.joined(separator: ", ")) to continue", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xB45309))
                }
            }
            .padding(16)
        }
        .background(Color.appScreenBackground)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    Task { await upload() }
                } label: {
                    if phase == .uploading {
                        HStack(spacing: 8) { ProgressView().tint(.white); Text("Enrolling…") }
                    } else {
                        Text("Enroll \(shots.count) photos")
                    }
                }
                .buttonStyle(.mconnect(.primary))
                .disabled(!requiredMissing.isEmpty || phase == .uploading)

                Button("Record again") {
                    shots = [:]
                    phase = .capture(LensPose.guidedOrder)
                }
                .buttonStyle(.mconnect(.secondary))
                .disabled(phase == .uploading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .navigationTitle("Review photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { close() }.disabled(phase == .uploading)
            }
        }
    }

    private var staffHeader: some View {
        HStack(spacing: 12) {
            ConversationAvatarView(initials: staff.initials, source: staff.photoUrl, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(staff.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appPrimaryText)
                Text([staff.code, staff.department].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appSecondaryText)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func upload() async {
        guard let token = authStore.currentSession?.token else { return }
        let photos = LensPose.guidedOrder.compactMap { pose in
            shots[pose].map { LensPhotoUpload(pose: pose.rawValue, jpeg: $0.jpeg) }
        }
        phase = .uploading
        do {
            let result = try await LensEnrollmentAPIService.enroll(
                token: token, staffId: staff.staffId, replace: replace, photos: photos
            )
            didEnroll = result.addedSamples > 0
            UINotificationFeedbackGenerator().notificationOccurred(result.mustRetake ? .warning : .success)
            phase = .result(result)
        } catch let error as LensEnrollError where error.savedForLater {
            // Lens is down / not configured but the photos are on the profile.
            lastError = error
            didEnroll = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            phase = .saved
        } catch let error as LensEnrollError {
            lastError = error
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            phase = .failure(error.localizedDescription)
        } catch {
            lastError = nil
            phase = .failure(error.localizedDescription)
        }
    }

    // MARK: Result

    private func resultScreen(_ result: LensEnrollResult) -> some View {
        let ok = !result.mustRetake
        return ScrollView {
            VStack(spacing: 18) {
                Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(ok ? Color(hex: 0x16A34A) : Color(hex: 0xD97706))
                    .symbolEffect(.bounce, value: ok)
                    .padding(.top, 24)
                Text(ok ? "\(staff.displayName) is enrolled" : "Only \(result.addedSamples) of \(shots.count) photos were saved")
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(ok
                     ? "\(result.addedSamples) photos added · \(result.faceSamples ?? result.addedSamples) on file"
                     : "Record again so the cameras have at least 3 good photos.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)

                failedList(result.failed ?? [])
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appScreenBackground)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if !ok {
                    Button("Record again") {
                        shots = [:]
                        replace = false
                        phase = .capture(LensPose.guidedOrder)
                    }
                    .buttonStyle(.mconnect(.primary))
                }
                Button("Done") { close() }
                    .buttonStyle(.mconnect(ok ? .primary : .secondary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .navigationTitle("Enrollment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var savedScreen: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xD97706))
                    .padding(.top, 24)
                Text("Photos saved")
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Photos saved on \(staff.displayName)'s profile. Waiting for Lens.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appScreenBackground)
        .safeAreaInset(edge: .bottom) {
            Button("Done") { close() }
                .buttonStyle(.mconnect(.primary))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .navigationTitle("Enrollment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func failureScreen(_ message: String) -> some View {
        let error = lastError
        let isAdminIssue = error?.code == "FACE_MATCHES_ANOTHER_PERSON" || error?.code == "FACE_DOES_NOT_MATCH_EXISTING_ENROLLMENT"
        return ScrollView {
            VStack(spacing: 18) {
                Image(systemName: isAdminIssue ? "person.crop.circle.badge.exclamationmark" : "xmark.octagon.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xDC2626))
                    .padding(.top, 24)
                Text(message)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                failedList(error?.failed ?? [])
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appScreenBackground)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if error?.code == "FACE_DOES_NOT_MATCH_EXISTING_ENROLLMENT" && !replace {
                    Button("Re-enroll with Replace") {
                        replace = true
                        Task { await upload() }
                    }
                    .buttonStyle(.mconnect(.danger))
                }
                if error?.asksForRetake == true {
                    Button("Record again") {
                        shots = [:]
                        phase = .capture(LensPose.guidedOrder)
                    }
                    .buttonStyle(.mconnect(.primary))
                } else if error?.isRetryable == true || error == nil {
                    Button("Try again") { Task { await upload() } }
                        .buttonStyle(.mconnect(.primary))
                }
                Button("Close") { close() }
                    .buttonStyle(.mconnect(.secondary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .navigationTitle("Enrollment")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func failedList(_ failed: [LensFailedPhoto]) -> some View {
        if !failed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Photos not saved")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appSecondaryText)
                ForEach(failed) { item in
                    HStack(alignment: .top, spacing: 10) {
                        if let pose = item.pose.flatMap(LensPose.init(rawValue:)),
                           let data = shots[pose]?.jpeg, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.pose.flatMap(LensPose.init(rawValue:))?.title ?? "Photo")
                                .font(.system(size: 14, weight: .semibold))
                            Text(LensMessages.photoReason(item))
                                .font(.system(size: 13))
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct LensShotCard: View {
    let pose: LensPose
    let shot: LensShot?
    let disabled: Bool
    let onRetake: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appFieldBackground)
                if let shot, let image = UIImage(data: shot.jpeg) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.square.badge.camera")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.appTertiaryText)
                        Text(pose.isRequired ? "Required" : "Optional")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(pose.isRequired ? Color(hex: 0xB45309) : Color.appTertiaryText)
                    }
                }
            }
            .frame(height: 170)
            .clipped()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pose.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.appPrimaryText)
                    if let shot {
                        Label(shot.quality >= 0.6 ? "Good" : "OK", systemImage: shot.quality >= 0.6 ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(shot.quality >= 0.6 ? Color(hex: 0x16A34A) : Color(hex: 0xCA8A04))
                    }
                }
                Spacer()
                Button(shot == nil ? "Capture" : "Retake", action: onRetake)
                    .buttonStyle(.mconnect(.secondary, compact: true))
                    .disabled(disabled)
            }
        }
        .padding(10)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
