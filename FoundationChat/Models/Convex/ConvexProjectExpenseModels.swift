import Foundation
import SwiftUI

struct ProjectSummary: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let description: String?
    let status: String?
    let progress: Int?
    let startDate: String?
    let endDate: String?
    let budget: Double?
    let location: String?
    let managerName: String?
    let staffManagerId: String?
    let projectType: String?
    let specialPaymentEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case name, description, status, progress, startDate, endDate, budget
        case location, managerName, staffManagerId, projectType, specialPaymentEnabled
    }

    init(
        id: String,
        name: String? = nil,
        description: String? = nil,
        status: String? = nil,
        progress: Int? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        budget: Double? = nil,
        location: String? = nil,
        managerName: String? = nil,
        staffManagerId: String? = nil,
        projectType: String? = nil,
        specialPaymentEnabled: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
        self.progress = progress
        self.startDate = startDate
        self.endDate = endDate
        self.budget = budget
        self.location = location
        self.managerName = managerName
        self.staffManagerId = staffManagerId
        self.projectType = projectType
        self.specialPaymentEnabled = specialPaymentEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        progress = try container.decodeIfPresent(Int.self, forKey: .progress)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        budget = try container.decodeIfPresent(Double.self, forKey: .budget)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        managerName = try container.decodeIfPresent(String.self, forKey: .managerName)
        staffManagerId = try container.decodeIfPresent(String.self, forKey: .staffManagerId)
        projectType = try container.decodeIfPresent(String.self, forKey: .projectType)
        specialPaymentEnabled = try container.decodeIfPresent(Bool.self, forKey: .specialPaymentEnabled)
    }

    var displayName: String { name?.projectNilIfBlank ?? "Untitled project" }
}

struct ProjectExpense: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let projectId: String?
    let category: String
    let amount: Double
    let date: String
    let paymentMethod: String?
    let notes: String?
    let receipts: [ExpenseReceipt]?
    let paid: Bool
    let paidAt: Double?
    let paidByStaffId: String?
    let createdByStaffId: String?
    let createdAt: Double?
    let updatedAt: Double?
    let creationTime: Double?
    let createdByName: String?
    let paidByName: String?
    let project: ProjectSummary?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case projectId, category, amount, date, paymentMethod, notes, receipts
        case paid, paidAt, paidByStaffId, createdByStaffId, createdAt, updatedAt
        case createdByName, paidByName, project
        case creationTime = "_creationTime"
    }
}

struct ExpenseReceipt: Codable, Hashable, Sendable {
    let storageId: String
    let url: String?
    let name: String?
}

struct ExpenseCategoryTotals: Decodable, Equatable, Sendable {
    let labour: Double
    let materials: Double
    let equipment: Double
    let other: Double

    static let zero = ExpenseCategoryTotals(labour: 0, materials: 0, equipment: 0, other: 0)

    enum CodingKeys: String, CodingKey {
        case labour, materials, equipment, other
    }

    init(labour: Double, materials: Double, equipment: Double, other: Double) {
        self.labour = labour
        self.materials = materials
        self.equipment = equipment
        self.other = other
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        labour = try container.decodeIfPresent(Double.self, forKey: .labour) ?? 0
        materials = try container.decodeIfPresent(Double.self, forKey: .materials) ?? 0
        equipment = try container.decodeIfPresent(Double.self, forKey: .equipment) ?? 0
        other = try container.decodeIfPresent(Double.self, forKey: .other) ?? 0
    }
}

struct ExpenseTotals: Decodable, Equatable, Sendable {
    let byCategory: ExpenseCategoryTotals
    let total: Double
    let paid: Double
    let pending: Double
    let count: Int

    static let zero = ExpenseTotals(byCategory: .zero, total: 0, paid: 0, pending: 0, count: 0)

    enum CodingKeys: String, CodingKey {
        case byCategory, total, paid, pending, count
    }

    init(byCategory: ExpenseCategoryTotals, total: Double, paid: Double, pending: Double, count: Int) {
        self.byCategory = byCategory
        self.total = total
        self.paid = paid
        self.pending = pending
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        byCategory = try container.decodeIfPresent(ExpenseCategoryTotals.self, forKey: .byCategory) ?? .zero
        total = try container.decodeIfPresent(Double.self, forKey: .total) ?? 0
        paid = try container.decodeIfPresent(Double.self, forKey: .paid) ?? 0
        pending = try container.decodeIfPresent(Double.self, forKey: .pending) ?? 0
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

enum ProjectExpenseCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case labour
    case materials
    case equipment
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .labour: return "Labour"
        case .materials: return "Materials"
        case .equipment: return "Equipments"
        case .other: return "Other"
        }
    }

    var queryValue: String? { self == .all ? nil : rawValue }

    var color: Color {
        switch self {
        case .all: return Color(hex: 0x0B61CA)
        case .labour: return Color(hex: 0x2563EB)
        case .materials: return Color(hex: 0xF97316)
        case .equipment: return Color(hex: 0x16A34A)
        case .other: return Color(hex: 0x71717A)
        }
    }

    static func from(_ raw: String) -> ProjectExpenseCategory {
        ProjectExpenseCategory(rawValue: raw.lowercased()) ?? .other
    }
}

private extension String {
    var projectNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
