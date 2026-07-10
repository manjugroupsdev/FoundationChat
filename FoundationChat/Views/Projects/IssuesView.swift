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
            searchBar

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
            .presentationDetents([.height(620), .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            TextField("Search Issues", text: $searchText)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x64748B))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xE2E8F0), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, y: 3)
        .padding(.horizontal, 16)
        .padding(.top, 16)
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

    @State private var projectId = ""
    @State private var title = ""
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create Issue")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color(hex: 0x101828))
                        Text("Information about project issue")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: 0x667085))
                    }
                    .padding(.top, 16)

                    issueField(title: "Project ID *", text: $projectId, placeholder: "Enter project id", icon: "folder")
                    issueField(title: "Title *", text: $title, placeholder: "Title is compulsory", icon: "text.badge.checkmark")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x344054))
                        TextEditor(text: $description)
                            .font(.system(size: 15, weight: .medium))
                            .frame(minHeight: 120)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xDC2626))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 26)
                .padding(.bottom, 18)
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
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .background(Color.white)
        }
        .background(Color.white)
    }

    private func issueField(title: String, text: Binding<String>, placeholder: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x344054))
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x667085))
                    .frame(width: 24)
                TextField(placeholder, text: text)
                    .font(.system(size: 15, weight: .medium))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE4E7EC), lineWidth: 1))
        }
    }

    @MainActor
    private func submit() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Please login again."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await IssuesAPIService.createIssue(
                token: token,
                projectId: projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description
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
