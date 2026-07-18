import Foundation

struct DailyLogMaterial: Codable, Hashable, Sendable {
    let name: String
    let quantity: Double
    let unit: String?

    var stableId: String { "\(name)|\(quantity)|\(unit ?? "")" }
}

struct DailyLogEquipment: Codable, Hashable, Sendable {
    let name: String
    let hours: Double

    var stableId: String { "\(name)|\(hours)" }
}

struct DailyLogAttachment: Codable, Identifiable, Hashable, Sendable {
    let storageId: String
    let url: String?
    let type: String?
    let name: String?

    var id: String { storageId }
}

struct DailyLogEntry: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let date: String?
    let weather: String?
    let siteConditions: String?
    let workSummary: String?
    let labourCount: Int?
    let labourHours: Double?
    let issuesEncountered: String?
    let safetyObservations: String?
    let materialsUsed: [DailyLogMaterial]?
    let equipmentUsed: [DailyLogEquipment]?
    let supervisorName: String?
    let createdBy: String?
    let projectId: String?
    let projectName: String?
    let attachments: [DailyLogAttachment]?

    private enum CodingKeys: String, CodingKey {
        case _id
        case plainId = "id"
        case date, weather, siteConditions, workSummary, labourCount, labourHours
        case issuesEncountered, safetyObservations, materialsUsed, equipmentUsed
        case supervisorName, createdBy, projectId, projectName, attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: ._id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        date = try container.decodeIfPresent(String.self, forKey: .date)
        weather = try container.decodeIfPresent(String.self, forKey: .weather)
        siteConditions = try container.decodeIfPresent(String.self, forKey: .siteConditions)
        workSummary = try container.decodeIfPresent(String.self, forKey: .workSummary)
        labourCount = try container.decodeIfPresent(Int.self, forKey: .labourCount)
        labourHours = try container.decodeIfPresent(Double.self, forKey: .labourHours)
        issuesEncountered = try container.decodeIfPresent(String.self, forKey: .issuesEncountered)
        safetyObservations = try container.decodeIfPresent(String.self, forKey: .safetyObservations)
        materialsUsed = try container.decodeIfPresent([DailyLogMaterial].self, forKey: .materialsUsed)
        equipmentUsed = try container.decodeIfPresent([DailyLogEquipment].self, forKey: .equipmentUsed)
        supervisorName = try container.decodeIfPresent(String.self, forKey: .supervisorName)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        attachments = try container.decodeIfPresent([DailyLogAttachment].self, forKey: .attachments)
    }
}

struct DailyLogMaterialCatalogItem: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let unit: String?
    let category: String?
    let itemCode: String?
    let brand: String?

    private enum CodingKeys: String, CodingKey {
        case _id
        case plainId = "id"
        case name, unit, category, itemCode, brand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: ._id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        itemCode = try container.decodeIfPresent(String.self, forKey: .itemCode)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
    }

    var displayName: String {
        name?.nonBlank ?? "Material"
    }

    var subtitle: String {
        [category?.nonBlank, unit?.nonBlank, brand?.nonBlank]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct DprRecipient: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let phone: String?
    let normalizedPhone: String?
    let isActive: Bool
    let staffId: String?
    let projectId: String?
    let projectName: String?

    private enum CodingKeys: String, CodingKey {
        case _id
        case plainId = "id"
        case name, phone, normalizedPhone, isActive, staffId, projectId, projectName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: ._id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        normalizedPhone = try container.decodeIfPresent(String.self, forKey: .normalizedPhone)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        staffId = try container.decodeIfPresent(String.self, forKey: .staffId)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
    }
}

struct DprReport: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let date: String?
    let status: String?
    let sentCount: Int?
    let failedCount: Int?
    let taskUpdateCount: Int?
    let pdfUrl: String?
    let projectId: String?
    let projectName: String?

    private enum CodingKeys: String, CodingKey {
        case _id
        case plainId = "id"
        case date, status, sentCount, failedCount, taskUpdateCount, pdfUrl, projectId, projectName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: ._id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        date = try container.decodeIfPresent(String.self, forKey: .date)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        sentCount = try container.decodeIfPresent(Int.self, forKey: .sentCount)
        failedCount = try container.decodeIfPresent(Int.self, forKey: .failedCount)
        taskUpdateCount = try container.decodeIfPresent(Int.self, forKey: .taskUpdateCount)
        pdfUrl = try container.decodeIfPresent(String.self, forKey: .pdfUrl)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
    }
}

struct DailyLogUploadedMedia: Identifiable, Hashable {
    let id = UUID()
    let data: Data
    let contentType: String
    let type: String
    let name: String
}
