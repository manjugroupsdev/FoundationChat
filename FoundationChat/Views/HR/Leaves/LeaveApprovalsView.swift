import SwiftUI

struct LeaveApprovalsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var pendingLeaves: [ConvexLeave] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var rejectingLeave: ConvexLeave?
    @State private var rejectReason = ""
    @State private var actionInFlightId: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if pendingLeaves.isEmpty && !isLoading {
                ContentUnavailableView("No Pending Approvals", systemImage: "checkmark.circle", description: Text("All caught up!"))
            }

            ForEach(pendingLeaves) { leave in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(leave.staffName ?? "Unknown")
                                .font(.headline)
                            Text(leave.isHalfDayLeave ? halfDayLabel(leave) : leave.leaveTypeLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if leave.isHalfDayLeave {
                            Text("0.5d")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.blue)
                        } else if let days = leave.days {
                            Text("\(Int(days))d")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }

                    HStack {
                        Label(leave.fromDate ?? "--", systemImage: "calendar")
                        if let to = leave.toDate, to != leave.fromDate {
                            Text("→ \(to)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let reason = leave.reason {
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            approveLeave(leave)
                        } label: {
                            Label(actionInFlightId == leave._id ? "Working..." : "Approve", systemImage: "checkmark")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(actionInFlightId != nil)

                        Button {
                            rejectingLeave = leave
                            rejectReason = ""
                        } label: {
                            Label("Reject", systemImage: "xmark")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(actionInFlightId != nil)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Leave Approvals")
        .refreshable { loadData() }
        .overlay {
            if isLoading && pendingLeaves.isEmpty { ProgressView() }
        }
        .alert("Reject Leave", isPresented: .init(
            get: { rejectingLeave != nil },
            set: { if !$0 { rejectingLeave = nil } }
        )) {
            TextField("Reason", text: $rejectReason)
            Button("Reject", role: .destructive) {
                if let leave = rejectingLeave {
                    rejectLeave(leave, reason: rejectReason)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a reason for rejection")
        }
        .task { loadData() }
    }

    private func loadData() {
        guard let token = authStore.currentSession?.token else { return }
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                pendingLeaves = try await HRConvexAPIService.getPendingLeaveApprovals(
                    token: token,
                    teamOnly: true,
                    scope: "direct",
                    viewerStaffId: authStore.currentSession?.user._id
                )
            } catch {
                if Self.isCancellation(error) { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func approveLeave(_ leave: ConvexLeave) {
        guard let token = authStore.currentSession?.token else { return }
        actionInFlightId = leave._id
        Task {
            defer { actionInFlightId = nil }
            do {
                try await HRConvexAPIService.approveLeave(token: token, id: leave._id)
                loadData()
            } catch {
                if Self.isCancellation(error) { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rejectLeave(_ leave: ConvexLeave, reason: String) {
        guard let token = authStore.currentSession?.token else { return }
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            errorMessage = "Please enter a rejection reason."
            return
        }
        actionInFlightId = leave._id
        Task {
            defer {
                actionInFlightId = nil
                rejectingLeave = nil
                rejectReason = ""
            }
            do {
                try await HRConvexAPIService.rejectLeave(token: token, id: leave._id, reason: trimmedReason)
                loadData()
            } catch {
                if Self.isCancellation(error) { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func halfDayLabel(_ leave: ConvexLeave) -> String {
        let base = leave.leaveTypeLabel
        guard let raw = leave.halfDaySession?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "\(base) · Half-day"
        }
        let session = raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
        return "\(base) · Half-day (\(session))"
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as NSError).code == NSURLErrorCancelled
    }
}
