import CoreLocation
import SwiftUI

// MARK: - GeoTrackAssignedPlacesView

struct GeoTrackAssignedPlacesView: View {
    @State private var places: [GeoTrackAssignedPlace] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var selectedPlace: GeoTrackAssignedPlace?
    @State private var placeToNavigate: GeoTrackAssignedPlace?
    @State private var searchText = ""

    private let geoAPI = GeoTrackAPIService.shared

    private var filtered: [GeoTrackAssignedPlace] {
        guard !searchText.isEmpty else { return places }
        return places.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.address ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.type ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading places…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    "No Places",
                    systemImage: "building.2",
                    description: Text("Assigned client places will appear here.")
                )
            } else {
                List(filtered) { place in
                    PlaceRow(
                        place: place,
                        onScheduleVisit: {
                            selectedPlace = place
                            showCreateSheet = true
                        },
                        onVisitNow: { placeToNavigate = place }
                    )
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search places")
            }
        }
        .navigationTitle("Assigned Places")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showCreateSheet) {
            if let place = selectedPlace {
                CreateVisitSheet(place: place, onCreated: {
                    showCreateSheet = false
                })
            }
        }
        .fullScreenCover(item: $placeToNavigate) { place in
            TripNavigationView(
                placeId: place.id,
                placeName: place.name,
                placeAddress: place.address,
                destination: coordinate(for: place)
            )
        }
    }

    private func coordinate(for place: GeoTrackAssignedPlace) -> CLLocationCoordinate2D? {
        guard let lat = place.lat, let lng = place.lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            places = try await geoAPI.assignedPlaces()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - PlaceRow

private struct PlaceRow: View {
    let place: GeoTrackAssignedPlace
    let onScheduleVisit: () -> Void
    let onVisitNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.subheadline.weight(.semibold))
                    if let type = place.type {
                        Text(type)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onScheduleVisit) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .tint(.blue)
            }

            if let address = place.address {
                Label(address, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let contact = place.contactPerson {
                Label(contact, systemImage: "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: onVisitNow) {
                Label("Visit Now", systemImage: "location.north.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - CreateVisitSheet

private struct CreateVisitSheet: View {
    let place: GeoTrackAssignedPlace
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scheduledDate = Date()
    @State private var notes = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    private let geoAPI = GeoTrackAPIService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Place") {
                    LabeledContent("Name", value: place.name)
                    if let address = place.address {
                        LabeledContent("Address", value: address)
                    }
                }

                Section("Visit Details") {
                    DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }

                Section {
                    Button {
                        Task { await createVisit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCreating {
                                ProgressView()
                            } else {
                                Label("Schedule Visit", systemImage: "calendar.badge.plus")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isCreating)
                }
            }
            .navigationTitle("Schedule Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createVisit() async {
        isCreating = true
        errorMessage = nil
        do {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            _ = try await geoAPI.createVisit(
                clientPlaceId: place.id,
                scheduledDate: df.string(from: scheduledDate),
                notes: notes.isEmpty ? nil : notes
            )
            onCreated()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - GeoTrackAssignedPlace Identifiable

extension GeoTrackAssignedPlace: Identifiable {}

#Preview {
    NavigationStack {
        GeoTrackAssignedPlacesView()
    }
}
