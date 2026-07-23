import AVFoundation
import SwiftUI

struct IssuesView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var issues: [ProjectIssue] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var audioPlayer: AVPlayer?
    @State private var playingIssueId: String?
    @State private var showCreateIssue = false

    private var filteredIssues: [ProjectIssue] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return issues }
        return issues.filter { issue in
            (issue.title ?? "").lowercased().contains(query)
            || (issue.description ?? "").lowercased().contains(query)
            || (issue.projectId ?? "").lowercased().contains(query)
            || (issue.status ?? "").lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isLoading && issues.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                IssueCardSkeleton()
                            }
                        }
                        .padding(.top, 16)
                    }
                } else if filteredIssues.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredIssues) { issue in
                                IssueCard(
                                    issue: issue,
                                    isPlaying: playingIssueId == issue.id,
                                    onPlay: { toggleAudio(for: issue) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                    .refreshable {
                        await loadIssues()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white)
        .navigationTitle("Issues")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Issues"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateIssue = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Create Issue")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task {
            await loadIssues()
        }
        .alert("Issues", isPresented: errorAlertBinding, actions: {
            Button("OK", role: .cancel) { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .onDisappear {
            audioPlayer?.pause()
            audioPlayer = nil
        }
        .sheet(isPresented: $showCreateIssue) {
            CreateIssueSheet {
                await loadIssues()
            }
            .appFormActivity()
            .appLibraryNativeSheet([.height(620), .large])
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("HomeEmptyTrips")
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 150)
                .opacity(0.7)

            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No Issues Yet" : "No Issues Found")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: 0x0F172A))

            Text("Stay organized by creating or joining teams. Groups help you manage tasks, track progress, and collaborate with your team in one place.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: 0x64748B))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadIssues() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Please login again."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            issues = try await IssuesAPIService.listMyIssues(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleAudio(for issue: ProjectIssue) {
        guard let rawURL = issue.audioUrl?.nonBlank,
              let url = URL(string: rawURL)
        else { return }

        if playingIssueId == issue.id {
            audioPlayer?.pause()
            audioPlayer = nil
            playingIssueId = nil
            return
        }

        audioPlayer?.pause()
        audioPlayer = AVPlayer(url: url)
        audioPlayer?.play()
        playingIssueId = issue.id
    }
}

private struct IssueCard: View {
    let issue: ProjectIssue
    let isPlaying: Bool
    let onPlay: () -> Void

    private var title: String {
        issue.title?.nonBlank ?? "Issue"
    }

    private var description: String? {
        issue.description?.nonBlank
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x16A34A))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: 0xDCFCE7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .lineLimit(1)

                    Text(issue.projectId?.nonBlank ?? "Reported by me")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x64748B))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                IssueStatusBadge(status: issue.status)
            }

            Divider()
                .background(Color(hex: 0xF1F5F9))

            if let description {
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: 0x475467))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x64748B))

                Text(displayTime(issue.createdAt))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: 0x64748B))

                Spacer()

                if issue.audioUrl?.nonBlank != nil {
                    Button(action: onPlay) {
                        HStack(spacing: 8) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(audioDuration(issue.audioDurationMs))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color(hex: 0xEFF8FF), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xE2E8F0), lineWidth: 1)
        )
    }

    private func displayTime(_ raw: Double?) -> String {
        guard let raw else { return "Today" }
        let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'Today,' hh:mm a" : "dd MMM yyyy, hh:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func audioDuration(_ raw: Double?) -> String {
        let totalSeconds = Int((raw ?? 0) / 1000)
        guard totalSeconds > 0 else { return "Audio" }
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct CreateIssueSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let onCreated: () async -> Void

    @State private var projects: [ProjectSummary] = []
    @State private var selectedProject: ProjectSummary?
    @State private var showProjectPicker = false
    @State private var title = ""
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var isLoadingProjects = false
    @State private var errorMessage: String?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var previewPlayer: AVAudioPlayer?
    @State private var recordedAudioURL: URL?
    @State private var recordedAudioData: Data?
    @State private var isRecording = false
    @State private var isPlayingPreview = false
    @State private var recordingElapsedSeconds = 0
    @State private var audioDurationSeconds = 0
    @State private var recordingTimer: Timer?

    private var canSubmit: Bool {
        selectedProject != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("New Issue")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    issuePickerField(
                        title: "Project *",
                        value: selectedProject?.displayName ?? (isLoadingProjects ? "Loading projects..." : "Select project"),
                        isPlaceholder: selectedProject == nil,
                        action: {
                            if projects.isEmpty {
                                Task { await loadProjects() }
                            } else {
                                showProjectPicker = true
                            }
                        }
                    )

                    issueTextField(title: "Issue Title *", text: $title, placeholder: "Enter issue title")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x334155))
                        TextEditor(text: $description)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color(hex: 0x0F172A))
                            .frame(minHeight: 100)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE2E8F0), lineWidth: 1))
                    }

                    voiceNoteSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xDC2626))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            VStack(spacing: 0) {
                Divider()
                    .overlay(Color(hex: 0xEAECF0))

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isSubmitting ? "Submitting..." : "Submit Issue")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: canSubmit ? [Color(hex: 0x1BCB0B), Color(hex: 0x3DA302)] : [Color(hex: 0xD0D5DD), Color(hex: 0xD0D5DD)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .background(Color.white)
        }
        .background(Color.white)
        .appCompactSheetCTAContainer()
        .task {
            await loadProjects()
        }
        .sheet(isPresented: $showProjectPicker) {
            NativeSearchableSelectionSheet(
                title: "Select Project",
                prompt: "Search projects",
                items: projects,
                selectedId: selectedProject?.id,
                searchText: { project in
                    [project.displayName, project.status ?? ""].joined(separator: " ")
                },
                rowContent: { project, isSelected in
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? Color(hex: 0x0B61CA) : Color(hex: 0x64748B))
                            .frame(width: 34, height: 34)
                            .background((isSelected ? Color(hex: 0xEAF3FF) : Color(hex: 0xF1F5F9)), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x0F172A))
                            if let status = project.status?.nonBlank {
                                Text(status.capitalized)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(Color(hex: 0x64748B))
                            }
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(hex: 0x0B61CA))
                        }
                    }
                    .padding(.vertical, 4)
                },
                onSelect: { project in
                    selectedProject = project
                }
            )
        }
        .onDisappear {
            stopRecording()
            stopPreview()
        }
    }

    private func issueTextField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x334155))
                TextField(placeholder, text: text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE2E8F0), lineWidth: 1))
        }
    }

    private func issuePickerField(title: String, value: String, isPlaceholder: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x334155))
            Button(action: action) {
                HStack(spacing: 10) {
                    Text(value)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isPlaceholder ? Color(hex: 0x94A3B8) : Color(hex: 0x0F172A))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x64748B))
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE2E8F0), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingProjects)
        }
    }

    private var voiceNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice Note")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x334155))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(audioStatusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(audioStatusColor)
                    if isRecording {
                        Text(formatDuration(recordingElapsedSeconds))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                    }
                }

                Spacer(minLength: 12)

                if recordedAudioURL != nil && !isRecording {
                    Button(action: togglePreview) {
                        Image(systemName: isPlayingPreview ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                            .frame(width: 32, height: 32)
                            .background(Color(hex: 0xEFF8FF), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: deleteRecording) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xEF4444))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: toggleRecording) {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(isRecording ? Color(hex: 0xEF4444) : Color(hex: 0x0B61CA), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE2E8F0), lineWidth: 1))
        }
    }

    private var audioStatusText: String {
        if isRecording { return "Recording voice note..." }
        if recordedAudioURL != nil { return isPlayingPreview ? "Playing voice note..." : "Voice note attached" }
        return "Tap microphone to record voice note"
    }

    private var audioStatusColor: Color {
        if isRecording { return Color(hex: 0xEF4444) }
        if recordedAudioURL != nil { return Color(hex: 0x16A34A) }
        return Color(hex: 0x64748B)
    }

    @MainActor
    private func loadProjects() async {
        guard projects.isEmpty, let token = authStore.currentSession?.token else { return }
        isLoadingProjects = true
        defer { isLoadingProjects = false }
        do {
            let loaded = try await ProjectConvexAPIService.getMyProjects(token: token)
            projects = loaded.filter { ($0.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ongoing" }
            if projects.isEmpty {
                projects = loaded
            }
            if selectedProject == nil {
                selectedProject = projects.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }
        startRecording()
    }

    private func startRecording() {
        stopPreview()
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    errorMessage = "Permission to record audio is required."
                    return
                }
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)

                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("issue_voice_\(Int(Date().timeIntervalSince1970)).m4a")
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44_100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                    ]
                    let recorder = try AVAudioRecorder(url: url, settings: settings)
                    recorder.record()
                    audioRecorder = recorder
                    recordedAudioURL = url
                    recordedAudioData = nil
                    audioDurationSeconds = 0
                    recordingElapsedSeconds = 0
                    isRecording = true
                    recordingTimer?.invalidate()
                    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                        recordingElapsedSeconds += 1
                    }
                } catch {
                    errorMessage = "Failed to start audio recording."
                }
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        audioRecorder?.stop()
        audioRecorder = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        audioDurationSeconds = max(recordingElapsedSeconds, 1)
        if let recordedAudioURL {
            recordedAudioData = try? Data(contentsOf: recordedAudioURL)
        }
    }

    private func togglePreview() {
        if isPlayingPreview {
            stopPreview()
            return
        }
        guard let recordedAudioURL else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: recordedAudioURL)
            player.prepareToPlay()
            player.play()
            previewPlayer = player
            isPlayingPreview = true
        } catch {
            errorMessage = "Failed to play audio preview."
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        isPlayingPreview = false
    }

    private func deleteRecording() {
        stopPreview()
        stopRecording()
        if let recordedAudioURL {
            try? FileManager.default.removeItem(at: recordedAudioURL)
        }
        recordedAudioURL = nil
        recordedAudioData = nil
        audioDurationSeconds = 0
        recordingElapsedSeconds = 0
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    @MainActor
    private func submit() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Please login again."
            return
        }
        guard let selectedProject else {
            errorMessage = "Please select a project."
            return
        }
        if isRecording {
            stopRecording()
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var audioStorageId: String?
            var audioFileSize: Int?
            var audioDuration: Int?
            if let recordedAudioData, !recordedAudioData.isEmpty {
                let uploadURL = try await authStore.generateAttachmentUploadURL()
                audioStorageId = try await authStore.uploadAttachmentData(
                    recordedAudioData,
                    uploadURL: uploadURL,
                    mimeType: "audio/mp4"
                )
                audioFileSize = recordedAudioData.count
                audioDuration = audioDurationSeconds
            }
            try await IssuesAPIService.createIssue(
                token: token,
                projectId: selectedProject.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description,
                audioStorageId: audioStorageId,
                audioFileName: audioStorageId == nil ? nil : "voice.m4a",
                audioFileType: audioStorageId == nil ? nil : "audio/mp4",
                audioFileSize: audioFileSize,
                audioDurationSeconds: audioDuration
            )
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct IssueStatusBadge: View {
    let status: String?

    private var label: String {
        status?.nonBlank?.capitalized ?? "Open"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: 0x175CD3))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color(hex: 0xEFF8FF), in: Capsule())
    }
}

private struct IssueCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(width: 170, height: 16)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(width: 120, height: 12)
                }
                Spacer()
            }
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(height: 14)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(width: 140, height: 12)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xE2E8F0), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .redacted(reason: .placeholder)
    }
}

#Preview {
    IssuesView()
        .environment(AuthStore())
}
