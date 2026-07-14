import Foundation

// MARK: - Tasks

struct ConvexTaskUpdate: Decodable, Identifiable, Equatable, Sendable {
    let _id: String?
    let comment: String?
    let progress: Int?
    let date: String?
    let todaysUpdate: String?
    let blocker: String?
    let tomorrowsPlan: String?
    let progressSnapshot: Int?
    let images: [TaskUpdateImage]?
    let updateType: String?
    let by: String?
    let byName: String?
    let createdBy: String?
    let at: String?
    let createdAt: String?
    let creationTime: Double?

    enum CodingKeys: String, CodingKey {
        case _id, comment, progress, date, todaysUpdate, blocker, tomorrowsPlan
        case progressSnapshot, images, updateType, by, byName, createdBy, at, createdAt
        case creationTime = "_creationTime"
    }

    var id: String { _id ?? at ?? createdAt ?? date ?? UUID().uuidString }

    var occurredAt: Date? {
        let value = at ?? createdAt
        guard let value else { return nil }
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFractional.date(from: value) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value)
    }

    var displayProgress: Int? { progressSnapshot ?? progress }
    var displayAuthor: String { createdBy?.taskNilIfBlank ?? byName?.taskNilIfBlank ?? by?.taskNilIfBlank ?? "Site Update" }
    var displayNotes: String? { todaysUpdate?.taskNilIfBlank ?? comment?.taskNilIfBlank }
}

struct ConvexTask: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let taskId: String?
    let name: String?
    let title: String?
    let taskName: String?
    let taskTitle: String?
    let description: String?
    let taskDescription: String?
    let workCategory: String?
    let status: String?
    let progress: Int?
    let priority: String?
    let dueDate: String?
    let endDate: String?
    let startDate: String?
    let actualStartDate: String?
    let actualEndDate: String?
    let duration: Int?
    let projectId: String?
    let projectName: String?
    let assignedToId: String?
    let assignedTo: String?
    let assignedToName: String?
    let staffAssignedTo: String?
    let assignedById: String?
    let assignedBy: String?
    let assignedByName: String?
    let achievedQuantity: Double?
    let totalQuantity: Double?
    let unit: String?
    let todaysUpdate: String?
    let blocker: String?
    let tomorrowsPlan: String?
    let createdAt: String?
    let creationTime: Double?
    let updatedAt: String?
    let completedAt: String?
    let updates: [ConvexTaskUpdate]?

    enum CodingKeys: String, CodingKey {
        case _id, taskId, name, title, taskName, taskTitle, description, taskDescription
        case workCategory, status, progress, priority, dueDate, endDate, startDate
        case actualStartDate, actualEndDate, duration, projectId, projectName
        case assignedToId, assignedTo, assignedToName, staffAssignedTo
        case assignedById, assignedBy, assignedByName, achievedQuantity, totalQuantity
        case unit, todaysUpdate, blocker, tomorrowsPlan, createdAt, updatedAt
        case completedAt, updates
        case creationTime = "_creationTime"
    }

    var id: String { _id }

    var displayTitle: String {
        name?.taskNilIfBlank ?? title?.taskNilIfBlank ?? taskName?.taskNilIfBlank ?? taskTitle?.taskNilIfBlank ?? "Untitled task"
    }

    var displayDescription: String? {
        description?.taskNilIfBlank ?? taskDescription?.taskNilIfBlank
    }

    var displayProject: String {
        projectName?.taskNilIfBlank ?? workCategory?.taskNilIfBlank ?? "Project"
    }

    var displayDueDate: String? {
        endDate?.taskNilIfBlank ?? dueDate?.taskNilIfBlank
    }

    var displayProgress: Int {
        if let p = progress { return max(0, min(100, p)) }
        switch normalizedStatus {
        case .completed: return 100
        case .inProgress: return 50
        default: return 0
        }
    }

    var normalizedStatus: TaskStatus {
        TaskStatus.from(status)
    }

    var assignedByDisplay: String? {
        assignedByName ?? assignedBy
    }

    var assignedToDisplay: String? {
        assignedToName ?? assignedTo
    }

    var isAssignedToCurrentStaff: Bool {
        staffAssignedTo?.taskNilIfBlank != nil
    }
}

