import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TaskUpdateSheet: View {
    let task: ConvexTask
    let onSubmitted: () async -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var status: TaskStatus
    @State private var selectedDate = Date()
    @State private var progress: Double
    @State private var todaysUpdate: String
    @State private var blocker: String
    @State private var tomorrowsPlan: String
    @State private var isSubmitting = false
    @State private var isLoadingPhotos = false
    @State private var errorMessage: String?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedPhotoData: [Data] = []

    init(task: ConvexTask, onSubmitted: @escaping () async -> Void) {
        self.task = task
        self.onSubmitted = onSubmitted
        _status = State(initialValue: task.normalizedStatus)
        _progress = State(initialValue: Double(task.displayProgress))
        _todaysUpdate = State(initialValue: task.todaysUpdate ?? "")
        _blocker = State(initialValue: task.blocker ?? "")
        _tomorrowsPlan = State(initialValue: task.tomorrowsPlan ?? "")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                statusPicker
                dateField
                progressField
                textArea(title: "Today's Update", text: $todaysUpdate, placeholder: "What did you accomplish today?", minHeight: 136)
                textArea(title: "Issues / Blockers", text: $blocker, placeholder: "No Issues", minHeight: 104)
                textArea(title: "Tomorrow's Plan", text: $tomorrowsPlan, placeholder: "What will you work on tomorrow?", minHeight: 104)
                photosBlock

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Button {
                    submit()
                } label: {
                    Text(isSubmitting ? "Updating..." : "Update It")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(hex: 0x7A35F8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color.white)
        .onChange(of: selectedPhotoItems) { _, _ in
            Task { await loadSelectedPhotos() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0xE4E7EC))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)

            Text("Update Task")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            Text("Set status, progress, and notes for today.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(hex: 0x475467))
        }
    }

    private var statusPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            HStack(spacing: 8) {
                ForEach(TaskStatus.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            setStatus(item, fromUser: true)
                        }
                    } label: {
                        Text(updateStatusLabel(item))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(status == item ? .white : Color(hex: 0x475467))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(status == item ? Color(hex: 0x7A5AF8) : Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color(hex: 0xE5E7EB), lineWidth: status == item ? 0 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            HStack {
                Text(selectedDate, format: .dateTime.month(.wide).day().year())
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .tint(Color(hex: 0x7A5AF8))
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }
        }
    }

    private var progressField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Progress %")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                Text("\(Int(progress.rounded()))%")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x7A5AF8))
            }

            Slider(value: $progress, in: 0...100, step: 1)
                .tint(Color(hex: 0x7A5AF8))
                .onChange(of: progress) { _, value in
                    if value >= 100 { status = .completed }
                    else if value == 0 && status != .delayed { status = .pending }
                    else if value > 0 && status == .pending { status = .inProgress }
                }
        }
    }

    private func textArea(title: String, text: Binding<String>, placeholder: String, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(hex: 0x101828))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: minHeight)

                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }
        }
    }

    private var photosBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photos")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Spacer()
                Text("\(selectedPhotoData.count) \(selectedPhotoData.count == 1 ? "Photo" : "Photos")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x475467))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(selectedPhotoData.enumerated()), id: \.offset) { index, data in
                        selectedPhotoThumbnail(data: data) {
                            selectedPhotoData.remove(at: index)
                            if selectedPhotoItems.indices.contains(index) {
                                selectedPhotoItems.remove(at: index)
                            }
                        }
                    }

                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 6, matching: .images) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(hex: 0xF8FAFC))
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)

                            if isLoadingPhotos {
                                ProgressView()
                                    .tint(Color(hex: 0x7A5AF8))
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x7A5AF8))
                            }
                        }
                        .frame(width: 76, height: 76)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting || isLoadingPhotos)
                    .accessibilityLabel("Add photo")
                }
            }
        }
    }

    private var hasTimelineContent: Bool {
        todaysUpdate.trimmedForTask != nil || blocker.trimmedForTask != nil || tomorrowsPlan.trimmedForTask != nil || !selectedPhotoData.isEmpty
    }

    private func setStatus(_ next: TaskStatus, fromUser: Bool) {
        status = next
        switch next {
        case .completed:
            progress = 100
        case .pending:
            if fromUser { progress = 0 }
        case .inProgress:
            if fromUser && progress == 0 { progress = 10 }
        case .delayed:
            break
        }
    }

    private func updateStatusLabel(_ status: TaskStatus) -> String {
        status == .pending ? "Not Started" : status.label
    }

    private func selectedPhotoThumbnail(data: Data, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                #if canImport(UIKit)
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(hex: 0xF8FAFC)
                }
                #else
                Color(hex: 0xF8FAFC)
                #endif
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.65), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove photo")
        }
    }

    private func loadSelectedPhotos() async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }

        var loaded: [Data] = []
        for item in selectedPhotoItems {
            if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                loaded.append(data)
            }
        }
        selectedPhotoData = loaded
    }

    private func submit() {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in"
            return
        }
        let newProgress = Int(progress.rounded())
        let selectedDateString = AppModuleFormatters.ymd.string(from: selectedDate)
        let actualToday = AppModuleFormatters.ymd.string(from: Date())

        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            do {
                let uploadedImages = try await uploadSelectedPhotos(token: token)
                try await TasksConvexAPIService.updateTask(
                    token: token,
                    taskId: task._id,
                    status: status.serverValue,
                    progress: newProgress,
                    actualStartDate: (status == .inProgress || status == .completed) ? actualToday : nil,
                    actualEndDate: status == .completed ? actualToday : nil
                )

                if hasTimelineContent {
                    try await TasksConvexAPIService.addTimelineUpdate(
                        token: token,
                        taskId: task._id,
                        date: selectedDateString,
                        todaysUpdate: todaysUpdate.trimmedForTask,
                        blocker: blocker.trimmedForTask,
                        tomorrowsPlan: tomorrowsPlan.trimmedForTask,
                        progressSnapshot: newProgress,
                        images: uploadedImages.isEmpty ? nil : uploadedImages
                    )
                }

                await onSubmitted()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func uploadSelectedPhotos(token: String) async throws -> [TaskUpdateImage] {
        guard !selectedPhotoData.isEmpty else { return [] }

        var uploaded: [TaskUpdateImage] = []
        for (index, data) in selectedPhotoData.enumerated() {
            let storageId = try await HRConvexAPIService.uploadPhoto(token: token, imageData: data)
            uploaded.append(TaskUpdateImage(storageId: storageId, url: nil, name: "task_update_\(index + 1).jpg"))
        }
        return uploaded
    }
}

private extension String {
    var trimmedForTask: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
