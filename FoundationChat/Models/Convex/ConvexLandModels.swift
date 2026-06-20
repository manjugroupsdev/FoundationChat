import Foundation

struct LandInspection: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let referenceNo: String?
    let totalArea: Double?
    let areaUnit: String?
    let propertyName: String?
    let ownerName: String?
    let location: String?
    let scheduledDate: String?
    let village: String?
    let taluk: String?
    let district: String?
    let locality: String?
    let city: String?
    let fullAddress: String?
    let pincode: String?
    let surveyNo: String?
    let propertyType: String?
    let status: String?
    let derivedInspectionStatus: String?
    let inspectionAcceptanceStatus: String?
    let reportId: String?
    let vpInspectionStatus: String?
    let inspectionDetails: String?
    let competitorDetails: String?
    let amenityDetails: String?
    let targetDetails: String?
    let notes: String?
    let exactLocation: String?
    let landmark: String?
    let latLong: String?
    let population: String?
    let roadType: [String]?
    let accessibilityWidth: String?
    let accessibilityWidthUnit: String?
    let electricity: String?
    let eConnectionToLand: String?
    let telecom: String?
    let railwayStationDistance: String?
    let busStopDistance: String?
    let schoolEntries: [LandAreaEntry]?
    let collegeEntries: [LandAreaEntry]?
    let hospitalEntries: [LandAreaEntry]?
    let mallEntries: [LandAreaEntry]?
    let marketEntries: [LandAreaEntry]?
    let presentDemand: [String]?
    let futureDemand: [String]?
    let targetClients: [String]?
    let landlordPrice: Double?
    let landlordPriceUnit: String?
    let recommendationPrice: Double?
    let recommendationPriceUnit: String?
    let priceCanSell: Double?
    let priceCanSellUnit: String?
    let conclusion: String?
    let competitors: [LandCompetitorEntry]?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case propertyId, referenceNo, totalArea, areaUnit
        case propertyName, ownerName, customerName, location, scheduledDate, inspectionDate
        case village, taluk, district, locality, city, fullAddress, pincode, surveyNo, propertyType
        case status, derivedInspectionStatus, inspectionAcceptanceStatus, reportId, vpInspectionStatus
        case inspectionDetails, competitorDetails, amenityDetails, targetDetails
        case exactLocation, landmark, latLong, mapLink, googleMapLink, population, roadType
        case accessibilityWidth, accessibilityWidthUnit, electricity, eConnectionToLand, telecom
        case railwayStationDistance, busStopDistance
        case schoolEntries, collegeEntries, hospitalEntries, mallEntries, marketEntries
        case presentDemand, futureDemand, targetClients
        case landlordPrice, landlordPriceUnit, recommendationPrice, recommendationPriceUnit
        case priceCanSell, priceCanSellUnit, conclusion, competitors
        case notes, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .propertyId)
            ?? UUID().uuidString
        referenceNo = try container.decodeIfPresent(String.self, forKey: .referenceNo)
        totalArea = try container.decodeIfPresent(Double.self, forKey: .totalArea)
        areaUnit = try container.decodeIfPresent(String.self, forKey: .areaUnit)
        propertyName = try container.decodeIfPresent(String.self, forKey: .propertyName)
            ?? container.decodeIfPresent(String.self, forKey: .referenceNo)
        ownerName = try container.decodeIfPresent(String.self, forKey: .ownerName)
            ?? container.decodeIfPresent(String.self, forKey: .customerName)
        location = try container.decodeIfPresent(String.self, forKey: .location)
            ?? container.decodeIfPresent(String.self, forKey: .fullAddress)
            ?? [try container.decodeIfPresent(String.self, forKey: .village),
                try container.decodeIfPresent(String.self, forKey: .taluk),
                try container.decodeIfPresent(String.self, forKey: .district)]
                .compactMap { $0?.landNilIfBlank }
                .joined(separator: ", ")
                .landNilIfBlank
        scheduledDate = try container.decodeIfPresent(String.self, forKey: .scheduledDate)
            ?? container.decodeIfPresent(String.self, forKey: .inspectionDate)
        village = try container.decodeIfPresent(String.self, forKey: .village)
        taluk = try container.decodeIfPresent(String.self, forKey: .taluk)
        district = try container.decodeIfPresent(String.self, forKey: .district)
        locality = try container.decodeIfPresent(String.self, forKey: .locality)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        fullAddress = try container.decodeIfPresent(String.self, forKey: .fullAddress)
        pincode = try container.decodeIfPresent(String.self, forKey: .pincode)
        surveyNo = try container.decodeIfPresent(String.self, forKey: .surveyNo)
        propertyType = try container.decodeIfPresent(String.self, forKey: .propertyType)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        derivedInspectionStatus = try container.decodeIfPresent(String.self, forKey: .derivedInspectionStatus)
        inspectionAcceptanceStatus = try container.decodeIfPresent(String.self, forKey: .inspectionAcceptanceStatus)
        reportId = try container.decodeIfPresent(String.self, forKey: .reportId)
        vpInspectionStatus = try container.decodeIfPresent(String.self, forKey: .vpInspectionStatus)
        inspectionDetails = try container.decodeIfPresent(String.self, forKey: .inspectionDetails)
        competitorDetails = try container.decodeIfPresent(String.self, forKey: .competitorDetails)
        amenityDetails = try container.decodeIfPresent(String.self, forKey: .amenityDetails)
        targetDetails = try container.decodeIfPresent(String.self, forKey: .targetDetails)
        exactLocation = try container.decodeIfPresent(String.self, forKey: .exactLocation)
        landmark = try container.decodeIfPresent(String.self, forKey: .landmark)
        latLong = try container.decodeIfPresent(String.self, forKey: .latLong)
            ?? container.decodeIfPresent(String.self, forKey: .mapLink)
            ?? container.decodeIfPresent(String.self, forKey: .googleMapLink)
        population = try container.decodeIfPresent(String.self, forKey: .population)
        roadType = try container.decodeStringArrayIfPresent(forKey: .roadType)
        accessibilityWidth = try container.decodeIfPresent(String.self, forKey: .accessibilityWidth)
        accessibilityWidthUnit = try container.decodeIfPresent(String.self, forKey: .accessibilityWidthUnit)
        electricity = try container.decodeIfPresent(String.self, forKey: .electricity)
        eConnectionToLand = try container.decodeIfPresent(String.self, forKey: .eConnectionToLand)
        telecom = try container.decodeIfPresent(String.self, forKey: .telecom)
        railwayStationDistance = try container.decodeIfPresent(String.self, forKey: .railwayStationDistance)
        busStopDistance = try container.decodeIfPresent(String.self, forKey: .busStopDistance)
        schoolEntries = try container.decodeIfPresent([LandAreaEntry].self, forKey: .schoolEntries)
        collegeEntries = try container.decodeIfPresent([LandAreaEntry].self, forKey: .collegeEntries)
        hospitalEntries = try container.decodeIfPresent([LandAreaEntry].self, forKey: .hospitalEntries)
        mallEntries = try container.decodeIfPresent([LandAreaEntry].self, forKey: .mallEntries)
        marketEntries = try container.decodeIfPresent([LandAreaEntry].self, forKey: .marketEntries)
        presentDemand = try container.decodeStringArrayIfPresent(forKey: .presentDemand)
        futureDemand = try container.decodeStringArrayIfPresent(forKey: .futureDemand)
        targetClients = try container.decodeStringArrayIfPresent(forKey: .targetClients)
        landlordPrice = try container.decodeLossyDoubleIfPresent(forKey: .landlordPrice)
        landlordPriceUnit = try container.decodeIfPresent(String.self, forKey: .landlordPriceUnit)
        recommendationPrice = try container.decodeLossyDoubleIfPresent(forKey: .recommendationPrice)
        recommendationPriceUnit = try container.decodeIfPresent(String.self, forKey: .recommendationPriceUnit)
        priceCanSell = try container.decodeLossyDoubleIfPresent(forKey: .priceCanSell)
        priceCanSellUnit = try container.decodeIfPresent(String.self, forKey: .priceCanSellUnit)
        conclusion = try container.decodeIfPresent(String.self, forKey: .conclusion)
        competitors = try container.decodeIfPresent([LandCompetitorEntry].self, forKey: .competitors)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var title: String {
        propertyName?.landNilIfBlank ?? referenceNo?.landNilIfBlank ?? ownerName?.landNilIfBlank ?? "Land Inspection"
    }

    var subtitle: String {
        [location, ownerName]
            .compactMap { $0?.landNilIfBlank }
            .joined(separator: " · ")
    }

    var displayStatus: String {
        (derivedInspectionStatus ?? status)?.landNilIfBlank?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Not Started"
    }

    var isVPApproved: Bool {
        let vpStatus = vpInspectionStatus?.lowercased().replacingOccurrences(of: "_", with: " ")
        if let vpStatus {
            return vpStatus.contains("approved") || vpStatus.contains("accepted") || vpStatus == "vp approved"
        }
        return [inspectionAcceptanceStatus, derivedInspectionStatus, status]
            .compactMap { $0?.lowercased().replacingOccurrences(of: "_", with: " ") }
            .contains { value in
                value.contains("approved by vp")
                    || value.contains("vp approved")
                    || (value.contains("vp") && value.contains("approved"))
            }
    }
}