struct DailyTaskManagerPayload: Equatable, Sendable {
    let tasks: [DailyTask]
    let teamIds: Set<String>
    let scope: String?
}

struct DailyTask: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let title: String?
    let taskName: String?
    let label: String?
    let priority: String?
    let description: String?
    let deadline: String?
    let assignedTo: String?
    let assignedBy: String?
    let assignedToName: String?
    let assignedByName: String?
    let taskCategory: String?
    let status: String?
    let module: String?
    let pendingExtensionRequest: Bool?
    let sourceReferenceType: String?
    let sourceReferenceId: String?
    let actionUrl: String?
    let creationTime: Double?

    enum CodingKeys: String, CodingKey {
        case _id, title, taskName, label, priority, description, deadline
        case assignedTo, assignedBy, assignedToName, assignedByName
        case taskCategory, status, module, pendingExtensionRequest
        case sourceReferenceType, sourceReferenceId, actionUrl
        case creationTime = "_creationTime"
    }

    var id: String { _id }

    var displayTitle: String {
        title?.taskNilIfBlank ?? taskName?.taskNilIfBlank ?? "Task"
    }

    var displaySubtitle: String? {
        if let taskName = taskName?.taskNilIfBlank, taskName != displayTitle {
            return taskName
        }
        return description?.taskNilIfBlank
    }

    var displayAssignedTo: String {
        assignedToName?.taskNilIfBlank ?? assignedTo?.taskNilIfBlank ?? "-"
    }
}

struct TaskResourceEntry: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let taskId: String?
    let resourceType: String?
    let itemName: String?
    let unit: String?
    let budgetQty: Double?
    let plannedQty: Double?
    let actualQty: Double?
    let rate: Double?
    let isLumpsum: Bool?
    let lumpsumAmount: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case taskId, resourceType, itemName, unit, budgetQty, plannedQty, actualQty, rate, isLumpsum, lumpsumAmount
    }
}

struct TaskUpdateImage: Decodable, Encodable, Equatable, Sendable {
    let storageId: String
    let url: String?
    let name: String?
}

enum TaskStatus: String, CaseIterable, Sendable {
    case pending
    case inProgress
    case completed
    case delayed

    static func from(_ raw: String?) -> TaskStatus {
        switch raw?.lowercased() {
        case "completed", "done", "closed": return .completed
        case "in_progress", "in-progress", "inprogress", "ongoing", "started": return .inProgress
        case "delayed", "blocked", "overdue": return .delayed
        default: return .pending
        }
    }

    var serverValue: String {
        switch self {
        case .pending: return "not-started"
        case .inProgress: return "in-progress"
        case .completed: return "completed"
        case .delayed: return "delayed"
        }
    }

    var label: String {
        switch self {
        case .pending: return "Not-started"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .delayed: return "Delayed"
        }
    }
}

enum TaskListFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case inProgress
    case pending
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .inProgress: return "In progress"
        case .pending: return "Pending"
        case .completed: return "Completed"
        }
    }

    func matches(_ task: ConvexTask) -> Bool {
        switch self {
        case .all: return true
        case .inProgress: return task.normalizedStatus == .inProgress
        case .pending: return task.normalizedStatus == .pending
        case .completed: return task.normalizedStatus == .completed
        }
    }
}

struct ConvexTaskSummary: Decodable, Equatable, Sendable {
    let total: Int?
    let notStarted: Int?
    let pending: Int?
    let inProgress: Int?
    let completed: Int?
    let delayed: Int?
    let overallPercent: Double?
    let overallProgress: Double?

    var totalCount: Int { total ?? 0 }
    var pendingCount: Int { notStarted ?? pending ?? 0 }
    var inProgressCount: Int { inProgress ?? 0 }
    var completedCount: Int { completed ?? 0 }
    var delayedCount: Int { delayed ?? 0 }

    var overallPercentValue: Double {
        if let p = overallPercent { return p }
        if let p = overallProgress { return p }
        guard totalCount > 0 else { return 0 }
        return (Double(completedCount) / Double(totalCount)) * 100
    }
}

private extension String {
    var taskNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
