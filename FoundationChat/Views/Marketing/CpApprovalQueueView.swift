import SwiftUI

/// GM review queue for OUT-OF-GEOFENCE CP completions held for approval.
///
/// Mirrors Android `CpApprovalQueueBottomSheet`. Lists the completions awaiting
/// this GM (the server scopes the feed to the resolved approver), each with the
/// client, the field staff, the place + how far out of geofence, the recorded
/// outcome, the staff's reason, and the arrival photo. Approve → the visit
/// completes; Reject (with a remark) → the visit reopens for the same staff.
struct CpApprovalQueueView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var items: [CpApprovalItem] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var busyItemId: String?

    @State private var rejectTarget: CpApprovalItem?
    @State private var rejectRemark = ""

    private var cacheKey: String {
        let staffId = authStore.viewer?.subject ?? authStore.currentSession?.user._id ?? "anonymous"
        return "marketing.cp-approvals.pending.\(staffId)"
    }

    var body: some View {
        ScrollView {
            if isLoading && items.isEmpty {
                skeletonList
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else if items.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(items) { item in
                        CpApprovalCard(
                            item: item,
                            isBusy: busyItemId == item.id,
                            onApprove: { Task { await approve(item) } },
                            onReject: {
                                rejectRemark = ""
                                rejectTarget = item
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .refreshable { await load() }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("CP Approvals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("CP Approvals")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))
            }
        }
        .task { if !hasLoaded { await load() } }
        .alert("Reject & reassign", isPresented: Binding(
            get: { rejectTarget != nil },
            set: { if !$0 { rejectTarget = nil } }
        )) {
            TextField("Reason for rejecting", text: $rejectRemark)
            Button("Cancel", role: .cancel) { rejectTarget = nil }
            Button("Reject", role: .destructive) {
                if let target = rejectTarget {
                    Task { await reject(target, remark: rejectRemark) }
                }
            }
        } message: {
            Text("This reopens the visit for \(rejectTarget?.staffName ?? "the staff") with your remark.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Color(hex: 0x98A2B3))
                .padding(.top, 72)
            Text(errorMessage == nil ? "Nothing to Approve" : "Couldn't Load")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))
                .padding(.top, 16)
            Text(errorMessage ?? "Out-of-geofence CP completions waiting on your approval will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x667085))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var skeletonList: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: 0xE4E7EC))
                    .frame(height: 190)
                    .redacted(reason: .placeholder)
            }
        }
    }

    @MainActor
    private func load() async {
        if items.isEmpty,
           let cached = LocalCache.get(cacheKey, as: [CpApprovalItem].self) {
            items = cached
            hasLoaded = true
        }
        guard let token = authStore.currentSession?.token else {
            if items.isEmpty { errorMessage = "Not signed in." }
            hasLoaded = true
            return
        }
        isLoading = items.isEmpty
        defer { isLoading = false; hasLoaded = true }
        do {
            items = try await MarketingConvexAPIService.getPendingCpApprovals(token: token)
            LocalCache.put(cacheKey, items)
            errorMessage = nil
        } catch {
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func approve(_ item: CpApprovalItem) async {
        guard let token = authStore.currentSession?.token else { return }
        busyItemId = item.id
        defer { busyItemId = nil }
        do {
            try await MarketingConvexAPIService.approveCpCompletion(token: token, id: item.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reject(_ item: CpApprovalItem, remark: String) async {
        let trimmed = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "A remark is required to reject."
            return
        }
        guard let token = authStore.currentSession?.token else { return }
        rejectTarget = nil
        busyItemId = item.id
        defer { busyItemId = nil }
        do {
            try await MarketingConvexAPIService.rejectCpCompletion(token: token, id: item.id, remark: trimmed)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CpApprovalCard: View {
    let item: CpApprovalItem
    let isBusy: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.clientName?.blankToNil ?? "Client")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x101828))

            Text("by \(item.staffName?.blankToNil ?? "Field staff")")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x475467))

            if let place = placeLine, !place.isEmpty {
                Text(place)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xB54708))
                    .padding(.top, 4)
            }

            if let outcome = item.outcome?.blankToNil {
                Text("Outcome: \(outcome.replacingOccurrences(of: "_", with: " "))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x475467))
            }

            if let remark = item.staffRemark?.blankToNil {
                Text("Staff reason: \(remark)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x101828))
                    .padding(.top, 2)
            }

            if let scheduled = item.scheduledDate?.blankToNil {
                Text("Scheduled: \(scheduled)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x667085))
            }

            if let photoUrl = item.photoUrl?.blankToNil, let url = URL(string: photoUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color(hex: 0xF2F4F7).overlay(Image(systemName: "photo").foregroundStyle(Color(hex: 0x98A2B3)))
                    default:
                        Color(hex: 0xF2F4F7).overlay(ProgressView())
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 10)
            }

            HStack(spacing: 8) {
                Button(action: onReject) {
                    Text("Reject")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xB42318))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(hex: 0xFEE4E2), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Button(action: onApprove) {
                    Group {
                        if isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Text("Approve")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(hex: 0x169B2F), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
            .padding(.top, 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .stroke(Color(hex: 0xE4E7EC), lineWidth: 1)
        )
    }

    private var placeLine: String? {
        let distance = item.distanceMeters.map { meters -> String in
            let label: String
            if meters >= 1000 {
                label = String(format: "%.1f km", meters / 1000)
            } else {
                label = "\(Int(meters.rounded())) m"
            }
            return "\(label) out of geofence"
        }
        return [item.placeName?.blankToNil, distance]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private extension String {
    var blankToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
