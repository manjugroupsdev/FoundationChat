import Foundation
import CoreGraphics

// MARK: - Loans

struct ConvexLoanData: Decodable, Identifiable, Equatable, Sendable {
    let id: String?
    let loanId: String?
    let staffId: String?
    let staffName: String?
    let employeeId: String?
    let principalAmount: Double?
    let loanAmount: Double?
    let annualInterestRate: Double?
    let interestType: String?
    let disbursedDate: String?
    let repaymentStartMonth: String?
    let repaymentEndMonth: String?
    let monthlyDeduction: Double?
    let totalRepaid: Double?
    let remainingBalance: Double?
    let status: String?
    let purpose: String?
    let notes: String?
    let approvalStatus: String?
    let repayments: [ConvexLoanRepaymentData]?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case loanId, staffId, staffName, employeeId, principalAmount, loanAmount
        case annualInterestRate, interestType, disbursedDate, repaymentStartMonth
        case repaymentEndMonth, monthlyDeduction, totalRepaid, remainingBalance
        case status, purpose, notes, approvalStatus, repayments
    }
}

struct ConvexLoanRepaymentData: Decodable, Identifiable, Equatable, Sendable {
    let id: String?
    let loanId: String?
    let staffId: String?
    let month: String?
    let amount: Double?
    let mode: String?
    let notes: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case loanId, staffId, month, amount, mode, notes, createdAt
    }
}

enum AppLoanType: String, Sendable {
    case home
    case education
    case other
}

enum AppLoanStatus: String, Sendable {
    case active
    case pending
    case repaid
}

enum AppRepaymentStatus: String, Sendable {
    case paid
    case upcoming
    case overdue
}

struct AppRepayment: Identifiable, Equatable, Sendable {
    let id = UUID()
    let emiIndex: Int
    let dueDate: Date?
    let amount: Int
    let status: AppRepaymentStatus
    let paidVia: String?
    let onTime: Bool
}

struct AppLoan: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let loanId: String
    let type: AppLoanType
    let status: AppLoanStatus
    let outstandingBalance: Int
    let nextEmiAmount: Int
    let nextEmiDueDate: Date?
    let principal: Int
    let disbursedDate: Date?
    let repayments: [AppRepayment]
}

enum AppLoanMapper {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func mapLoanList(_ remoteList: [ConvexLoanData], status: AppLoanStatus) -> [AppLoan] {
        remoteList.compactMap { remote in
            guard remote.id?.isEmpty == false else { return nil }
            return fromRemote(remote, mappedStatus: status)
        }
    }

    static func fromRemote(_ remote: ConvexLoanData, mappedStatus: AppLoanStatus) -> AppLoan {
        let type = inferType(remote.purpose)
        let title = remote.purpose?.nilIfBlank ?? {
            switch type {
            case .home: return "Home Loan"
            case .education: return "Education Loan"
            case .other: return "Loan"
            }
        }()

        let paidEntries = (remote.repayments ?? [])
            .sorted { (parseMonth($0.month) ?? .distantPast) < (parseMonth($1.month) ?? .distantPast) }
            .enumerated()
            .map { mapRepayment(index: $0.offset + 1, repayment: $0.element) }

        let repayments: [AppRepayment]
        switch mappedStatus {
        case .active:
            repayments = buildFullSchedule(remote, paid: paidEntries)
        case .pending:
            repayments = buildPendingSchedule(remote)
        case .repaid:
            repayments = paidEntries
        }

        let nextEmiDate = mappedStatus == .active ? nextUnpaidMonth(remote, paid: paidEntries) : nil
        let outstanding: Double
        if mappedStatus == .pending {
            outstanding = remote.loanAmount ?? remote.principalAmount ?? 0
        } else {
            outstanding = remote.remainingBalance ?? 0
        }

        return AppLoan(
            id: remote.id ?? UUID().uuidString,
            title: title,
            loanId: remote.loanId ?? "",
            type: type,
            status: mappedStatus,
            outstandingBalance: Int(outstanding),
            nextEmiAmount: Int(remote.monthlyDeduction ?? 0),
            nextEmiDueDate: nextEmiDate,
            principal: Int(remote.loanAmount ?? remote.principalAmount ?? 0),
            disbursedDate: parseDay(remote.disbursedDate),
            repayments: repayments
        )
    }

