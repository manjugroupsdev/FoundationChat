import SwiftUI

struct PermissionApprovalsView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var pendingPermissions: [ConvexPermission] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var rejectingPermission: ConvexPermission?
    @State private var rejectReason = ""
    @State private var actionInFlightId: String?

    private var approvalsCacheKey: String {
        let staff = authStore.currentSession?.user.staffId?.nonBlank
            ?? authStore.currentSession?.user._id.nonBlank
            ?? "anon"
        return "permissions.approvals.direct.\(staff)"
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if pendingPermissions.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Pending Requests",
                    systemImage: "checkmark.circle",
                    description: Text("All permission requests are cleared.")
                )
            }

            ForEach(pendingPermissions) { permission in
                permissionReviewCard(permission)
            }
        }
        .navigationTitle("Permission Approvals")
        .refreshable { loadData() }
        .overlay {
            if isLoading && pendingPermissions.isEmpty {
                ProgressView()
            }
        }
        .alert("Reject Permission", isPresented: Binding(
            get: { rejectingPermission != nil },
            set: { if !$0 { rejectingPermission = nil } }
        )) {
            TextField("Reason", text: $rejectReason)
            Button("Reject", role: .destructive) {
                if let rejectingPermission {
                    rejectPermission(rejectingPermission)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a reason for rejection")
        }
        .task { loadData() }
    }

    private func permissionReviewCard(_ permission: ConvexPermission) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.staffName ?? "Unknown Staff")
                        .font(.headline)
                    Text(permission.date ?? "--")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let hours = permission.durationHours {
                    Text(durationLabel(hours: hours))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Label(permission.timeRange, systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let reason = permission.reason, !reason.isEmpty {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    approvePermission(permission)
                } label: {
                    Label(actionInFlightId == permission._id ? "Working..." : "Approve", systemImage: "checkmark")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(actionInFlightId != nil)

                Button {
                    rejectingPermission = permission
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

    private func loadData() {
        guard let token = authStore.currentSession?.token else { return }
        if pendingPermissions.isEmpty,
           let cached = LocalCache.get(approvalsCacheKey, as: [ConvexPermission].self) {
            pendingPermissions = cached
        }
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            do {
                pendingPermissions = try await HRConvexAPIService.getPendingPermissionApprovals(
                    token: token,
                    scope: "direct",
                    viewerStaffId: authStore.currentSession?.user._id
                )
                LocalCache.put(approvalsCacheKey, pendingPermissions)
            } catch {
                if pendingPermissions.isEmpty {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func approvePermission(_ permission: ConvexPermission) {
        guard let token = authStore.currentSession?.token else { return }
        actionInFlightId = permission._id
        Task {
            defer { actionInFlightId = nil }
            do {
                try await HRConvexAPIService.approvePermission(token: token, id: permission._id)
                loadData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rejectPermission(_ permission: ConvexPermission) {
        guard let token = authStore.currentSession?.token else { return }
        let trimmedReason = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            errorMessage = "Please enter a rejection reason."
            return
        }

        actionInFlightId = permission._id
        Task {
            defer {
                actionInFlightId = nil
                rejectingPermission = nil
                rejectReason = ""
            }
            do {
                try await HRConvexAPIService.rejectPermission(
                    token: token,
                    id: permission._id,
                    reason: trimmedReason
                )
                loadData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func durationLabel(hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}

#Preview {
    NavigationStack {
        PermissionApprovalsView()
    }
}
