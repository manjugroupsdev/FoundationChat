import Foundation

struct LocationPoint: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let stackUserId: String
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double?
    let speed: Double?
    let heading: Double?
    let recordedAt: Double

    var recordedDate: Date {
        Date(timeIntervalSince1970: recordedAt / 1000)
    }
}

struct TrackedUser: Decodable, Identifiable, Equatable, Sendable {
    let stackUserId: String
    let name: String?
    let imageUrl: String?
    let lastLocation: LastLocation?

    var id: String { stackUserId }
    var displayName: String { name ?? stackUserId }
}

struct LastLocation: Decodable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let recordedAt: Double

    var recordedDate: Date {
        Date(timeIntervalSince1970: recordedAt / 1000)
    }
}

struct RecordLocationResult: Decodable, Sendable {
    let recorded: Bool
}

struct RecordBatchResult: Decodable, Sendable {
    let recorded: Int
}

struct DeleteLocationsResult: Decodable, Sendable {
    let deleted: Int
}
