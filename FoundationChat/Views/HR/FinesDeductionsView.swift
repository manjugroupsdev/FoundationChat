import SwiftUI

struct FinesDeductionsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var fines: [ConvexFineDeduction] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFine: ConvexFineDeduction?

    private var canViewAll: Bool {
        authStore.hasPermission("fines.view")
    }

    private var filteredFines: [ConvexFineDeduction] {
        guard canViewAll, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fines
        }
        return fines.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || ($0.employeeId ?? "").localizedCaseInsensitiveContains(searchText)
                || $0.displayDepartment.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if canViewAll {
                        searchField
                            .padding(.bottom, 4)
                    }

                    if isLoading && fines.isEmpty {
                        fineSkeletons
                    } else if filteredFines.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 90)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredFines) { fine in
                                FineDeductionCard(fine: fine) {
                                    selectedFine = fine
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .refreshable { await loadFines() }
        }
        .background(Color(hex: 0xF5F6FA).ignoresSafeArea())
        .navigationTitle("Fines & Deductions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadFines() }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .sheet(item: $selectedFine) { fine in
            FineDeductionDetailSheet(fine: fine)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 34, height: 34)
                        .background(Color(hex: 0xEEF6FF), in: Circle())
                }
                .buttonStyle(.plain)

                Text("Fines & Deductions")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1D2939))
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 46)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.white)

            Divider()
                .background(Color(hex: 0xE4E7EC))
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            TextField("Search Employee", text: $searchText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: 0x1D2939))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x475467))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        }
    }

    private var fineSkeletons: some View {
        VStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .frame(height: 86)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 14) {
                            Circle().fill(Color(hex: 0xEEF2F6)).frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xEEF2F6)).frame(width: 120, height: 14)
                                RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xEEF2F6)).frame(width: 170, height: 10)
                            }
                            Spacer()
                            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xEEF2F6)).frame(width: 58, height: 16)
                        }
                        .padding(16)
                    }
                    .redacted(reason: .placeholder)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color(hex: 0x98A2B3))
                .frame(width: 78, height: 78)
                .background(Color.white, in: Circle())

            Text("No Fines Recorded")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x1D2939))

            Text(canViewAll ? "Search another name or add a new fine." : "Your active fines and deductions will show here.")
                .font(.system(size: 13, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x98A2B3))
                .padding(.horizontal, 24)
        }
    }

    @MainActor
    private func loadFines() async {
        guard let token = authStore.currentSession?.token, !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            fines = canViewAll
                ? try await HRConvexAPIService.listFines(token: token, status: "active")
                : try await HRConvexAPIService.listMyFines(token: token)
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

private struct FineDeductionCard: View {
    let fine: ConvexFineDeduction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                FineAvatar(name: fine.displayName, urlString: fine.staffPhotoUrl, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(fine.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1D2939))
                        .lineLimit(1)

                    Text("\(fine.displayDepartment)\n\(fine.displayType)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineSpacing(2)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "indianrupeesign.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B61CA))
                        Text(AppModuleFormatters.rupees(fine.amount ?? 0))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1D2939))
                    }

                    Text(fine.displayStatus)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x22C55E))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Color(hex: 0xECFDF3), in: Capsule())

                    Text(fine.displayDate)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct FineDeductionDetailSheet: View {
    let fine: ConvexFineDeduction

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(Color(hex: 0xD0D5DD))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)

                Text(fine.displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x101828))

                Text(detailMeta)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x667085))
                    .padding(.top, 4)

                finePhoto
                    .padding(.top, 16)

                Text("Reason")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x344054))
                    .padding(.top, 18)

                Text(fine.notes?.nonBlank ?? "No reason provided")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(hex: 0x475467))
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(Color.white)
    }

    private var detailMeta: String {
        [
            fine.displayType,
            AppModuleFormatters.rupees(fine.amount ?? 0),
            fine.displayStatus,
            fine.displayDate
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "  -  ")
    }

    @ViewBuilder
    private var finePhoto: some View {
        if let url = resolvedURL(fine.photoUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    noPhoto("Could not load picture")
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
            }
        } else {
            noPhoto("No picture attached")
        }
    }

    private func noPhoto(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(hex: 0x9CA3AF))
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
            }
    }
}

private struct FineAvatar: View {
    let name: String
    let urlString: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = resolvedURL(urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold))
            .foregroundStyle(Color(hex: 0x0B61CA))
            .frame(width: size, height: size)
            .background(Color(hex: 0xEEF8FF), in: Circle())
    }

    private var initials: String {
        let pieces = name
            .split(separator: " ")
            .compactMap(\.first)
        let text = String(pieces.prefix(2)).uppercased()
        return text.isEmpty ? "S" : text
    }
}

private func resolvedURL(_ value: String?) -> URL? {
    guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty,
          raw != "null",
          raw != "undefined"
    else { return nil }

    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
        return URL(string: raw)
    }
    if raw.hasPrefix("/") {
        return URL(string: "\(AppConfig.baseURL)\(raw)")
    }
    return URL(string: raw)
}

#Preview {
    FinesDeductionsView()
        .environment(AuthStore())
}
