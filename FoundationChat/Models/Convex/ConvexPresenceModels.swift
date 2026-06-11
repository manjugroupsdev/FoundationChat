import Foundation

struct UserPresenceInfo: Decodable, Identifiable, Equatable, Sendable {
    let stackUserId: String
    let status: String
    let customStatusText: String?
    let customStatusEmoji: String?
    let lastHeartbeatAt: Double

    var id: String { stackUserId }

    var presenceStatus: PresenceStatus {
        PresenceStatus(rawValue: status) ?? .offline
    }

    private enum CodingKeys: String, CodingKey {
        case stackUserId
        case staffId
        case status
        case customStatusText
        case customStatusEmoji
        case lastHeartbeatAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stackUserId = try container.decodeIfPresent(String.self, forKey: .stackUserId)
            ?? container.decodeIfPresent(String.self, forKey: .staffId)
            ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "offline"
        customStatusText = try container.decodeIfPresent(String.self, forKey: .customStatusText)
        customStatusEmoji = try container.decodeIfPresent(String.self, forKey: .customStatusEmoji)
        lastHeartbeatAt = try container.decodeIfPresent(Double.self, forKey: .lastHeartbeatAt) ?? 0
    }

    init(
        stackUserId: String,
        status: String,
        customStatusText: String? = nil,
        customStatusEmoji: String? = nil,
        lastHeartbeatAt: Double = 0
    ) {
        self.stackUserId = stackUserId
        self.status = status
        self.customStatusText = customStatusText
        self.customStatusEmoji = customStatusEmoji
        self.lastHeartbeatAt = lastHeartbeatAt
    }
}

enum PresenceStatus: String, Sendable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case online
    case away
    case busy
    case offline

    var displayName: String {
        switch self {
        case .online: return "Online"
        case .away: return "Away"
        case .busy: return "Busy"
        case .offline: return "Offline"
        }
    }

    var systemImage: String {
        switch self {
        case .online: return "circle.fill"
        case .away: return "moon.fill"
        case .busy: return "minus.circle.fill"
        case .offline: return "circle"
        }
    }
}

struct HeartbeatResult: Decodable, Sendable {
    let status: String
}

struct SetStatusResult: Decodable, Sendable {
    let status: String
}

struct ClearStatusResult: Decodable, Sendable {
    let cleared: Bool
}
