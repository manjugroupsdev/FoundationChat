import SwiftUI

struct LeaveApprovalsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var pendingLeaves: [ConvexLeave] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var rejectingLeave: ConvexLeave?
    @State private var rejectReason = ""

    var body: some View {
        List {
            if pendingLeaves.isEmpty && !isLoading {
                ContentUnavailableView("No Pending Approvals", systemImage: "checkmark.circle", description: Text("All caught up!"))
            }

            ForEach(pendingLeaves) { leave in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(leave.staffName ?? "Unknown")
                                .font(.headline)
                            Text(leave.leaveTypeLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let days = leave.days {
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
                            Label("Approve", systemImage: "checkmark")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

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
                pendingLeaves = try await HRConvexAPIService.getPendingLeaveApprovals(token: token)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func approveLeave(_ leave: ConvexLeave) {
        guard let token = authStore.currentSession?.token else { return }
        Task {
            do {
                try await HRConvexAPIService.approveLeave(token: token, id: leave._id)
                loadData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rejectLeave(_ leave: ConvexLeave, reason: String) {
        guard let token = authStore.currentSession?.token else { return }
        Task {
            do {
                try await HRConvexAPIService.rejectLeave(token: token, id: leave._id, reason: reason)
                loadData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
