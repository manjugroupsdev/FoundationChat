import CoreData
import Foundation

// MARK: - PendingPunch (NSManagedObject)

/// CoreData entity mirroring Android's `PendingPunchEntity` (pending_punches table).
///
/// One row per attendance punch (in/out) that couldn't reach the server because
/// the device was offline / the network failed. The staff's REAL tap time is kept
/// in `clientPunchTime` so, when the queue flushes after connectivity returns, the
/// punch is recorded at the time it actually happened — not the (later) sync time.
/// This is what stops attendance times drifting due to network delay.
///
/// The proof selfie is kept as a local JPEG file (`photoPath`) and uploaded at
/// flush time; storing a Convex storage id here would be impossible while offline.
/// Optional lat/lng are bridged as `NSNumber?` so `nil` survives round-trips.
final class PendingPunch: NSManagedObject {
    @NSManaged var localId: UUID           // Primary key for deletion
    @NSManaged var isPunchIn: Bool
    @NSManaged var clientPunchTime: String // ISO-8601 device time at the moment of the tap
    @NSManaged var latitudeValue: NSNumber?
    @NSManaged var longitudeValue: NSNumber?
    @NSManaged var address: String?
    @NSManaged var photoPath: String?      // Absolute path to the proof selfie (uploaded on flush)
    @NSManaged var deviceId: String?
    @NSManaged var source: String
    @NSManaged var createdAt: Int64        // Unix epoch milliseconds — flush order (oldest first)
    @NSManaged var attemptCount: Int32
    @NSManaged var lastError: String?

    func toValue() -> PendingPunchValue {
        PendingPunchValue(
            id: localId,
            isPunchIn: isPunchIn,
            clientPunchTime: clientPunchTime,
            latitude: latitudeValue?.doubleValue,
            longitude: longitudeValue?.doubleValue,
            address: address,
            photoPath: photoPath,
            deviceId: deviceId,
            source: source,
            createdAt: createdAt
        )
    }
}

// MARK: - PendingPunchValue (Sendable snapshot for crossing concurrency boundaries)

struct PendingPunchValue: Sendable {
    let id: UUID
    let isPunchIn: Bool
    let clientPunchTime: String
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let photoPath: String?
    let deviceId: String?
    let source: String
    let createdAt: Int64
}

// MARK: - PendingPunchStore (programmatic CoreData stack)