    private static func mapRepayment(index: Int, repayment: ConvexLoanRepaymentData) -> AppRepayment {
        let dueDate = parseMonth(repayment.month) ?? parseISO(repayment.createdAt)
        let status: AppRepaymentStatus = .paid
        let paidVia: String? = {
            guard status == .paid else { return nil }
            switch repayment.mode {
            case "salary-deduction": return "Salary"
            case "manual": return "Bank"
            case let mode? where !mode.isEmpty: return mode.prefix(1).uppercased() + mode.dropFirst()
            default: return nil
            }
        }()
        return AppRepayment(
            emiIndex: index,
            dueDate: dueDate,
            amount: Int(repayment.amount ?? 0),
            status: status,
            paidVia: paidVia,
            onTime: true
        )
    }

    private static func buildFullSchedule(_ remote: ConvexLoanData, paid: [AppRepayment]) -> [AppRepayment] {
        guard let start = parseMonth(remote.repaymentStartMonth),
              let end = parseMonth(remote.repaymentEndMonth)
        else { return paid }

        let paidByMonth = Dictionary(uniqueKeysWithValues: paid.compactMap { repayment in
            repayment.dueDate.map { (monthKey($0), repayment) }
        })
        let emiAmount = Int(remote.monthlyDeduction ?? 0)
        var output: [AppRepayment] = []
        var cursor = start
        var index = 1
        while cursor <= end && index <= 360 {
            let key = monthKey(cursor)
            if let existing = paidByMonth[key] {
                output.append(AppRepayment(
                    emiIndex: index,
                    dueDate: existing.dueDate,
                    amount: existing.amount,
                    status: existing.status,
                    paidVia: existing.paidVia,
                    onTime: existing.onTime
                ))
            } else {
                output.append(AppRepayment(
                    emiIndex: index,
                    dueDate: cursor,
                    amount: emiAmount,
                    status: .upcoming,
                    paidVia: nil,
                    onTime: true
                ))
            }
            cursor = Calendar.current.date(byAdding: .month, value: 1, to: cursor) ?? .distantFuture
            index += 1
        }
        return output
    }

    private static func buildPendingSchedule(_ remote: ConvexLoanData) -> [AppRepayment] {
        guard let start = parseMonth(remote.repaymentStartMonth),
              let end = parseMonth(remote.repaymentEndMonth)
        else { return [] }
        let emiAmount = Int(remote.monthlyDeduction ?? 0)
        var output: [AppRepayment] = []
        var cursor = start
        var index = 1
        while cursor <= end && index <= 360 {
            output.append(AppRepayment(
                emiIndex: index,
                dueDate: cursor,
                amount: emiAmount,
                status: .upcoming,
                paidVia: nil,
                onTime: true
            ))
            cursor = Calendar.current.date(byAdding: .month, value: 1, to: cursor) ?? .distantFuture
            index += 1
        }
        return output
    }

    private static func nextUnpaidMonth(_ remote: ConvexLoanData, paid: [AppRepayment]) -> Date? {
        guard let start = parseMonth(remote.repaymentStartMonth) else { return nil }
        let end = parseMonth(remote.repaymentEndMonth)
        let paidMonths = Set(paid.compactMap { $0.dueDate.map(monthKey) })
        let now = Date()
        var cursor = start
        for _ in 0..<360 {
            if let end, cursor > end { return nil }
            if !paidMonths.contains(monthKey(cursor)) && cursor >= now { return cursor }
            cursor = Calendar.current.date(byAdding: .month, value: 1, to: cursor) ?? .distantFuture
        }
        return nil
    }

    private static func inferType(_ purpose: String?) -> AppLoanType {
        let lower = purpose?.lowercased() ?? ""
        if lower.contains("home") || lower.contains("house") || lower.contains("property") { return .home }
        if lower.contains("educ") || lower.contains("school") || lower.contains("college") { return .education }
        return .other
    }

    private static func parseDay(_ value: String?) -> Date? {
        guard let value = value?.nilIfBlank else { return nil }
        return dayFormatter.date(from: value)
    }

    private static func parseMonth(_ value: String?) -> Date? {
        guard let value = value?.nilIfBlank else { return nil }
        return monthFormatter.date(from: value)
    }

