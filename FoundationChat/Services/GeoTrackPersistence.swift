import CoreData
import Foundation

// MARK: - PendingLocationPoint (NSManagedObject)

/// CoreData entity mirroring Android's LocationPointEntity (pending_points table).
/// Optional `altitude` is bridged as NSNumber? so nil survives round-trips.
final class PendingLocationPoint: NSManagedObject {
    @NSManaged var localId: UUID          // Primary key for deletion
    @NSManaged var lat: Double
    @NSManaged var lng: Double
    @NSManaged var accuracy: Double
    @NSManaged var speed: Double
    @NSManaged var bearing: Double
    @NSManaged var altitudeValue: NSNumber? // nil == no altitude fix
    @NSManaged var activity: String
    @NSManaged var activityConfidence: Int32
    @NSManaged var isMock: Bool
    @NSManaged var batteryPct: Int32
    @NSManaged var networkType: String
    @NSManaged var gpsEnabled: Bool
    @NSManaged var airplaneMode: Bool
    @NSManaged var recordedAt: Int64       // Unix epoch milliseconds
    @NSManaged var isSent: Bool

    func toGeoTrackPoint() -> GeoTrackLocationPoint {
        GeoTrackLocationPoint(
            lat: lat,
            lng: lng,
            accuracy: accuracy,
            speed: speed,
            bearing: bearing,
            altitude: altitudeValue?.doubleValue,
            activity: activity,
            activityConfidence: Int(activityConfidence),
            isMock: isMock,
            batteryPct: Int(batteryPct),
            networkType: networkType,
            gpsEnabled: gpsEnabled,
            airplaneMode: airplaneMode,
            recordedAt: recordedAt
        )
    }
}

// MARK: - PendingPoint (value type for passing across concurrency boundaries)

struct PendingPoint: Sendable {
    let id: UUID
    let point: GeoTrackLocationPoint
}

// MARK: - GeoTrackPersistence

/// Programmatic CoreData stack — no .xcdatamodeld file required.
/// All write operations run on a background context; reads use viewContext.
final class GeoTrackPersistence {
    static let shared = GeoTrackPersistence()

    let container: NSPersistentContainer

    /// Designated init. Pass `inMemory: true` for unit tests.
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(
            name: "GeoTrack",
            managedObjectModel: Self.makeModel()
        )
        if inMemory {
            let desc = NSPersistentStoreDescription()
            desc.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [desc]
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("GeoTrack CoreData failed to load: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Insert

    /// Saves one GPS point to the local buffer. Always isSent = false.
    func insert(point: GeoTrackLocationPoint) async throws {
        let ctx = container.newBackgroundContext()
        try await ctx.perform {
            let entity = PendingLocationPoint(context: ctx)
            entity.localId = UUID()
            entity.lat = point.lat
            entity.lng = point.lng
            entity.accuracy = point.accuracy
            entity.speed = point.speed
            entity.bearing = point.bearing
            entity.altitudeValue = point.altitude.map { NSNumber(value: $0) }
            entity.activity = point.activity
            entity.activityConfidence = Int32(point.activityConfidence)
            entity.isMock = point.isMock
            entity.batteryPct = Int32(point.batteryPct)
            entity.networkType = point.networkType
            entity.gpsEnabled = point.gpsEnabled
            entity.airplaneMode = point.airplaneMode
            entity.recordedAt = point.recordedAt
            entity.isSent = false
            try ctx.save()
        }
    }

    // MARK: - Fetch Unsent

    /// Returns up to `limit` unsent points ordered by recordedAt ASC.
    /// Matches Android: getUnsent(limit = 200).
    func fetchUnsent(limit: Int = 200) async throws -> [PendingPoint] {
        let ctx = container.newBackgroundContext()
        return try await ctx.perform {
            let request = NSFetchRequest<PendingLocationPoint>(entityName: "PendingLocationPoint")
            request.predicate = NSPredicate(format: "isSent == NO")
            request.sortDescriptors = [NSSortDescriptor(key: "recordedAt", ascending: true)]
            request.fetchLimit = limit
            let results = try ctx.fetch(request)
            return results.map { PendingPoint(id: $0.localId, point: $0.toGeoTrackPoint()) }
        }
    }

    // MARK: - Mark As Sent (delete)

    /// Deletes records with the given localIds. Called after a successful push-batch upload.
    /// Matches Android: deleteByIds(ids).
    func markAsSent(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let ctx = container.newBackgroundContext()
        try await ctx.perform {
            let request = NSFetchRequest<PendingLocationPoint>(entityName: "PendingLocationPoint")
            request.predicate = NSPredicate(format: "localId IN %@", ids as CVarArg)
            let toDelete = try ctx.fetch(request)
            toDelete.forEach { ctx.delete($0) }
            try ctx.save()
        }
    }

    // MARK: - Unsent Count

    /// Returns the number of unsent buffered points.
    func getUnsentCount() async throws -> Int {
        let ctx = container.newBackgroundContext()
        return try await ctx.perform {
            let request = NSFetchRequest<NSNumber>(entityName: "PendingLocationPoint")
            request.predicate = NSPredicate(format: "isSent == NO")
            request.resultType = .countResultType
            let results = try ctx.fetch(request)
            return results.first?.intValue ?? 0
        }
    }

    // MARK: - Purge Sent Points

    /// Deletes all rows where isSent == true. Matches Android: deleteSent().
    func purgeOldSentPoints() async throws {
        let ctx = container.newBackgroundContext()
        try await ctx.perform {
            let request = NSFetchRequest<PendingLocationPoint>(entityName: "PendingLocationPoint")
            request.predicate = NSPredicate(format: "isSent == YES")
            let toDelete = try ctx.fetch(request)
            toDelete.forEach { ctx.delete($0) }
            if ctx.hasChanges { try ctx.save() }
        }
    }

    // MARK: - Programmatic NSManagedObjectModel

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "PendingLocationPoint"
        entity.managedObjectClassName = NSStringFromClass(PendingLocationPoint.self)

        func attr(
            _ name: String,
            type: NSAttributeType,
            optional: Bool = false,
            default defaultValue: Any? = nil
        ) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            if let defaultValue { a.defaultValue = defaultValue }
            return a
        }

        entity.properties = [
            attr("localId",             type: .UUIDAttributeType),
            attr("lat",                 type: .doubleAttributeType,   default: 0.0),
            attr("lng",                 type: .doubleAttributeType,   default: 0.0),
            attr("accuracy",            type: .doubleAttributeType,   default: 0.0),
            attr("speed",               type: .doubleAttributeType,   default: 0.0),
            attr("bearing",             type: .doubleAttributeType,   default: 0.0),
            // altitude is optional — stored as NSNumber? (nil == no fix)
            attr("altitudeValue",       type: .doubleAttributeType,   optional: true),
            attr("activity",            type: .stringAttributeType,   default: "UNKNOWN"),
            attr("activityConfidence",  type: .integer32AttributeType, default: Int32(0)),
            attr("isMock",              type: .booleanAttributeType,  default: false),
            attr("batteryPct",          type: .integer32AttributeType, default: Int32(0)),
            attr("networkType",         type: .stringAttributeType,   default: "UNKNOWN"),
            attr("gpsEnabled",          type: .booleanAttributeType,  default: true),
            attr("airplaneMode",        type: .booleanAttributeType,  default: false),
            attr("recordedAt",          type: .integer64AttributeType, default: Int64(0)),
            attr("isSent",              type: .booleanAttributeType,  default: false),
        ]

        model.entities = [entity]
        return model
    }
}