/// Programmatic CoreData stack — no `.xcdatamodeld` file required — mirroring
/// `GeoTrackPersistence`. Kept as its own store so the offline-punch buffer is
/// isolated from the GeoTrack location buffer. All writes run on a background
/// context; reads return Sendable value types.
final class PendingPunchStore {
    static let shared = PendingPunchStore()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(
            name: "PendingPunch",
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
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("PendingPunch CoreData failed to load: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: Insert

    /// Persists a failed punch to the offline queue. The selfie bytes (if any) are
    /// copied to a stable file under Application Support so they survive until the
    /// queue flushes. Returns `true` when the row was written.
    @discardableResult
    func insert(
        isPunchIn: Bool,
        clientPunchTime: String,
        latitude: Double?,
        longitude: Double?,
        address: String?,
        photoData: Data?,
        deviceId: String?,
        source: String = "mobile",
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) async -> Bool {
        let persistedPhotoPath = photoData.flatMap { Self.persistPhoto($0) }
        let ctx = container.newBackgroundContext()
        do {
            try await ctx.perform {
                let entity = PendingPunch(context: ctx)
                entity.localId = UUID()
                entity.isPunchIn = isPunchIn
                entity.clientPunchTime = clientPunchTime
                entity.latitudeValue = latitude.map { NSNumber(value: $0) }
                entity.longitudeValue = longitude.map { NSNumber(value: $0) }
                entity.address = address
                entity.photoPath = persistedPhotoPath
                entity.deviceId = deviceId
                entity.source = source
                entity.createdAt = createdAt
                entity.attemptCount = 0
                entity.lastError = nil
                try ctx.save()
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: Fetch

    /// All queued punches, oldest first — punches flush in the order they were taken.
    func listAll() async -> [PendingPunchValue] {
        let ctx = container.newBackgroundContext()
        return (try? await ctx.perform {
            let request = NSFetchRequest<PendingPunch>(entityName: "PendingPunch")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try ctx.fetch(request).map { $0.toValue() }
        }) ?? []
    }

    func count() async -> Int {
        let ctx = container.newBackgroundContext()
        return (try? await ctx.perform {
            let request = NSFetchRequest<NSNumber>(entityName: "PendingPunch")
            request.resultType = .countResultType
            return try ctx.fetch(request).first?.intValue ?? 0
        }) ?? 0
    }

    // MARK: Delete / update

    /// Removes the row and its selfie file (used after a successful sync).
    func delete(id: UUID, deletePhoto: Bool = true) async {
        let ctx = container.newBackgroundContext()
        try? await ctx.perform {
            let request = NSFetchRequest<PendingPunch>(entityName: "PendingPunch")
            request.predicate = NSPredicate(format: "localId IN %@", [id] as CVarArg)
            let rows = try ctx.fetch(request)
            if deletePhoto {
                rows.forEach { Self.deletePhoto($0.photoPath) }
            }
            rows.forEach { ctx.delete($0) }
            if ctx.hasChanges { try ctx.save() }
        }
    }

    func bumpAttempt(id: UUID, error: String?) async {
        let ctx = container.newBackgroundContext()
        try? await ctx.perform {
            let request = NSFetchRequest<PendingPunch>(entityName: "PendingPunch")
            request.predicate = NSPredicate(format: "localId IN %@", [id] as CVarArg)
            for row in try ctx.fetch(request) {
                row.attemptCount += 1
                row.lastError = error
            }
            if ctx.hasChanges { try ctx.save() }
        }
    }

    // MARK: Photo files

    private static func photoDirectory() -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = base.appendingPathComponent("PunchQueue", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func persistPhoto(_ data: Data) -> String? {
        guard let dir = photoDirectory() else { return nil }
        let file = dir.appendingPathComponent("punch_\(Int64(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString).jpg")
        do {
            try data.write(to: file, options: .atomic)
            return file.path
        } catch {
            return nil
        }
    }

    private static func deletePhoto(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: Programmatic NSManagedObjectModel

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "PendingPunch"
        entity.managedObjectClassName = NSStringFromClass(PendingPunch.self)

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
            attr("localId",         type: .UUIDAttributeType),
            attr("isPunchIn",       type: .booleanAttributeType,   default: true),
            attr("clientPunchTime", type: .stringAttributeType,    default: ""),
            attr("latitudeValue",   type: .doubleAttributeType,    optional: true),
            attr("longitudeValue",  type: .doubleAttributeType,    optional: true),
            attr("address",         type: .stringAttributeType,    optional: true),
            attr("photoPath",       type: .stringAttributeType,    optional: true),
            attr("deviceId",        type: .stringAttributeType,    optional: true),
            attr("source",          type: .stringAttributeType,    default: "mobile"),
            attr("createdAt",       type: .integer64AttributeType, default: Int64(0)),
            attr("attemptCount",    type: .integer32AttributeType, default: Int32(0)),
            attr("lastError",       type: .stringAttributeType,    optional: true),
        ]

        model.entities = [entity]
        return model
    }
}

// MARK: - PunchTimestamp helper

enum PunchTimestamp {
    /// ISO-8601 device time WITH the local UTC offset (e.g. `2026-08-13T09:00:00.123+05:30`),
    /// matching Android's `HomeViewModel.isoNow()` so the backend records the real tap time.
    static func iso(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}

// MARK: - PendingPunchSyncCoordinator (flush / replay)

/// Flushes queued offline punches once connectivity returns. An `actor` so two
/// flushes can never overlap (the iOS analogue of Android's unique-work
/// `PunchSyncWorker` guarded by `ExistingWorkPolicy.KEEP`).
///
/// Each pending punch already carries the staff's REAL tap time
/// (`clientPunchTime`); the backend records that, so a punch taken offline at
/// 09:00 and synced at 09:20 still lands at 09:00. Replays oldest-first with the
/// original tap time, removes on success, and keeps the row on a network failure.
actor PendingPunchSyncCoordinator {
    static let shared = PendingPunchSyncCoordinator()

    private var isFlushing = false

    /// Replays the offline punch queue. Safe to call on every Home appearance —
    /// no-ops when the queue is empty or a flush is already running.
    func flush(token: String) async {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        let pending = await PendingPunchStore.shared.listAll()
        guard !pending.isEmpty else { return }

        for punch in pending {
            do {
                // Upload the selfie (best-effort — a punch may still land without it).
                var storageId: String?
                if let path = punch.photoPath,
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    storageId = try? await HRConvexAPIService.uploadPhoto(token: token, imageData: data)
                }

                if punch.isPunchIn {
                    _ = try await HRConvexAPIService.punchIn(
                        token: token,
                        latitude: punch.latitude,
                        longitude: punch.longitude,
                        address: punch.address,
                        source: punch.source,
                        photo: storageId,
                        deviceId: punch.deviceId,
                        clientPunchTime: punch.clientPunchTime
                    )
                } else {
                    try await HRConvexAPIService.punchOut(
                        token: token,
                        latitude: punch.latitude,
                        longitude: punch.longitude,
                        address: punch.address,
                        source: punch.source,
                        photo: storageId,
                        deviceId: punch.deviceId,
                        clientPunchTime: punch.clientPunchTime
                    )
                }
                // Landed — drop the row and its selfie file.
                await PendingPunchStore.shared.delete(id: punch.id)
            } catch is HRConvexAPIError {
                // Server was REACHED and rejected the punch (already-punched, blocked
                // location, HTTP 4xx/5xx, unauthorized). Retrying a rejection would
                // loop forever, and a duplicate-rejection means it already landed —
                // so clear the row (matches Android PunchSyncWorker). Keep the selfie
                // file only in case it's still referenced; harmless to leave.
                await PendingPunchStore.shared.delete(id: punch.id, deletePhoto: false)
            } catch {
                // Network / connectivity error — keep the row for the next flush.
                await PendingPunchStore.shared.bumpAttempt(id: punch.id, error: error.localizedDescription)
            }
        }
    }
}