    private static func parseISO(_ value: String?) -> Date? {
        guard let value = value?.nilIfBlank else { return nil }
        return isoFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func monthKey(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }
}

// MARK: - Marketing / Inventory / Booking

struct MarketingProject: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let scope: String?
    let status: String?
    let location: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, scope, status, location
    }
}

struct InventoryLayoutCoordinates: Decodable, Hashable, Sendable {
    let shape: String?
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let rotation: Double?
    let svgViewBox: String?
    let points: [LayoutPoint]?
}

struct LayoutPoint: Decodable, Hashable, Sendable {
    let x: Double
    let y: Double
}

struct InventoryUnit: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let projectId: String?
    let unitNumber: String?
    let unitType: String?
    let facing: String?
    let area: Double?
    let dimensions: String?
    let floor: Int?
    let block: String?
    let priceSnapshot: Double?
    let status: String
    let rawStatus: String?
    let reservedByBookingId: String?
    let soldByBookingId: String?
    let customerName: String?
    let layoutId: String?
    let layoutCoordinates: InventoryLayoutCoordinates?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case projectId, unitNumber, unitType, facing, area, dimensions, floor, block
        case priceSnapshot, status, rawStatus, reservedByBookingId, soldByBookingId
        case customerName, layoutId, layoutCoordinates
    }
}

struct TelecallerLeadSearchData: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let contactName: String?
    let mobileNumber: String?
    let emailId: String?
    let clientCity: String?
    let locationPreferred: String?
    let suggestedVisitAddress: String?
    let latestAnalysisProfile: LeadAnalysisProfile?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case contactName, mobileNumber, emailId, clientCity, locationPreferred
        case suggestedVisitAddress, latestAnalysisProfile
    }

    var displayName: String {
        latestAnalysisProfile?.clientName?.nilIfBlank
            ?? contactName?.nilIfBlank
            ?? mobileNumber?.nilIfBlank
            ?? id
    }
}

struct LeadAnalysisProfile: Decodable, Hashable, Sendable {
    let clientName: String?
    let pincode: String?
    let address: String?
    let landmark: String?
    let state: String?
    let district: String?
    let alternateMobileNumber: String?
    let propertyType: String?
}

struct CreateBookingRequest: Encodable, Sendable {
    let clientName: String
    let mobileNumber: String
    let bookingDate: String
    let leadId: String?
    let title: String?
    let fatherSpouseName: String?
    let dateOfBirth: String?
    let anniversaryDate: String?
    let alternateNumbers: String?
    let whatsappNumber: String?
    let projectId: String?
    let plotId: String?
    let plotNo: String?
    let bookingType: String?
    let cefNo: String?
    let isDuplicateBooking: Bool?
    let isAgainstSV: Bool?
    let propertyType: String?
    let bookingMode: String?
    let bookingCost: Double?
    let guidelineValue: Double?
    let specialConsideration: Double?
    let specialConsiderationReason: String?
    let discountApprovedBy: String?
    let specialConsiderationValidity: Double?
    let promotionalOffers: String?
    let promotionalOffersTnC: String?
    let promotionalOfferValue: Double?
    let offerValidityPeriod: Double?
    let agreedAmount: Double?
    let registrationCharges: Double?
    let gstAmount: Double?
    let gstApplicable: Bool?
    let documentCharges: Double?
    let pattaCharges: Double?
    let otherCharges: Double?
    let otherChargesApplicable: Bool?
    let advanceAmount: Double?
    let balanceAmount: Double?
    let paymentMode: String?
    let freePayment: Bool?
    let allotmentDueAmount: Double?
    let allotmentDueDate: String?
    let secondPaymentAmount: Double?
    let secondPaymentDate: String?
    let thirdPaymentAmount: Double?
    let thirdPaymentDate: String?
    let fourthPaymentAmount: Double?
    let fourthPaymentDate: String?
    let preferredRegistrationDate: String?
    let originalAvpStaffId: String?
    let originalGmStaffId: String?
    let originalSeniorManagerStaffId: String?
    let originalBdoStaffId: String?
    let originalTelecallerStaffId: String?
    let aadhaar: String?
    let pan: String?
    let referenceName1: String?
    let referenceMobile1: String?
    let referenceProfession1: String?
    let referenceName2: String?
    let referenceMobile2: String?
    let referenceProfession2: String?
    let docPreparedIn: String?
    let email: String?
    let pincode: String?
    let homeAddress: String?
    let profession: String?
    let designation: String?
    let incomePerAnnum: String?
    let officeName: String?
    let officeAddress: String?
    let state: String?
    let district: String?
    let location: String?
    let officeMobile: String?
    let officePhone: String?
    let officeEmail: String?
    let nationality: String?
    let cpVisitId: String?
    let siteVisitId: String?
    let source: String?
    let status: String?
    let sourceType: String?
    let sourceClientPlaceVisitId: String?
    let sourceSiteVisitId: String?
    let notes: String?

