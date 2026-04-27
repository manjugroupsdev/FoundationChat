import Foundation

// MARK: - Tasks

struct ConvexTaskUpdate: Decodable, Identifiable, Equatable, Sendable {
    let _id: String?
    let comment: String?
    let progress: Int?
    let updateType: String?
    let by: String?
    let byName: String?
    let at: String?
    let createdAt: String?

    var id: String { _id ?? at ?? createdAt ?? UUID().uuidString }

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
}

struct ConvexTask: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let taskId: String?
    let title: String?
    let taskName: String?
    let taskTitle: String?
    let description: String?
    let taskDescription: String?
    let status: String?
    let progress: Int?
    let priority: String?
    let dueDate: String?
    let startDate: String?
    let projectId: String?
    let projectName: String?
    let assignedToId: String?
    let assignedTo: String?
    let assignedToName: String?
    let assignedById: String?
    let assignedBy: String?
    let assignedByName: String?
    let createdAt: String?
    let updatedAt: String?
    let completedAt: String?
    let updates: [ConvexTaskUpdate]?

    var id: String { _id }

    var displayTitle: String {
        title ?? taskName ?? taskTitle ?? "Untitled Task"
    }

    var displayDescription: String? {
        description ?? taskDescription
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
}

enum TaskStatus: String, CaseIterable, Sendable {
    case pending
    case inProgress
    case completed

    static func from(_ raw: String?) -> TaskStatus {
        switch raw?.lowercased() {
        case "completed", "done", "closed": return .completed
        case "in_progress", "in-progress", "inprogress", "ongoing", "started": return .inProgress
        default: return .pending
        }
    }

    var serverValue: String {
        switch self {
        case .pending: return "pending"
        case .inProgress: return "in_progress"
        case .completed: return "completed"
        }
    }

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }
}

enum TaskListFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case inProgress
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }

    func matches(_ task: ConvexTask) -> Bool {
        switch self {
        case .all: return true
        case .inProgress: return task.normalizedStatus == .inProgress
        case .completed: return task.normalizedStatus == .completed
        }
    }
}

struct ConvexTaskSummary: Decodable, Equatable, Sendable {
    let total: Int?
    let pending: Int?
    let inProgress: Int?
    let completed: Int?
    let overallPercent: Double?
    let overallProgress: Double?

    var totalCount: Int { total ?? 0 }
    var pendingCount: Int { pending ?? 0 }
    var inProgressCount: Int { inProgress ?? 0 }
    var completedCount: Int { completed ?? 0 }

    var overallPercentValue: Double {
        if let p = overallPercent { return p }
        if let p = overallProgress { return p }
        guard totalCount > 0 else { return 0 }
        return (Double(completedCount) / Double(totalCount)) * 100
    }
}
