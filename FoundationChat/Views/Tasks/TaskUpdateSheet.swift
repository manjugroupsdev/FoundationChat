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
    @State private var progressText: String
    @State private var todaysUpdate: String
    @State private var blocker: String
    @State private var tomorrowsPlan: String
    @State private var isSubmitting = false
    @State private var isLoadingPhotos = false
    @State private var errorMessage: String?
    @State private var selectedPhotoData: [Data] = []
    @State private var showingDatePicker = false
    @State private var didSelectDate = false

    init(task: ConvexTask, onSubmitted: @escaping () async -> Void) {
        self.task = task
        self.onSubmitted = onSubmitted
        _status = State(initialValue: task.normalizedStatus)
        _progress = State(initialValue: Double(task.displayProgress))
        _progressText = State(initialValue: "\(task.displayProgress)%")
        _todaysUpdate = State(initialValue: task.todaysUpdate ?? "")
        _blocker = State(initialValue: task.blocker ?? "")
        _tomorrowsPlan = State(initialValue: task.tomorrowsPlan ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    dateField
                    textArea(title: "Today’s Update", required: true, systemImage: "doc.text", text: $todaysUpdate, placeholder: "Enter today’s update", minHeight: 58)
                    progressField
                    singleLineField(title: "Issues/ Blockers", required: true, systemImage: "xmark.circle", text: $blocker, placeholder: "No issues")
                    singleLineField(title: "Tomorrows Plan", required: true, systemImage: "calendar.badge.clock", text: $tomorrowsPlan, placeholder: "Plan for tomorrow")
                    photosBlock

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }

            submitButton
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.white)
        .appCompactSheetCTAContainer()
        .onChange(of: progress) { _, value in
            progressText = "\(Int(value.rounded()))%"
            updateStatusFromProgress()
        }
        .sheet(isPresented: $showingDatePicker) {
            taskUpdateDatePicker
                .appLibraryNativeSheet([.height(470)])
                .presentationBackground(Color.white)
        }
    }

    private var submitButton: some View {
        VStack(spacing: 12) {
            Divider()
                .opacity(0.35)

            Button {
                submit()
            } label: {
                HStack(spacing: 10) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Update it")
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isSubmitting ? Color(hex: 0xA6ADB8) : Color(hex: 0x12B800), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color.white.opacity(0.98))
    }

    private var header: some View {
        VStack(alignment: .center, spacing: 7) {
            Text("Today’s Update")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            Text("Update your daily tasks in this form")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))

            Button {
                showingDatePicker = true
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "calendar")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))

                    Text(didSelectDate ? selectedDate.formatted(.dateTime.month(.abbreviated).day().year()) : "Select Date")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x101828))

                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(Color(hex: 0xFCFCFD), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: 0xD7DDE8), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var progressField: some View {
        VStack(alignment: .leading, spacing: 10) {
            requiredLabel("Progress %")

            HStack(spacing: 18) {
                Slider(value: $progress, in: 0...100, step: 1)
                    .tint(Color(hex: 0x0B61CA))

                Text("\(Int(progress.rounded()))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }

            HStack(spacing: 16) {
                Image(systemName: "hourglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))

                TextField("Select or Type Progress", text: $progressText)
                    .font(.system(size: 14, weight: .medium))
                    .keyboardType(.numberPad)
                    .foregroundStyle(Color(hex: 0x101828))
                    .onChange(of: progressText) { _, value in
                        applyTypedProgress(value)
                    }

                Menu {
                    ForEach(progressOptions, id: \.self) { value in
                        Button("\(value)%") {
                            setProgress(Double(value))
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color(hex: 0xFCFCFD), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: 0xD7DDE8), lineWidth: 1)
            }
        }
    }

    private var statusField: some View {
        VStack(alignment: .leading, spacing: 8) {
            requiredLabel("Progress Status")

            Menu {
                ForEach(TaskStatus.allCases, id: \.rawValue) { option in
                    Button {
                        status = option
                    } label: {
                        if status == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                    Text(status.label)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color(hex: 0x101828))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101828))
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color(hex: 0x98A2B3), lineWidth: 1)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func textArea(title: String, required: Bool, systemImage: String, text: Binding<String>, placeholder: String, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if required {
                requiredLabel(title)
            } else {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
            }

            HStack(alignment: .top, spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 24)
                    .padding(.top, 17)

                TextField(placeholder, text: text, axis: .vertical)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
                    .lineLimit(1...4)
                    .padding(.vertical, 16)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: minHeight)
            .background(Color(hex: 0xFCFCFD), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: 0xD7DDE8), lineWidth: 1)
            }
        }
    }

    private func singleLineField(title: String, required: Bool, systemImage: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if required {
                requiredLabel(title)
            } else {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
            }

            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 24)

                TextField(placeholder, text: text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x101828))
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color(hex: 0xFCFCFD), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: 0xD7DDE8), lineWidth: 1)
            }
        }
    }

    private var taskUpdateDatePicker: some View {
        VStack(spacing: 18) {
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Color(hex: 0x0B61CA))

            Button {
                didSelectDate = true
                showingDatePicker = false
            } label: {
                Text("Submit Date")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(hex: 0x12B800))
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .appCompactSheetCTAContainer()
    }

    private var photosBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photos")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                Spacer()
                Text("\(selectedPhotoData.count) \(selectedPhotoData.count == 1 ? "Photo" : "Photos")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(selectedPhotoData.enumerated()), id: \.offset) { index, data in
                        selectedPhotoThumbnail(data: data) {
                            selectedPhotoData.remove(at: index)
                        }
                    }

                    CameraFirstPhotoPicker(
                        maxSelectionCount: max(1, 6 - selectedPhotoData.count),
                        isDisabled: isSubmitting || isLoadingPhotos || selectedPhotoData.count >= 6
                    ) { photos in
                        isLoadingPhotos = true
                        selectedPhotoData.append(contentsOf: photos.prefix(max(0, 6 - selectedPhotoData.count)))
                        isLoadingPhotos = false
                    } label: {
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
                    .accessibilityLabel("Add photo")
                }
            }
        }
    }

    private var hasTimelineContent: Bool {
        todaysUpdate.trimmedForTask != nil || blocker.trimmedForTask != nil || tomorrowsPlan.trimmedForTask != nil || !selectedPhotoData.isEmpty
    }

    private var progressOptions: [Int] {
        Array(stride(from: 0, through: 100, by: 10))
    }

    private func requiredLabel(_ title: String) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .foregroundStyle(Color(hex: 0x667085))
            Text("*")
                .foregroundStyle(Color.red)
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func setProgress(_ value: Double) {
        progress = min(max(value, 0), 100)
        progressText = "\(Int(progress.rounded()))%"
        updateStatusFromProgress()
    }

    private func applyTypedProgress(_ value: String) {
        let digits = value.filter(\.isNumber)
        guard let number = Int(digits) else {
            if value.isEmpty {
                setProgress(0)
            }
            return
        }
        setProgress(Double(min(max(number, 0), 100)))
    }

    private func updateStatusFromProgress() {
        let rounded = Int(progress.rounded())
        if rounded >= 100 {
            status = .completed
        } else if rounded <= 0 {
            status = .pending
        } else {
            status = .inProgress
        }
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