    init(
        clientName: String,
        mobileNumber: String,
        bookingDate: String,
        leadId: String? = nil,
        title: String? = nil,
        fatherSpouseName: String? = nil,
        dateOfBirth: String? = nil,
        anniversaryDate: String? = nil,
        alternateNumbers: String? = nil,
        whatsappNumber: String? = nil,
        projectId: String? = nil,
        plotId: String? = nil,
        plotNo: String? = nil,
        bookingType: String? = nil,
        cefNo: String? = nil,
        isDuplicateBooking: Bool? = nil,
        isAgainstSV: Bool? = nil,
        propertyType: String? = nil,
        bookingMode: String? = nil,
        bookingCost: Double? = nil,
        guidelineValue: Double? = nil,
        specialConsideration: Double? = nil,
        specialConsiderationReason: String? = nil,
        discountApprovedBy: String? = nil,
        specialConsiderationValidity: Double? = nil,
        promotionalOffers: String? = nil,
        promotionalOffersTnC: String? = nil,
        promotionalOfferValue: Double? = nil,
        offerValidityPeriod: Double? = nil,
        agreedAmount: Double? = nil,
        registrationCharges: Double? = nil,
        gstAmount: Double? = nil,
        gstApplicable: Bool? = nil,
        documentCharges: Double? = nil,
        pattaCharges: Double? = nil,
        otherCharges: Double? = nil,
        otherChargesApplicable: Bool? = nil,
        advanceAmount: Double? = nil,
        balanceAmount: Double? = nil,
        paymentMode: String? = nil,
        freePayment: Bool? = nil,
        allotmentDueAmount: Double? = nil,
        allotmentDueDate: String? = nil,
        secondPaymentAmount: Double? = nil,
        secondPaymentDate: String? = nil,
        thirdPaymentAmount: Double? = nil,
        thirdPaymentDate: String? = nil,
        fourthPaymentAmount: Double? = nil,
        fourthPaymentDate: String? = nil,
        preferredRegistrationDate: String? = nil,
        originalAvpStaffId: String? = nil,
        originalGmStaffId: String? = nil,
        originalSeniorManagerStaffId: String? = nil,
        originalBdoStaffId: String? = nil,
        originalTelecallerStaffId: String? = nil,
        aadhaar: String? = nil,
        pan: String? = nil,
        referenceName1: String? = nil,
        referenceMobile1: String? = nil,
        referenceProfession1: String? = nil,
        referenceName2: String? = nil,
        referenceMobile2: String? = nil,
        referenceProfession2: String? = nil,
        docPreparedIn: String? = nil,
        email: String? = nil,
        pincode: String? = nil,
        homeAddress: String? = nil,
        profession: String? = nil,
        designation: String? = nil,
        incomePerAnnum: String? = nil,
        officeName: String? = nil,
        officeAddress: String? = nil,
        state: String? = nil,
        district: String? = nil,
        location: String? = nil,
        officeMobile: String? = nil,
        officePhone: String? = nil,
        officeEmail: String? = nil,
        nationality: String? = nil,
        cpVisitId: String? = nil,
        siteVisitId: String? = nil,
        source: String? = nil,
        status: String? = nil,
        sourceType: String? = nil,
        sourceClientPlaceVisitId: String? = nil,
        sourceSiteVisitId: String? = nil,
        notes: String? = nil
    ) {
        self.clientName = clientName
        self.mobileNumber = mobileNumber
        self.bookingDate = bookingDate
        self.leadId = leadId
        self.title = title
        self.fatherSpouseName = fatherSpouseName
        self.dateOfBirth = dateOfBirth
        self.anniversaryDate = anniversaryDate
        self.alternateNumbers = alternateNumbers
        self.whatsappNumber = whatsappNumber
        self.projectId = projectId
        self.plotId = plotId
        self.plotNo = plotNo
        self.bookingType = bookingType
        self.cefNo = cefNo
        self.isDuplicateBooking = isDuplicateBooking
        self.isAgainstSV = isAgainstSV
        self.propertyType = propertyType
        self.bookingMode = bookingMode
        self.bookingCost = bookingCost
        self.guidelineValue = guidelineValue
        self.specialConsideration = specialConsideration
        self.specialConsiderationReason = specialConsiderationReason
        self.discountApprovedBy = discountApprovedBy
        self.specialConsiderationValidity = specialConsiderationValidity
        self.promotionalOffers = promotionalOffers
        self.promotionalOffersTnC = promotionalOffersTnC
        self.promotionalOfferValue = promotionalOfferValue
        self.offerValidityPeriod = offerValidityPeriod
        self.agreedAmount = agreedAmount
        self.registrationCharges = registrationCharges
        self.gstAmount = gstAmount
        self.gstApplicable = gstApplicable
        self.documentCharges = documentCharges
        self.pattaCharges = pattaCharges
        self.otherCharges = otherCharges
        self.otherChargesApplicable = otherChargesApplicable
        self.advanceAmount = advanceAmount
        self.balanceAmount = balanceAmount
        self.paymentMode = paymentMode
        self.freePayment = freePayment
        self.allotmentDueAmount = allotmentDueAmount
        self.allotmentDueDate = allotmentDueDate
        self.secondPaymentAmount = secondPaymentAmount
        self.secondPaymentDate = secondPaymentDate
        self.thirdPaymentAmount = thirdPaymentAmount
        self.thirdPaymentDate = thirdPaymentDate
        self.fourthPaymentAmount = fourthPaymentAmount
        self.fourthPaymentDate = fourthPaymentDate
        self.preferredRegistrationDate = preferredRegistrationDate
        self.originalAvpStaffId = originalAvpStaffId
        self.originalGmStaffId = originalGmStaffId
        self.originalSeniorManagerStaffId = originalSeniorManagerStaffId
        self.originalBdoStaffId = originalBdoStaffId
        self.originalTelecallerStaffId = originalTelecallerStaffId
        self.aadhaar = aadhaar
        self.pan = pan
        self.referenceName1 = referenceName1
        self.referenceMobile1 = referenceMobile1
        self.referenceProfession1 = referenceProfession1
        self.referenceName2 = referenceName2
        self.referenceMobile2 = referenceMobile2
        self.referenceProfession2 = referenceProfession2
        self.docPreparedIn = docPreparedIn
        self.email = email
        self.pincode = pincode
        self.homeAddress = homeAddress
        self.profession = profession
        self.designation = designation
        self.incomePerAnnum = incomePerAnnum
        self.officeName = officeName
        self.officeAddress = officeAddress
        self.state = state
        self.district = district
        self.location = location
        self.officeMobile = officeMobile
        self.officePhone = officePhone
        self.officeEmail = officeEmail
        self.nationality = nationality
        self.cpVisitId = cpVisitId
        self.siteVisitId = siteVisitId
        self.source = source
        self.status = status
        self.sourceType = sourceType
        self.sourceClientPlaceVisitId = sourceClientPlaceVisitId
        self.sourceSiteVisitId = sourceSiteVisitId
        self.notes = notes
    }
}

