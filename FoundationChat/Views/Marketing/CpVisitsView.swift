import CoreLocation
import SwiftUI

struct CpVisitsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var visits: [ConvexSiteVisit] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false

    var body: some View {
        List {
            Section {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create CP Visit", systemImage: "plus.circle.fill")
                        .font(AppModuleFont.rowTitle)
                }
            }

            if isLoading && visits.isEmpty {
                ProgressView("Loading CP visits…")
            } else if visits.isEmpty {
                ContentUnavailableView(
                    "No CP Visits",
                    systemImage: "mappin.and.ellipse",
                    description: Text(errorMessage ?? "No CP visits yet. Tap Create to add one.")
                )
            } else {
                ForEach(visits) { visit in
                    NavigationLink {
                        TripNavigationView(
                            visitId: visit.id,
                            placeName: visit.placeName ?? visit.leadName ?? "CP Visit",
                            placeAddress: visit.placeAddress,
                            destination: coordinate(for: visit),
                            initialStatus: visit.status
                        )
                    } label: {
                        CpVisitRow(visit: visit)
                    }
                }
            }
        }
        .navigationTitle("CP Visits")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .sheet(isPresented: $showCreateSheet) {
            NavigationStack {
                CreateCpVisitSheet {
                    showCreateSheet = false
                    Task { await load() }
                }
            }
        }
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else {
            errorMessage = "Not signed in."
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        let calendar = Calendar.current
        let today = Date()
        let from = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: 30, to: today) ?? today
        do {
            let all = try await HRConvexAPIService.getMySiteVisits(
                token: token,
                fromDate: AppModuleFormatters.ymd.string(from: from),
                toDate: AppModuleFormatters.ymd.string(from: to)
            )
            visits = all
                .filter { $0.tripType == "client_place" || $0.clientPlaceVisitId != nil }
                .sorted { ($0.scheduledDate ?? "") > ($1.scheduledDate ?? "") }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func coordinate(for visit: ConvexSiteVisit) -> CLLocationCoordinate2D? {
        guard let lat = visit.placeLat, let lng = visit.placeLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

private struct CpVisitRow: View {
    let visit: ConvexSiteVisit

    var body: some View {
        HStack(spacing: 12) {
            Text(String((visit.placeName ?? visit.leadName ?? "C").prefix(1)).uppercased())
                .font(AppModuleFont.rowTitle)
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 42, height: 42)
                .background(Color(hex: 0xEAF3FF), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(visit.placeName ?? visit.leadName ?? "CP Visit")
                    .font(AppModuleFont.rowTitle)
                Text(visit.scheduledDate ?? "—")
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(.secondary)
                Text((visit.placeLat != nil && visit.placeLng != nil) ? "Open route" : "Not mapped")
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AppModuleBadge(text: statusTitle, tint: statusTint)
        }
        .padding(.vertical, 5)
    }

    private var statusTitle: String {
        switch (visit.status ?? "").lowercased() {
        case "completed": return "Complete"
        case "in-progress", "arrived": return "Enroute"
        default: return "Start"
        }
    }

    private var statusTint: Color {
        switch (visit.status ?? "").lowercased() {
        case "completed": return .green
        case "in-progress", "arrived": return .orange
        default: return Color(hex: 0x0B61CA)
        }
    }
}

private struct CreateCpVisitSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    @State private var clientName = ""
    @State private var phone = ""
    @State private var date = Date()
    @State private var time = ""
    @State private var address = ""
    @State private var mapsLink = ""
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Client") {
                TextField("Client name", text: $clientName)
                    .textContentType(.name)
                TextField("10 digit phone", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }

            Section("Visit") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Time (optional)", text: $time)
                TextField("Address", text: $address, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Google Maps link", text: $mapsLink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .navigationTitle("Create CP Visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting { ProgressView() } else { Text("Create") }
                }
                .disabled(isSubmitting)
            }
        }
        .alert("CP Visit", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func submit() async {
        let normalizedPhone = AppModuleFormatters.normalizePhone(phone)
        guard normalizedPhone.count == 10 else { errorMessage = "Enter 10 digit phone"; return }
        let staffId = authStore.currentSession?.user.staffId ?? authStore.currentSession?.user._id
        guard let staffId, !staffId.isEmpty else { errorMessage = "Staff session missing"; return }
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { errorMessage = "Address is required"; return }
        guard let token = authStore.currentSession?.token else { return }

        let request = CreateCpVisitRequest(
            leadId: nil,
            clientName: clientName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            mobileNumber: normalizedPhone,
            assignedStaffId: staffId,
            scheduledDate: AppModuleFormatters.ymd.string(from: date),
            scheduledTime: time.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            visitAddress: trimmedAddress,
            visitLat: nil,
            visitLng: nil,
            googleMapsLink: mapsLink.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await MarketingConvexAPIService.createCpVisit(token: token, request: request)
            onCreated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
