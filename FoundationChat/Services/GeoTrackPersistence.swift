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

final class PendingTamperEvent: NSManagedObject {
    @NSManaged var localId: UUID
    @NSManaged var eventType: String
    @NSManaged var metadataJSON: String
    @NSManaged var recordedAt: Int64
}

// MARK: - PendingPoint (value type for passing across concurrency boundaries)

struct PendingPoint: Sendable {
    let id: UUID
    let point: GeoTrackLocationPoint
}

struct PendingTamperEventValue: Sendable {
    let id: UUID
    let eventType: GeoTrackTamperEventType
    let metadata: [String: String]
    // Original detection time (ms epoch), stamped when the event was buffered.
    // Replayed to the server as `detectedAt` so an offline tamper event surfaces
    // at its true time, not the sync time.
    let recordedAt: Int64
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
        container.persistentStoreDescriptions.forEach { description in
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        // Never crash the whole app on a corrupt / migration-failed local buffer.
        // A GeoTrack DB failure must degrade gracefully: this is a best-effort
        // store-and-forward buffer, not critical app state. Recovery ladder:
        //   1. destroy the on-disk store and recreate it empty (loses buffered
        //      points, but the alternative was a hard crash),
        //   2. if that still fails, fall back to an in-memory store so all
        //      inserts/fetches are harmless no-ops rather than a fatalError.
        let coordinator = container.persistentStoreCoordinator
        container.loadPersistentStores { description, error in
            guard let error else { return }
            NSLog("GeoTrack CoreData failed to load: \(error). Attempting recovery.")

            if let storeURL = description.url, description.type != NSInMemoryStoreType {
                try? coordinator.destroyPersistentStore(
                    at: storeURL, ofType: description.type, options: nil
                )
                try? FileManager.default.removeItem(at: storeURL)
                do {
                    try coordinator.addPersistentStore(
                        ofType: description.type,
                        configurationName: nil,
                        at: storeURL,
                        options: nil
                    )
                    NSLog("GeoTrack CoreData store recreated after load failure.")
                    return
                } catch {
                    NSLog("GeoTrack CoreData recreate failed: \(error). Falling back to in-memory buffer.")
                }
            }

            do {
                try coordinator.addPersistentStore(
                    ofType: NSInMemoryStoreType,
                    configurationName: nil,
                    at: nil,
                    options: nil
                )
                NSLog("GeoTrack CoreData degraded to in-memory buffer (no crash).")
            } catch {
                NSLog("GeoTrack CoreData in-memory fallback also failed: \(error). Buffer disabled.")
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

    func insertTamperEvent(eventType: GeoTrackTamperEventType, metadata: [String: String]) async throws {
        let ctx = container.newBackgroundContext()
        try await ctx.perform {
            let entity = PendingTamperEvent(context: ctx)
            entity.localId = UUID()
            entity.eventType = eventType.rawValue
            let data = try JSONEncoder().encode(metadata)
            entity.metadataJSON = String(data: data, encoding: .utf8) ?? "{}"
            entity.recordedAt = Int64(Date().timeIntervalSince1970 * 1000)
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

    func fetchUnsentTamperEvents(limit: Int = 50) async throws -> [PendingTamperEventValue] {
        let ctx = container.newBackgroundContext()
        return try await ctx.perform {
            let request = NSFetchRequest<PendingTamperEvent>(entityName: "PendingTamperEvent")
            request.sortDescriptors = [NSSortDescriptor(key: "recordedAt", ascending: true)]
            request.fetchLimit = limit
            let results = try ctx.fetch(request)
            return results.compactMap { event in
                guard let type = GeoTrackTamperEventType(rawValue: event.eventType) else {
                    return nil
                }
                let data = Data(event.metadataJSON.utf8)
                let metadata = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
                return PendingTamperEventValue(
                    id: event.localId,
                    eventType: type,
                    metadata: metadata,
                    recordedAt: event.recordedAt
                )
            }
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

    func deleteTamperEvents(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let ctx = container.newBackgroundContext()
        try await ctx.perform {
            let request = NSFetchRequest<PendingTamperEvent>(entityName: "PendingTamperEvent")
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

    // MARK: - Age-based Purge (offline safety cap)

    /// Deletes unsent points older than `cutoffMillis` (ms epoch). Mirrors
    /// Android `deleteUnsentOlderThan(now - MAX_UNSENT_POINT_AGE_MS)` (30 days):
    /// a genuinely-abandoned local DB (device never recovered) can't grow
    /// unbounded, while a multi-day offline field trip still flushes on
    /// reconnect. On iOS `markAsSent` already deletes on successful upload, so
    /// there is no separate sent-point retention to purge.
    func purgeStaleUnsentPoints(olderThan cutoffMillis: Int64) async throws {
        let ctx = container.newBackgroundContext()
        try await ctx.perform {
            let request = NSFetchRequest<PendingLocationPoint>(entityName: "PendingLocationPoint")
            request.predicate = NSPredicate(format: "isSent == NO AND recordedAt < %lld", cutoffMillis)
            let toDelete = try ctx.fetch(request)
            toDelete.forEach { ctx.delete($0) }
            if ctx.hasChanges { try ctx.save() }
        }
    }

    /// Deletes buffered tamper/health events older than `cutoffMillis` (ms epoch).
    /// Mirrors Android's 30-day retention for pending events — they are the
    /// battery/uptime history of the same offline window as unsent points.
    func purgeStaleTamperEvents(olderThan cutoffMillis: Int64) async throws {
        let ctx = container.newBackgroundContext()
        try await ctx.perform {
            let request = NSFetchRequest<PendingTamperEvent>(entityName: "PendingTamperEvent")
            request.predicate = NSPredicate(format: "recordedAt < %lld", cutoffMillis)
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

        let tamperEntity = NSEntityDescription()
        tamperEntity.name = "PendingTamperEvent"
        tamperEntity.managedObjectClassName = NSStringFromClass(PendingTamperEvent.self)
        tamperEntity.properties = [
            attr("localId",      type: .UUIDAttributeType),
            attr("eventType",    type: .stringAttributeType, default: ""),
            attr("metadataJSON", type: .stringAttributeType, default: "{}"),
            attr("recordedAt",   type: .integer64AttributeType, default: Int64(0)),
        ]

        model.entities = [entity, tamperEntity]
        return model
    }
}