struct SetSiteVisitOutcomeRequest: Encodable, Sendable {
    let id: String
    let outcome: String
    let reasons: [String]?
    let postponeReasons: [String]?
    let notInterestedReasons: [String]?
    let notInterestedDetails: [SiteVisitNotInterestedDetail]?
    let notes: String?
    let bookingId: String?
}

struct SiteVisitNotInterestedDetail: Encodable, Sendable {
    let reason: String
    let detail: String?
}

struct AppBooking: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let bookingRefNo: String?
    let clientName: String?
    let mobileNumber: String?
    let projectId: String?
    let projectName: String?
    let plotId: String?
    let plotNo: String?
    let bookingDate: String?
    let bookingType: String?
    let bookingMode: String?
    let bookingCost: Double?
    let advanceAmount: Double?
    let balanceAmount: Double?
    let source: String?
    let status: String?
    let approvalStatus: String?
    let notes: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case bookingRefNo, clientName, mobileNumber, projectId, projectName
        case plotId, plotNo, bookingDate, bookingType, bookingMode
        case bookingCost, advanceAmount, balanceAmount, source, status
        case approvalStatus, notes, createdAt, updatedAt
    }

    var displayStatus: String {
        approvalStatus?.nilIfBlank ?? status?.nilIfBlank ?? "pending"
    }
}

