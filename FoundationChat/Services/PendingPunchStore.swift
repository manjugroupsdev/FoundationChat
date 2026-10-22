import CoreData
import Foundation
import Network
import UserNotifications

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
            createdAt: createdAt,
            attemptCount: Int(attemptCount)
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
    /// Failed flush attempts so far; bounds how long a selfie upload is retried.
    let attemptCount: Int
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
        await save(
            isPunchIn: isPunchIn,
            clientPunchTime: clientPunchTime,
            latitude: latitude,
            longitude: longitude,
            address: address,
            photoData: photoData,
            deviceId: deviceId,
            source: source,
            createdAt: createdAt
        ) != nil
    }

    /// Same as `insert`, returning the saved row's id (nil if it couldn't be saved).
    func save(
        isPunchIn: Bool,
        clientPunchTime: String,
        latitude: Double?,
        longitude: Double?,
        address: String?,
        photoData: Data?,
        deviceId: String?,
        source: String = "mobile",
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) async -> UUID? {
        let persistedPhotoPath = photoData.flatMap { Self.persistPhoto($0) }
        let ctx = container.newBackgroundContext()
        let rowId = UUID()
        do {
            try await ctx.perform {
                let entity = PendingPunch(context: ctx)
                entity.localId = rowId
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
            return rowId
        } catch {
            return nil
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

/// What happened to one saved punch when it was sent.
enum PunchSyncOutcome: Sendable {
    /// The server recorded it.
    case recorded(attendanceId: String?)
    /// The server refused it (at home, already clocked in…). Row removed.
    case rejected(String)
    /// Not sent yet (offline, outage, selfie still uploading). Row kept.
    case deferred
}

/// Sends saved attendance punches. The ONE place that does it: the punch
/// screen calls `sendNow` straight after saving (so an online staff member
/// still gets the server's real answer), and app open, Home and the network
/// monitor call `flush` (Android `PunchReplayer` parity).
///
/// Punches go oldest-first and a flush stops at the first one that can't be
/// sent yet, so a clock-out never goes ahead of the clock-in it closes.
/// Flushes run one after another, so the same row is never sent twice at once.
actor PendingPunchSyncCoordinator {
    /// Flushes before a punch is recorded without its selfie.
    static let maxSelfieUploadAttempts = 20

    static let shared = PendingPunchSyncCoordinator()

    /// The flush that runs last; the next one waits for it.
    private var tail: Task<[UUID: PunchSyncOutcome], Never>?

    /// Punches a screen is waiting on. The screen reports their result and runs
    /// its own follow-up, so a flush neither notifies nor starts GeoTrack for them.
    private var claimedIds: Set<UUID> = []
    /// Outcomes of claimed punches, picked up by `sendNow`.
    private var screenOutcomes: [UUID: PunchSyncOutcome] = [:]
    /// Claimed punches whose send finished without reaching them.
    private var finishedSends: Set<UUID> = []

    private var pathMonitor: NWPathMonitor?
    private var lastPathSatisfied = true

    /// Sends the saved punches. Safe to call on every Home appearance; it waits
    /// for a flush already running and then sends whatever is left.
    @discardableResult
    func flush(token: String) async -> [UUID: PunchSyncOutcome] {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        let previous = tail
        let task = Task { () -> [UUID: PunchSyncOutcome] in
            _ = await previous?.value
            return await self.runFlush(token: token)
        }
        tail = task
        return await task.value
    }

    /// Sends the punch the screen just saved, waiting at most `timeout` seconds.
    /// Returns its outcome, or nil when there was no answer in time; the send
    /// keeps going and the flush does the follow-up itself, so a punch that
    /// lands late still starts or stops tracking.
    func sendNow(token: String, id: UUID, timeout: TimeInterval) async -> PunchSyncOutcome? {
        claimedIds.insert(id)
        Task {
            _ = await self.flush(token: token)
            if self.claimedIds.contains(id) { self.finishedSends.insert(id) }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let outcome = screenOutcomes[id] {
                release(id)
                return outcome
            }
            if finishedSends.contains(id) { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let late = screenOutcomes[id]
        release(id)
        return late
    }

    /// Sends saved punches whenever the network comes back while the app runs.
    func startMonitoringConnectivity() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            Task { await PendingPunchSyncCoordinator.shared.pathChanged(satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "attendance.punch.pathmonitor", qos: .utility))
    }

    private func pathChanged(satisfied: Bool) async {
        let cameBack = satisfied && !lastPathSatisfied
        lastPathSatisfied = satisfied
        guard cameBack else { return }
        let token = await MainActor.run { GeoTrackAPIService.shared.tokenProvider?() }
        guard let token, !token.isEmpty else { return }
        await flush(token: token)
    }

    private func release(_ id: UUID) {
        claimedIds.remove(id)
        screenOutcomes[id] = nil
        finishedSends.remove(id)
    }

    /// True while a screen is waiting on `id`; stores its outcome for it.
    private func keepForScreen(_ id: UUID, _ outcome: PunchSyncOutcome) -> Bool {
        guard claimedIds.contains(id) else { return false }
        screenOutcomes[id] = outcome
        return true
    }

    private func runFlush(token: String) async -> [UUID: PunchSyncOutcome] {
        let pending = await PendingPunchStore.shared.listAll()
        var outcomes: [UUID: PunchSyncOutcome] = [:]
        for punch in pending {
            let outcome = await send(punch, token: token)
            outcomes[punch.id] = outcome
            switch outcome {
            case .deferred:
                _ = keepForScreen(punch.id, outcome)
                return outcomes
            case .rejected(let message):
                await PendingPunchStore.shared.delete(id: punch.id)
                if !keepForScreen(punch.id, outcome) {
                    notifyRejected(punch, message: message)
                }
            case .recorded(let attendanceId):
                // Landed — drop the row and its selfie file.
                await PendingPunchStore.shared.delete(id: punch.id)
                if !keepForScreen(punch.id, outcome) {
                    await GeoTrackBootstrapCoordinator.shared.sync(
                        reason: punch.isPunchIn ? "offline-attendance-punch-in" : "offline-attendance-punch-out",
                        force: true,
                        contextId: attendanceId,
                        occurredAt: punch.createdAt,
                        lat: punch.latitude,
                        lng: punch.longitude,
                        attendanceOpen: punch.isPunchIn
                    )
                }
            }
        }
        return outcomes
    }

    private func send(_ punch: PendingPunchValue, token: String) async -> PunchSyncOutcome {
        do {
            // The selfie is part of the punch. Keep the row and retry rather
            // than recording it without the photo; only after many failed
            // attempts is it recorded without it, so the attendance itself is
            // never lost. (Android parity.)
            var storageId: String?
            if let path = punch.photoPath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                storageId = try? await HRConvexAPIService.uploadPhoto(
                    token: token,
                    imageData: data,
                    fileName: "attendance-photo.jpg",
                    purpose: .attendancePhoto
                )
                if storageId?.isEmpty != false,
                   punch.attemptCount < Self.maxSelfieUploadAttempts {
                    await PendingPunchStore.shared.bumpAttempt(id: punch.id, error: "Selfie upload failed")
                    return .deferred
                }
            }
            if punch.isPunchIn {
                let attendanceId = try await HRConvexAPIService.punchIn(
                    token: token,
                    latitude: punch.latitude,
                    longitude: punch.longitude,
                    address: punch.address,
                    source: punch.source,
                    photo: storageId,
                    deviceId: punch.deviceId,
                    clientPunchTime: punch.clientPunchTime
                )
                return .recorded(attendanceId: attendanceId)
            }
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
            return .recorded(attendanceId: nil)
        } catch let error as HRConvexAPIError where !error.isRetriableAttendanceFailure {
            // The server decided (at home, already clocked in…). Retrying it
            // would loop forever.
            return .rejected(error.localizedDescription)
        } catch {
            // Offline, outage or expired session — keep the row for later.
            await PendingPunchStore.shared.bumpAttempt(id: punch.id, error: error.localizedDescription)
            return .deferred
        }
    }

    /// Tells the staff a saved punch was refused, since the screen already said
    /// "saved". A refusal saying the punch is already there means an earlier
    /// attempt landed, so that one stays quiet.
    private func notifyRejected(_ punch: PendingPunchValue, message: String) {
        if message.range(of: "already", options: .caseInsensitive) != nil { return }
        let content = UNMutableNotificationContent()
        let what = punch.isPunchIn ? "Clock-in" : "Clock-out"
        let date = Date(timeIntervalSince1970: TimeInterval(punch.createdAt) / 1_000)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        content.title = "\(what) at \(formatter.string(from: date)) was not recorded"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "attendance-punch-rejected-\(punch.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
