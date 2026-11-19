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
    @State private var savedPhotosOf: LensStaff?

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
                        // Saved photos: Send to Lens, retake one or all, delete.
                        if (staff.savedPhotos ?? 0) > 0 { savedPhotosOf = staff } else { selected = staff }
                    } label: {
                        LensStaffRow(staff: staff)
                    }
                    .buttonStyle(.plain)
                    .disabled(!staff.canEnroll)
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
        .fullScreenCover(item: $savedPhotosOf) { staff in
            NavigationStack {
                LensCapturesView(staff: staff) { Task { await reload() } }
            }
            .environment(authStore)
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
        if staff.isEnrolled {
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
    /// Retake of one saved photo: the camera asks for just this pose.
    let single: LensPose?
    /// "Retake all": starts with Replace earlier photos on.
    let startReplace: Bool
    let onFinished: () -> Void

    init(staff: LensStaff, single: LensPose? = nil, startReplace: Bool = false, onFinished: @escaping () -> Void) {
        self.staff = staff
        self.single = single
        self.startReplace = startReplace
        self.onFinished = onFinished
        _phase = State(initialValue: .capture(single.map { [$0] } ?? LensPose.guidedOrder))
        _replace = State(initialValue: startReplace && single == nil)
    }

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case capture([LensPose])
        case review
        case uploading
        case result(LensEnrollResult)
        case retaken(LensEnrollResult)
        case saved
        case failure(String)
    }

    @State private var phase: Phase
    @State private var shots: [LensPose: LensShot] = [:]
    @State private var replace: Bool
    @State private var lastError: LensEnrollError?
    @State private var didEnroll = false

    var body: some View {
        Group {
            switch phase {
            case .capture(let targets):
                LensCaptureView(
                    staffName: staff.displayName,
                    targets: targets,
                    allowSkip: single == nil,
                    onDone: { captured in
                        if single == nil && targets.count == LensPose.guidedOrder.count {
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
            case .retaken(let result):
                NavigationStack { retakenScreen(result) }
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
        if let single { return shots[single] == nil ? [single] : [] }
        return LensPose.guidedOrder.filter { $0.isRequired && shots[$0] == nil }
    }

    /// Poses on the review screen: all of them, or the one being retaken.
    private var reviewPoses: [LensPose] { single.map { [$0] } ?? LensPose.guidedOrder }

    private var allTargets: [LensPose] { single.map { [$0] } ?? LensPose.guidedOrder }

    private var reviewScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                staffHeader

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(reviewPoses) { pose in
                        LensShotCard(pose: pose, shot: shots[pose], disabled: phase == .uploading) {
                            phase = .capture([pose])
                        }
                    }
                }

                if single == nil && (staff.isEnrolled || startReplace) {
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
                    } else if single != nil {
                        Text("Save photo")
                    } else {
                        Text("Enroll \(shots.count) photos")
                    }
                }
                .buttonStyle(.mconnect(.primary))
                .disabled(!requiredMissing.isEmpty || phase == .uploading)

                Button("Record again") {
                    shots = [:]
                    phase = .capture(allTargets)
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
        if single != nil, let photo = photos.first {
            do {
                let result = try await LensEnrollmentAPIService.retake(token: token, staffId: staff.staffId, photo: photo)
                didEnroll = true
                UINotificationFeedbackGenerator().notificationOccurred(result.isWaitingForLens ? .warning : .success)
                phase = .retaken(result)
            } catch let error as LensEnrollError {
                lastError = error
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                phase = .failure(error.localizedDescription)
            } catch {
                lastError = nil
                phase = .failure(error.localizedDescription)
            }
            return
        }
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
                        phase = .capture(allTargets)
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

    private func retakenScreen(_ result: LensEnrollResult) -> some View {
        let waiting = result.isWaitingForLens
        let poseName = (single?.title ?? "new").lowercased()
        return ScrollView {
            VStack(spacing: 18) {
                Image(systemName: waiting ? "tray.and.arrow.down.fill" : "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(waiting ? Color(hex: 0xD97706) : Color(hex: 0x16A34A))
                    .padding(.top, 24)
                Text(waiting ? "Photo saved" : "Photo replaced")
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(result.message ?? (waiting
                    ? "The new \(poseName) photo is saved on the profile. Waiting for Lens."
                    : "The new \(poseName) photo is added to Lens."))
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
        .navigationTitle("Retake")
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
                        phase = .capture(allTargets)
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

// MARK: - Saved photos (Send to Lens, retake, delete)

/// A staff member's saved Lens photos. Per pose: retake (the camera asks for
/// just that pose) or delete; plus Send to Lens, Retake all and Delete all.
/// Delete removes our stored photo only; it never calls Lens.
struct LensCapturesView: View {
    let staff: LensStaff
    let onChanged: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var captures: [LensCapture] = []
    @State private var enrollment: LensStaffEnrollment?
    @State private var loaded = false
    @State private var busy: String?
    @State private var errorMessage: String?
    @State private var retakePose: LensPose?
    @State private var retakeAll = false
    @State private var confirmDelete: DeleteTarget?

    private struct DeleteTarget: Identifiable {
        let captureId: String?
        let pose: LensPose?
        var id: String { captureId ?? "all" }
    }

    private var waiting: Int { captures.filter { !$0.inLens }.count }

    private func photo(for pose: LensPose) -> LensCapture? {
        captures.first { $0.pose == pose.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(statusLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(waiting > 0 ? Color(hex: 0xB45309) : Color.appSecondaryText)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(LensPose.guidedOrder) { pose in
                        card(pose)
                    }
                }
                Text("Delete removes the photo from the staff profile only. Lens keeps what it already has, so the cameras still recognise this person.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appTertiaryText)
            }
            .padding(16)
            .redacted(reason: loaded ? [] : .placeholder)
        }
        .background(Color.appScreenBackground)
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle(staff.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }.disabled(busy != nil)
            }
        }
        .task { await load() }
        .floaterAlert($errorMessage)
        // Shared Mconnect confirm sheet (never the stock alert).
        .mconnectConfirm(
            item: $confirmDelete,
            title: { $0.captureId == nil ? "Delete all photos?" : "Delete this photo?" },
            message: { target in
                if let pose = target.pose {
                    return "The \(pose.title.lowercased()) photo is removed from \(staff.displayName)'s profile. Lens keeps what it already has."
                }
                return "All \(captures.count) saved photos of \(staff.displayName) are removed from the profile. Lens keeps what it already has."
            },
            confirmLabel: "Delete",
            destructive: true,
            systemImage: "trash"
        ) { target in
            Task { await delete(target.captureId) }
        }
        .fullScreenCover(item: $retakePose) { pose in
            LensEnrollmentFlowView(staff: staff, single: pose) { changed() }
                .environment(authStore)
        }
        .fullScreenCover(isPresented: $retakeAll) {
            LensEnrollmentFlowView(staff: staff, startReplace: true) { changed() }
                .environment(authStore)
        }
    }

    private var statusLine: String {
        let samples = enrollment?.faceSamples ?? 0
        if waiting > 0 { return "\(waiting) photos waiting for Lens" }
        if samples > 0 { return "In Lens: \(samples) photos for the cameras" }
        if captures.isEmpty && loaded { return "No saved photos. Record the head turn to enroll." }
        return "In Lens: \(captures.count) photos for the cameras"
    }

    private func card(_ pose: LensPose) -> some View {
        let shot = photo(for: pose)
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.appFieldBackground)
                if let url = shot?.url.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text("No photo")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
            .frame(height: 170)
            .clipped()
            Text(pose.isRequired ? pose.title : "\(pose.title) · Optional")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appPrimaryText)
            Text(shot == nil ? "No photo" : (shot!.inLens ? "In Lens" : "Waiting for Lens"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(shot == nil ? Color.appTertiaryText : (shot!.inLens ? Color(hex: 0x16A34A) : Color(hex: 0xB45309)))
            Button(shot == nil ? "Capture" : "Retake") { retakePose = pose }
                .buttonStyle(.mconnect(.secondary, compact: true))
                .disabled(busy != nil || !loaded)
            if let shot {
                Button(busy == shot.captureId ? "Deleting…" : "Delete") {
                    confirmDelete = DeleteTarget(captureId: shot.captureId, pose: pose)
                }
                .buttonStyle(.mconnect(.danger, compact: true))
                .disabled(busy != nil)
            }
        }
        .padding(10)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if waiting > 0 {
                Button {
                    Task { await sendPending() }
                } label: {
                    if busy == "send" {
                        HStack(spacing: 8) { ProgressView().tint(.white); Text("Sending to Lens…") }
                    } else {
                        Text("Send to Lens (\(waiting))")
                    }
                }
                .buttonStyle(.mconnect(.primary))
                .disabled(busy != nil)
            }
            HStack(spacing: 10) {
                Button("Retake all") { retakeAll = true }
                    .buttonStyle(.mconnect(.secondary))
                    .disabled(busy != nil || !loaded)
                if !captures.isEmpty {
                    Button(busy == "all" ? "Deleting…" : "Delete all") {
                        confirmDelete = DeleteTarget(captureId: nil, pose: nil)
                    }
                    .buttonStyle(.mconnect(.danger))
                    .disabled(busy != nil)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func changed() {
        onChanged()
        Task { await load() }
    }

    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        do {
            let page = try await LensEnrollmentAPIService.captures(token: token, staffId: staff.staffId)
            captures = page.captures ?? []
            enrollment = page.enrollment
            loaded = true
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            loaded = true
            errorMessage = error.localizedDescription
        }
    }

    private func sendPending() async {
        guard busy == nil, let token = authStore.currentSession?.token else { return }
        busy = "send"
        do {
            let result = try await LensEnrollmentAPIService.sendPending(token: token, staffId: staff.staffId)
            let notUsed = result.failed?.count ?? 0
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Floater.shared.success("Sent to Lens: \(result.addedSamples) added, \(result.faceSamples ?? result.addedSamples) photos for the cameras." + (notUsed > 0 ? " \(notUsed) not used." : ""))
            onChanged()
        } catch is CancellationError {
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            Floater.shared.warning(error.localizedDescription)
        }
        busy = nil
        await load()
    }

    private func delete(_ captureId: String?) async {
        guard busy == nil, let token = authStore.currentSession?.token else { return }
        busy = captureId ?? "all"
        do {
            let n = try await LensEnrollmentAPIService.deleteCaptures(token: token, staffId: staff.staffId, captureId: captureId)
            Floater.shared.success(n == 1 ? "Photo deleted." : "\(n) photos deleted.")
            onChanged()
        } catch is CancellationError {
        } catch {
            Floater.shared.warning(error.localizedDescription)
        }
        busy = nil
        await load()
    }
}