struct UpdateBookingRequest: Encodable, Sendable {
    let id: String
    let clientName: String?
    let mobileNumber: String?
    let bookingDate: String?
    let bookingCost: Double?
    let advanceAmount: Double?
    let notes: String?
}

struct CreateCpVisitRequest: Encodable, Sendable {
    let leadId: String?
    let projectId: String?
    let clientName: String?
    let mobileNumber: String
    let assignedStaffId: String
    let scheduledDate: String
    let scheduledTime: String?
    let visitAddress: String
    let visitLat: Double?
    let visitLng: Double?
    let googleMapsLink: String?
    let notes: String?
}

struct CreateCpVisitResponse: Decodable, Sendable {
    let success: Bool
    let id: String?
    let fieldVisitId: String?
    let followupId: String?
    let clientPlaceId: String?
    let error: String?
}

struct MarkClientMetRequest: Encodable, Sendable {
    let id: String
    let clientMet: Bool
    let clientNoShowReason: String?

    init(id: String, clientMet: Bool, clientNoShowReason: String? = nil) {
        self.id = id
        self.clientMet = clientMet
        self.clientNoShowReason = clientNoShowReason
    }
}

struct SetCpVisitOutcomeRequest: Encodable, Sendable {
    let id: String
    let outcome: String
    let postponeReasons: [String]?
    let notes: String?
}

struct SiteVisitAttendeeRequest: Encodable, Hashable, Sendable {
    let name: String?
    let relation: String?
    let age: String?
    let isVeg: Bool?
}

struct ConvertCpVisitToSiteVisitRequest: Encodable, Sendable {
    let id: String
    let projectId: String
    let scheduledDate: String
    let scheduledTime: String?
    let telecallerId: String?
    let convertedByStaffId: String?
    let assignedTelecallerStaffId: String?
    let inchargeStaffId: String?
    let hodStaffId: String?
    let avpStaffId: String?
    let gmStaffId: String?
    let seniorManagerStaffId: String?
    let expectedAttendeeCount: Int?
    let attendees: [SiteVisitAttendeeRequest]?
    let pickupAddress: String?
    let pickupTime: String?
    let travelMode: String?
    let vehiclePreference: String?
    let foodPreferences: String?
    let notes: String?

    init(
        id: String,
        projectId: String,
        scheduledDate: String,
        scheduledTime: String? = nil,
        telecallerId: String? = nil,
        convertedByStaffId: String? = nil,
        assignedTelecallerStaffId: String? = nil,
        inchargeStaffId: String? = nil,
        hodStaffId: String? = nil,
        avpStaffId: String? = nil,
        gmStaffId: String? = nil,
        seniorManagerStaffId: String? = nil,
        expectedAttendeeCount: Int? = nil,
        attendees: [SiteVisitAttendeeRequest]? = nil,
        pickupAddress: String? = nil,
        pickupTime: String? = nil,
        travelMode: String? = nil,
        vehiclePreference: String? = nil,
        foodPreferences: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.scheduledDate = scheduledDate
        self.scheduledTime = scheduledTime
        self.telecallerId = telecallerId
        self.convertedByStaffId = convertedByStaffId
        self.assignedTelecallerStaffId = assignedTelecallerStaffId
        self.inchargeStaffId = inchargeStaffId
        self.hodStaffId = hodStaffId
        self.avpStaffId = avpStaffId
        self.gmStaffId = gmStaffId
        self.seniorManagerStaffId = seniorManagerStaffId
        self.expectedAttendeeCount = expectedAttendeeCount
        self.attendees = attendees
        self.pickupAddress = pickupAddress
        self.pickupTime = pickupTime
        self.travelMode = travelMode
        self.vehiclePreference = vehiclePreference
        self.foodPreferences = foodPreferences
        self.notes = notes
    }
}

struct ConvertCpVisitToSiteVisitResponse: Decodable, Sendable {
    let success: Bool
    let siteVisitId: String?
    let visitId: String?
    let error: String?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