private extension KeyedDecodingContainer {
    func decodeStringArrayIfPresent(forKey key: Key) throws -> [String]? {
        if let values = try decodeIfPresent([String].self, forKey: key) {
            return values.compactMap(\.landNilIfBlank).nilIfEmpty
        }
        if let value = try decodeIfPresent(String.self, forKey: key)?.landNilIfBlank {
            return value
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .nilIfEmpty ?? [value]
        }
        return nil
    }

    func decodeLossyDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try decodeIfPresent(String.self, forKey: key)?.landNilIfBlank {
            return Double(value)
        }
        return nil
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

struct LandAreaEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String = ""
    var distance: String = ""

    enum CodingKeys: String, CodingKey { case name, distance }
}

struct LandCompetitorEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var promoterName: String = ""
    var projectName: String = ""
    var location: String = ""
    var latLong: String = ""
    var extentUnits: String = ""
    var approvalType: String = ""
    var amenities: String = ""
    var currentStage: String = ""
    var distanceFromProject: String = ""
    var distanceFromBusStand: String = ""
    var distanceFromRailway: String = ""
    var actualPrice: Double?
    var actualPriceUnit: String = "sqft"
    var finalPrice: Double?
    var finalPriceUnit: String = "sqft"

    enum CodingKeys: String, CodingKey {
        case promoterName, projectName, location, latLong, extentUnits, approvalType, amenities
        case currentStage, distanceFromProject, distanceFromBusStand, distanceFromRailway
        case actualPrice, actualPriceUnit, finalPrice, finalPriceUnit
    }
}

