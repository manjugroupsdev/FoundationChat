import SwiftUI

struct TaskUpdateSheet: View {
    let task: ConvexTask
    let onSubmitted: () async -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var progress: Double
    @State private var comment: String = ""
    @State private var status: TaskStatus
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(task: ConvexTask, onSubmitted: @escaping () async -> Void) {
        self.task = task
        self.onSubmitted = onSubmitted
        _progress = State(initialValue: Double(task.displayProgress))
        _status = State(initialValue: task.normalizedStatus)
    }

    var body: some View {
        Form {
            Section("Progress") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(Int(progress.rounded()))%")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.indigo)
                            .monospacedDigit()
                        Spacer()
                    }
                    Slider(value: $progress, in: 0...100, step: 5) {
                        Text("Progress")
                    } minimumValueLabel: {
                        Text("0").font(.caption2)
                    } maximumValueLabel: {
                        Text("100").font(.caption2)
                    }
                    .tint(.indigo)
                    .onChange(of: progress) { _, new in
                        if new >= 100 { status = .completed }
                        else if new > 0 && status == .pending { status = .inProgress }
                    }
                }
            }

            Section("Status") {
                Picker("Status", selection: $status) {
                    ForEach(TaskStatus.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Comment") {
                TextField("Add a note about this update", text: $comment, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Update Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    submit()
                }
                .disabled(isSubmitting || !hasChanges)
            }
        }
        .overlay {
            if isSubmitting {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    private var hasChanges: Bool {
        Int(progress.rounded()) != task.displayProgress
            || status != task.normalizedStatus
            || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in"
            return
        }
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let newProgress = Int(progress.rounded())
        let progressChanged = newProgress != task.displayProgress
        let statusChanged = status != task.normalizedStatus
        let commentOnly = !trimmedComment.isEmpty && !progressChanged && !statusChanged

        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            do {
                if progressChanged {
                    try await TasksConvexAPIService.updateProgress(
                        token: token,
                        taskId: task._id,
                        progress: newProgress,
                        comment: trimmedComment.isEmpty ? nil : trimmedComment
                    )
                }
                if statusChanged {
                    try await TasksConvexAPIService.updateStatus(
                        token: token,
                        taskId: task._id,
                        status: status.serverValue
                    )
                }
                if commentOnly {
                    try await TasksConvexAPIService.addUpdate(
                        token: token,
                        taskId: task._id,
                        comment: trimmedComment
                    )
                }
                await onSubmitted()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