struct SaveLandInspectionRequest: Encodable {
    let id: String?
    let propertyId: String?
    let propertyName: String
    let ownerName: String?
    let location: String?
    let scheduledDate: String
    let inspectionDetails: String
    let competitorDetails: String?
    let amenityDetails: String?
    let targetDetails: String?
    let notes: String?
    let customerName: String?
    let surveyNo: String?
    let siteLocation: String?
    let exactLocation: String?
    let landmark: String?
    let latLong: String?
    let population: String?
    let roadType: [String]?
    let accessibilityWidth: String?
    let accessibilityWidthUnit: String?
    let electricity: String?
    let eConnectionToLand: String?
    let telecom: String?
    let railwayStationDistance: String?
    let busStopDistance: String?
    let schoolExists: Bool?
    let schoolEntries: [LandAreaEntry]?
    let collegeExists: Bool?
    let collegeEntries: [LandAreaEntry]?
    let hospitalExists: Bool?
    let hospitalEntries: [LandAreaEntry]?
    let mallExists: Bool?
    let mallEntries: [LandAreaEntry]?
    let marketExists: Bool?
    let marketEntries: [LandAreaEntry]?
    let presentDemand: [String]?
    let futureDemand: [String]?
    let targetClients: [String]?
    let landlordPrice: Double?
    let landlordPriceUnit: String?
    let recommendationPrice: Double?
    let recommendationPriceUnit: String?
    let priceCanSell: Double?
    let priceCanSellUnit: String?
    let conclusion: String?
    let competitors: [LandCompetitorEntry]?
}

struct RescheduleLandInspectionRequest: Encodable {
    let id: String
    let scheduledDate: String
}

struct LandQueryLog: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let propertyId: String?
    let queryIndex: Int?
    let referenceNo: String?
    let title: String?
    let queryNo: String?
    let propertyName: String?
    let status: String?
    let priority: String?
    let description: String?
    let remarks: String?
    let resolved: Bool?
    let createdOn: String?
    let latestUpdate: String?
    let updates: [LandQueryUpdate]?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case propertyId, queryIndex, referenceNo, title, query, queryNo, propertyName, status, priority, description
        case remarks, resolved, createdOn, latestUpdate, updates, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        propertyId = try container.decodeIfPresent(String.self, forKey: .propertyId)
        queryIndex = try container.decodeIfPresent(Int.self, forKey: .queryIndex)
        referenceNo = try container.decodeIfPresent(String.self, forKey: .referenceNo)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .query)
        queryNo = try container.decodeIfPresent(String.self, forKey: .queryNo)
        propertyName = try container.decodeIfPresent(String.self, forKey: .propertyName)
            ?? container.decodeIfPresent(String.self, forKey: .referenceNo)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .referenceNo)
        remarks = try container.decodeIfPresent(String.self, forKey: .remarks)
        resolved = try container.decodeIfPresent(Bool.self, forKey: .resolved)
        createdOn = try container.decodeIfPresent(String.self, forKey: .createdOn)
        latestUpdate = try container.decodeIfPresent(String.self, forKey: .latestUpdate)
        updates = try container.decodeIfPresent([LandQueryUpdate].self, forKey: .updates)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? [propertyId, queryIndex.map(String.init)].compactMap { $0 }.joined(separator: "-")
            .landNilIfBlank
            ?? UUID().uuidString
    }

    var displayTitle: String {
        title?.landNilIfBlank ?? queryNo?.landNilIfBlank ?? "Query"
    }

    var displayStatus: String {
        if resolved == true { return "Completed" }
        return status?.landNilIfBlank?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Pending"
    }

    var rawDate: String? {
        let raw = createdOn ?? createdAt ?? updatedAt
        guard let raw else { return nil }
        return String(raw.prefix(10)).landNilIfBlank
    }
}

struct LandQueryUpdate: Decodable, Identifiable, Hashable, Sendable {
    let rawId: String?
    let message: String?
    let status: String?
    let byName: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case rawId = "_id"
        case message, status, byName, createdAt
    }

    var id: String { rawId ?? "\(createdAt ?? "")|\(message ?? "")" }
}

struct LandQueryUpdateRequest: Encodable, Sendable {
    let propertyId: String
    let queryIndex: Int
    let remarks: String?
    let resolved: Bool?
}

extension String {
    var landNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
