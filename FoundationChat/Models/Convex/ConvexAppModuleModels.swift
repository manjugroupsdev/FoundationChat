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
    let requestType: String?
    let currentStage: String?
    let nominee1Status: String?
    let nominee2Status: String?
    let nominee1Name: String?
    let nominee2Name: String?
    let assignedGmName: String?
    let assignedAvpName: String?
    let gmName: String?
    let avpName: String?
    let hrApprovalName: String?
    let accountantName: String?
    let resolvedGmName: String?
    let resolvedAvpName: String?
    let resolvedHrName: String?
    let resolvedAccountantName: String?
    let repayments: [ConvexLoanRepaymentData]?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case loanId, staffId, staffName, employeeId, principalAmount, loanAmount
        case annualInterestRate, interestType, disbursedDate, repaymentStartMonth
        case repaymentEndMonth, monthlyDeduction, totalRepaid, remainingBalance
        case status, purpose, notes, approvalStatus, requestType, currentStage
        case nominee1Status, nominee2Status, nominee1Name, nominee2Name
        case assignedGmName, assignedAvpName, gmName, avpName, hrApprovalName, accountantName
        case resolvedGmName, resolvedAvpName, resolvedHrName, resolvedAccountantName, repayments
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
    let rawStatus: String?
    let requestType: String?
    let currentStage: String?
    let approvalStatus: String?
    let requesterName: String?
    let requesterEmployeeId: String?
    let nominee1Status: String?
    let nominee2Status: String?
    let nominee1Name: String?
    let nominee2Name: String?
    let gmName: String?
    let avpName: String?
    let hrName: String?
    let accountantName: String?

    var isSalaryAdvance: Bool {
        let request = requestType?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let titleText = title.lowercased()
        return request == "salary_advance" || request == "advance" || titleText.contains("advance")
    }
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
            repayments: repayments,
            rawStatus: remote.status?.nilIfBlank ?? remote.approvalStatus?.nilIfBlank,
            requestType: remote.requestType?.nilIfBlank ?? remote.interestType?.nilIfBlank,
            currentStage: remote.currentStage,
            approvalStatus: remote.approvalStatus,
            requesterName: remote.staffName?.nilIfBlank,
            requesterEmployeeId: remote.employeeId?.nilIfBlank,
            nominee1Status: remote.nominee1Status,
            nominee2Status: remote.nominee2Status,
            nominee1Name: remote.nominee1Name,
            nominee2Name: remote.nominee2Name,
            gmName: remote.gmName?.nilIfBlank ?? remote.assignedGmName?.nilIfBlank ?? remote.resolvedGmName?.nilIfBlank,
            avpName: remote.avpName?.nilIfBlank ?? remote.assignedAvpName?.nilIfBlank ?? remote.resolvedAvpName?.nilIfBlank,
            hrName: remote.hrApprovalName?.nilIfBlank ?? remote.resolvedHrName?.nilIfBlank,
            accountantName: remote.accountantName?.nilIfBlank ?? remote.resolvedAccountantName?.nilIfBlank
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
    let specialPaymentEnabled: Bool?
    let minimumAdvanceAmount: Double?
    let allotmentDueDays: Int?
    let gstPercent: Double?
    let promoOffer: String?
    let projectOfferValue: Double?
    let projectOfferTerms: String?
    let projectOfferValidityDays: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, scope, status, location, specialPaymentEnabled, minimumAdvanceAmount
        case allotmentDueDays, gstPercent
        case promoOffer, projectOfferValue, projectOfferTerms, projectOfferValidityDays
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

struct BookingPlotPrefill: Decodable, Sendable {
    let success: Bool
    let project: Project?
    let plot: Plot
    let fields: Fields
    let schedules: [Schedule]
    let error: String?

    struct Project: Decodable, Sendable {
        let id: String
        let name: String?
        let promoOffer: String?
        let projectOfferValue: Double?
        let projectOfferTerms: String?
        let projectOfferValidityDays: Double?
        let gstPercent: Double?
        let minimumAdvanceAmount: Double?
        let allotmentDueDays: Int?

        enum CodingKeys: String, CodingKey {
            case id = "_id"
            case name, promoOffer, projectOfferValue, projectOfferTerms, projectOfferValidityDays
            case gstPercent, minimumAdvanceAmount, allotmentDueDays
        }
    }

    struct Plot: Decodable, Sendable {
        let id: String
        let plotNo: String?
        let plotType: String?
        let area: Double?
        let ratePerSqft: Double?
        let plotCost: Double?
        let guidelineValue: Double?

        enum CodingKeys: String, CodingKey {
            case id = "_id"
            case plotNo, plotType, area, ratePerSqft, plotCost, guidelineValue
        }
    }

    struct Fields: Decodable, Sendable {
        let bookingCost: Double?
        let agreedAmount: Double?
        let guidelineValue: Double?
        let registrationCharges: Double?
        let gstAmount: Double?
        let documentCharges: Double?
        let pattaCharges: Double?
        let otherCharges: Double?
        let advanceAmount: Double?
        let advanceDueDate: String?
        let allotmentDueAmount: Double?
        let allotmentDueDate: String?
    }

    struct Schedule: Decodable, Sendable {
        let description: String?
        let paymentPercent: Double?
        let daysFromBooking: Int?
        let amount: Double?
        let dueDate: String?
    }
}

struct BookingConversionPrefill: Decodable, Equatable, Sendable {
    let bookingId: String
    let bookingRefNo: String?
    let previousProject: String?
    let previousPlot: String?
    let totalAmountPaid: Double
}

struct BookingExchangeSource: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let bookingRefNo: String
    let bookingDate: String
    let clientName: String
    let mobileNumber: String
    let projectId: String?
    let plotId: String?
    let projectName: String?
    let plotNo: String?
    let extentSqft: Double?
    let exchangeValue: Double?
    let bookingCost: Double?
    let agreedAmount: Double?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case bookingRefNo, bookingDate, clientName, mobileNumber
        case projectId, plotId, projectName, plotNo, extentSqft
        case exchangeValue, bookingCost, agreedAmount, status
    }

    var resolvedExchangeValue: Double {
        exchangeValue ?? agreedAmount ?? bookingCost ?? 0
    }
}

struct TelecallerLeadSearchData: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let contactName: String?
    let mobileNumber: String?
    let emailId: String?
    let projectId: String?
    let assignedToStaffId: String?
    let clientCity: String?
    let locationPreferred: String?
    let suggestedVisitAddress: String?
    let suggestedVisitLat: Double?
    let suggestedVisitLng: Double?
    let suggestedGoogleMapsLink: String?
    let latestAnalysisProfile: LeadAnalysisProfile?
    let clientPlaceProfile: LeadLocationProfile?
    let manualProfile: LeadLocationProfile?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case contactName, mobileNumber, emailId, projectId, assignedToStaffId, clientCity, locationPreferred
        case suggestedVisitAddress, suggestedVisitLat, suggestedVisitLng, suggestedGoogleMapsLink
        case latestAnalysisProfile, clientPlaceProfile, manualProfile
    }

    var displayName: String {
        latestAnalysisProfile?.clientName?.nilIfBlank
            ?? contactName?.nilIfBlank
            ?? mobileNumber?.nilIfBlank
            ?? id
    }
}

/// Client-master profile returned by `/api/clients/search-by-phone`.
/// The web booking form uses this record after lead lookup to fill any
/// remaining blank client, address, work, KYC, and reference fields.
struct BookingClientProfile: Decodable, Identifiable, Sendable {
    let id: String
    let mobileNumber: String?
    let alternateNumbers: String?
    let whatsappNumber: String?
    let email: String?
    let title: String?
    let clientName: String?
    let clientImageStorageId: String?
    let clientImageFileName: String?
    let fatherSpouseName: String?
    let dateOfBirth: String?
    let anniversaryDate: String?
    let nationality: String?
    let homeAddress: String?
    let doorNo: String?
    let addressLine1: String?
    let addressLine2: String?
    let landmark: String?
    let pincode: String?
    let state: String?
    let district: String?
    let location: String?
    let formattedAddress: String?
    let googleMapsLink: String?
    let lat: Double?
    let lng: Double?
    let profession: String?
    let designation: String?
    let department: String?
    let incomePerAnnum: String?
    let officeName: String?
    let officeAddress: String?
    let officeArea: String?
    let officePincode: String?
    let officeMobile: String?
    let officePhone: String?
    let officeEmail: String?
    let aadhaar: String?
    let aadhaarDocumentStorageId: String?
    let aadhaarDocumentFileName: String?
    let pan: String?
    let panDocumentStorageId: String?
    let panDocumentFileName: String?
    let referenceName1: String?
    let referenceMobile1: String?
    let referenceProfession1: String?
    let referenceName2: String?
    let referenceMobile2: String?
    let referenceProfession2: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case mobileNumber, alternateNumbers, whatsappNumber, email
        case title, clientName, clientImageStorageId, clientImageFileName
        case fatherSpouseName, dateOfBirth, anniversaryDate, nationality
        case homeAddress, doorNo, addressLine1, addressLine2, landmark
        case pincode, state, district, location, formattedAddress
        case googleMapsLink, lat, lng
        case profession, designation, department, incomePerAnnum
        case officeName, officeAddress, officeArea, officePincode
        case officeMobile, officePhone, officeEmail
        case aadhaar, aadhaarDocumentStorageId, aadhaarDocumentFileName
        case pan, panDocumentStorageId, panDocumentFileName
        case referenceName1, referenceMobile1, referenceProfession1
        case referenceName2, referenceMobile2, referenceProfession2
    }
}

struct LeadAnalysisProfile: Decodable, Hashable, Sendable {
    let clientName: String?
    let doorNo: String?
    let street: String?
    let pincode: String?
    let address: String?
    let landmark: String?
    let state: String?
    let district: String?
    let alternateMobileNumber: String?
    let propertyType: String?
}

struct LeadLocationProfile: Decodable, Hashable, Sendable {
    let clientName: String?
    let doorNo: String?
    let street: String?
    let address: String?
    let formattedAddress: String?
    let landmark: String?
    let city: String?
    let state: String?
    let pincode: String?
}

struct BookingPaymentScheduleItem: Codable, Equatable, Sendable {
    let amount: Double
    let dueDate: String
}

struct CreateBookingRequest: Encodable, Sendable {
    let clientName: String
    let mobileNumber: String
    let bookingDate: String
    let leadId: String?
    let title: String?
    let clientImageStorageId: String?
    let clientImageFileName: String?
    let fatherSpouseName: String?
    let dateOfBirth: String?
    let anniversaryDate: String?
    let alternateNumbers: String?
    let whatsappNumber: String?
    let lat: Double?
    let lng: Double?
    let googleMapsLink: String?
    let projectId: String?
    let plotId: String?
    let plotNo: String?
    let bookingType: String?
    let conversionManualEntry: Bool?
    let manualConversionProjectName: String?
    let manualConversionPlotNo: String?
    let manualConversionCredit: Double?
    let conversionNotes: String?
    let sourceExchangeBookingId: String?
    let exchangeManualEntry: Bool?
    let exchangeLookupProjectId: String?
    let exchangeLookupPlotNo: String?
    let exchangeConnectedMobileNumber: String?
    let manualExchangeProjectName: String?
    let manualExchangePlotNo: String?
    let manualExchangeExtentSqft: Double?
    let exchangeOldRegisteredValue: Double?
    let exchangeNewValue: Double?
    let exchangeBalancePayable: Double?
    let exchangeNotes: String?
    let cefNo: String?
    let isDuplicateBooking: Bool?
    let isAgainstSV: Bool?
    let svName: String?
    let svMobileNo: String?
    let propertyType: String?
    let bookingMode: String?
    let clientSource: String?
    let clientSourceName: String?
    let clientSourceMobile: String?
    let referralBenefit: String?
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
    let advanceTransactionId: String?
    let advancePaymentProofStorageId: String?
    let advancePaymentProofFileName: String?
    let advanceInstrumentNo: String?
    let advanceBankName: String?
    let advanceBankBranch: String?
    let advanceInstrumentDate: String?
    let customerPaymentCategory: String?
    let loanAmountRequested: Double?
    let paymentPlan: String?
    let freePayment: Bool?
    let allotmentDueAmount: Double?
    let allotmentDueDate: String?
    let secondPaymentAmount: Double?
    let secondPaymentDate: String?
    let thirdPaymentAmount: Double?
    let thirdPaymentDate: String?
    let fourthPaymentAmount: Double?
    let fourthPaymentDate: String?
    let flexiPaymentSchedule: [BookingPaymentScheduleItem]?
    let preferredRegistrationDate: String?
    let originalAvpStaffId: String?
    let originalGmStaffId: String?
    let originalSeniorManagerStaffId: String?
    let originalBdoStaffId: String?
    let originalTelecallerStaffId: String?
    let aadhaar: String?
    let aadhaarDocumentStorageId: String?
    let aadhaarDocumentFileName: String?
    let pan: String?
    let panDocumentStorageId: String?
    let panDocumentFileName: String?
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
    let department: String?
    let incomePerAnnum: String?
    let officeName: String?
    let officeAddress: String?
    let officeArea: String?
    let officePincode: String?
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
        clientImageStorageId: String? = nil,
        clientImageFileName: String? = nil,
        fatherSpouseName: String? = nil,
        dateOfBirth: String? = nil,
        anniversaryDate: String? = nil,
        alternateNumbers: String? = nil,
        whatsappNumber: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        googleMapsLink: String? = nil,
        projectId: String? = nil,
        plotId: String? = nil,
        plotNo: String? = nil,
        bookingType: String? = nil,
        conversionManualEntry: Bool? = nil,
        manualConversionProjectName: String? = nil,
        manualConversionPlotNo: String? = nil,
        manualConversionCredit: Double? = nil,
        conversionNotes: String? = nil,
        sourceExchangeBookingId: String? = nil,
        exchangeManualEntry: Bool? = nil,
        exchangeLookupProjectId: String? = nil,
        exchangeLookupPlotNo: String? = nil,
        exchangeConnectedMobileNumber: String? = nil,
        manualExchangeProjectName: String? = nil,
        manualExchangePlotNo: String? = nil,
        manualExchangeExtentSqft: Double? = nil,
        exchangeOldRegisteredValue: Double? = nil,
        exchangeNewValue: Double? = nil,
        exchangeBalancePayable: Double? = nil,
        exchangeNotes: String? = nil,
        cefNo: String? = nil,
        isDuplicateBooking: Bool? = nil,
        isAgainstSV: Bool? = nil,
        svName: String? = nil,
        svMobileNo: String? = nil,
        propertyType: String? = nil,
        bookingMode: String? = nil,
        clientSource: String? = nil,
        clientSourceName: String? = nil,
        clientSourceMobile: String? = nil,
        referralBenefit: String? = nil,
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
        advanceTransactionId: String? = nil,
        advancePaymentProofStorageId: String? = nil,
        advancePaymentProofFileName: String? = nil,
        advanceInstrumentNo: String? = nil,
        advanceBankName: String? = nil,
        advanceBankBranch: String? = nil,
        advanceInstrumentDate: String? = nil,
        customerPaymentCategory: String? = nil,
        loanAmountRequested: Double? = nil,
        paymentPlan: String? = nil,
        freePayment: Bool? = nil,
        allotmentDueAmount: Double? = nil,
        allotmentDueDate: String? = nil,
        secondPaymentAmount: Double? = nil,
        secondPaymentDate: String? = nil,
        thirdPaymentAmount: Double? = nil,
        thirdPaymentDate: String? = nil,
        fourthPaymentAmount: Double? = nil,
        fourthPaymentDate: String? = nil,
        flexiPaymentSchedule: [BookingPaymentScheduleItem]? = nil,
        preferredRegistrationDate: String? = nil,
        originalAvpStaffId: String? = nil,
        originalGmStaffId: String? = nil,
        originalSeniorManagerStaffId: String? = nil,
        originalBdoStaffId: String? = nil,
        originalTelecallerStaffId: String? = nil,
        aadhaar: String? = nil,
        aadhaarDocumentStorageId: String? = nil,
        aadhaarDocumentFileName: String? = nil,
        pan: String? = nil,
        panDocumentStorageId: String? = nil,
        panDocumentFileName: String? = nil,
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
        department: String? = nil,
        incomePerAnnum: String? = nil,
        officeName: String? = nil,
        officeAddress: String? = nil,
        officeArea: String? = nil,
        officePincode: String? = nil,
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
        self.clientImageStorageId = clientImageStorageId
        self.clientImageFileName = clientImageFileName
        self.fatherSpouseName = fatherSpouseName
        self.dateOfBirth = dateOfBirth
        self.anniversaryDate = anniversaryDate
        self.alternateNumbers = alternateNumbers
        self.whatsappNumber = whatsappNumber
        self.lat = lat
        self.lng = lng
        self.googleMapsLink = googleMapsLink
        self.projectId = projectId
        self.plotId = plotId
        self.plotNo = plotNo
        self.bookingType = bookingType
        self.conversionManualEntry = conversionManualEntry
        self.manualConversionProjectName = manualConversionProjectName
        self.manualConversionPlotNo = manualConversionPlotNo
        self.manualConversionCredit = manualConversionCredit
        self.conversionNotes = conversionNotes
        self.sourceExchangeBookingId = sourceExchangeBookingId
        self.exchangeManualEntry = exchangeManualEntry
        self.exchangeLookupProjectId = exchangeLookupProjectId
        self.exchangeLookupPlotNo = exchangeLookupPlotNo
        self.exchangeConnectedMobileNumber = exchangeConnectedMobileNumber
        self.manualExchangeProjectName = manualExchangeProjectName
        self.manualExchangePlotNo = manualExchangePlotNo
        self.manualExchangeExtentSqft = manualExchangeExtentSqft
        self.exchangeOldRegisteredValue = exchangeOldRegisteredValue
        self.exchangeNewValue = exchangeNewValue
        self.exchangeBalancePayable = exchangeBalancePayable
        self.exchangeNotes = exchangeNotes
        self.cefNo = cefNo
        self.isDuplicateBooking = isDuplicateBooking
        self.isAgainstSV = isAgainstSV
        self.svName = svName
        self.svMobileNo = svMobileNo
        self.propertyType = propertyType
        self.bookingMode = bookingMode
        self.clientSource = clientSource
        self.clientSourceName = clientSourceName
        self.clientSourceMobile = clientSourceMobile
        self.referralBenefit = referralBenefit
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
        self.advanceTransactionId = advanceTransactionId
        self.advancePaymentProofStorageId = advancePaymentProofStorageId
        self.advancePaymentProofFileName = advancePaymentProofFileName
        self.advanceInstrumentNo = advanceInstrumentNo
        self.advanceBankName = advanceBankName
        self.advanceBankBranch = advanceBankBranch
        self.advanceInstrumentDate = advanceInstrumentDate
        self.customerPaymentCategory = customerPaymentCategory
        self.loanAmountRequested = loanAmountRequested
        self.paymentPlan = paymentPlan
        self.freePayment = freePayment
        self.allotmentDueAmount = allotmentDueAmount
        self.allotmentDueDate = allotmentDueDate
        self.secondPaymentAmount = secondPaymentAmount
        self.secondPaymentDate = secondPaymentDate
        self.thirdPaymentAmount = thirdPaymentAmount
        self.thirdPaymentDate = thirdPaymentDate
        self.fourthPaymentAmount = fourthPaymentAmount
        self.fourthPaymentDate = fourthPaymentDate
        self.flexiPaymentSchedule = flexiPaymentSchedule
        self.preferredRegistrationDate = preferredRegistrationDate
        self.originalAvpStaffId = originalAvpStaffId
        self.originalGmStaffId = originalGmStaffId
        self.originalSeniorManagerStaffId = originalSeniorManagerStaffId
        self.originalBdoStaffId = originalBdoStaffId
        self.originalTelecallerStaffId = originalTelecallerStaffId
        self.aadhaar = aadhaar
        self.aadhaarDocumentStorageId = aadhaarDocumentStorageId
        self.aadhaarDocumentFileName = aadhaarDocumentFileName
        self.pan = pan
        self.panDocumentStorageId = panDocumentStorageId
        self.panDocumentFileName = panDocumentFileName
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
        self.department = department
        self.incomePerAnnum = incomePerAnnum
        self.officeName = officeName
        self.officeAddress = officeAddress
        self.officeArea = officeArea
        self.officePincode = officePincode
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
    let followupDueDate: String?
    let followupDueTime: String?

    init(
        id: String,
        outcome: String,
        reasons: [String]? = nil,
        postponeReasons: [String]? = nil,
        notInterestedReasons: [String]? = nil,
        notInterestedDetails: [SiteVisitNotInterestedDetail]? = nil,
        notes: String? = nil,
        bookingId: String? = nil,
        followupDueDate: String? = nil,
        followupDueTime: String? = nil
    ) {
        self.id = id
        self.outcome = outcome
        self.reasons = reasons
        self.postponeReasons = postponeReasons
        self.notInterestedReasons = notInterestedReasons
        self.notInterestedDetails = notInterestedDetails
        self.notes = notes
        self.bookingId = bookingId
        self.followupDueDate = followupDueDate
        self.followupDueTime = followupDueTime
    }
}

struct SiteVisitQRScanRequest: Encodable, Sendable {
    let qrData: String
}

struct SiteVisitIDRequest: Encodable, Sendable {
    let id: String
}

struct PostponeSiteVisitRequest: Encodable, Sendable {
    let id: String
    let scheduledDate: String
    let scheduledTime: String?
    let reason: String?
}

struct CancelSiteVisitRequest: Encodable, Sendable {
    let id: String
    let reason: String?
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
    let clientImageStorageId: String?
    let clientImageFileName: String?
    let title: String?
    let fatherSpouseName: String?
    let dateOfBirth: String?
    let anniversaryDate: String?
    let alternateNumbers: String?
    let whatsappNumber: String?
    let email: String?
    let nationality: String?
    let homeAddress: String?
    let pincode: String?
    let state: String?
    let district: String?
    let location: String?
    let profession: String?
    let designation: String?
    let incomePerAnnum: String?
    let officeName: String?
    let officeEmail: String?
    let officeMobile: String?
    let officePhone: String?
    let officeAddress: String?
    let guidelineValue: Double?
    let registrationCharges: Double?
    let gstAmount: Double?
    let documentCharges: Double?
    let pattaCharges: Double?
    let otherCharges: Double?
    let paymentMode: String?
    let customerPaymentCategory: String?
    let loanAmountRequested: Double?
    let paymentPlan: String?
    let advanceAmount: Double?
    let balanceAmount: Double?
    let source: String?
    let status: String?
    let approvalStatus: String?
    let notes: String?
    let createdAt: Double?
    let updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case bookingRefNo, clientName, mobileNumber, projectId, projectName
        case plotId, plotNo, bookingDate, bookingType, bookingMode
        case clientImageStorageId, clientImageFileName
        case title, fatherSpouseName, dateOfBirth, anniversaryDate, alternateNumbers, whatsappNumber
        case email, nationality, homeAddress, pincode, state, district, location
        case profession, designation, incomePerAnnum, officeName, officeEmail, officeMobile, officePhone, officeAddress
        case guidelineValue, registrationCharges, gstAmount, documentCharges, pattaCharges, otherCharges, paymentMode
        case customerPaymentCategory, loanAmountRequested, paymentPlan
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
    let title: String?
    let fatherSpouseName: String?
    let dateOfBirth: String?
    let anniversaryDate: String?
    let alternateNumbers: String?
    let whatsappNumber: String?
    let email: String?
    let nationality: String?
    let homeAddress: String?
    let pincode: String?
    let state: String?
    let district: String?
    let location: String?
    let profession: String?
    let designation: String?
    let incomePerAnnum: String?
    let officeName: String?
    let officeEmail: String?
    let officeMobile: String?
    let officePhone: String?
    let officeAddress: String?
    let bookingType: String?
    let bookingMode: String?
    let guidelineValue: Double?
    let registrationCharges: Double?
    let gstAmount: Double?
    let documentCharges: Double?
    let pattaCharges: Double?
    let otherCharges: Double?
    let paymentMode: String?
    let customerPaymentCategory: String?
    let loanAmountRequested: Double?
    let paymentPlan: String?

    init(
        id: String,
        clientName: String? = nil,
        mobileNumber: String? = nil,
        bookingDate: String? = nil,
        bookingCost: Double? = nil,
        advanceAmount: Double? = nil,
        notes: String? = nil,
        title: String? = nil,
        fatherSpouseName: String? = nil,
        dateOfBirth: String? = nil,
        anniversaryDate: String? = nil,
        alternateNumbers: String? = nil,
        whatsappNumber: String? = nil,
        email: String? = nil,
        nationality: String? = nil,
        homeAddress: String? = nil,
        pincode: String? = nil,
        state: String? = nil,
        district: String? = nil,
        location: String? = nil,
        profession: String? = nil,
        designation: String? = nil,
        incomePerAnnum: String? = nil,
        officeName: String? = nil,
        officeEmail: String? = nil,
        officeMobile: String? = nil,
        officePhone: String? = nil,
        officeAddress: String? = nil,
        bookingType: String? = nil,
        bookingMode: String? = nil,
        guidelineValue: Double? = nil,
        registrationCharges: Double? = nil,
        gstAmount: Double? = nil,
        documentCharges: Double? = nil,
        pattaCharges: Double? = nil,
        otherCharges: Double? = nil,
        paymentMode: String? = nil,
        customerPaymentCategory: String? = nil,
        loanAmountRequested: Double? = nil,
        paymentPlan: String? = nil
    ) {
        self.id = id
        self.clientName = clientName
        self.mobileNumber = mobileNumber
        self.bookingDate = bookingDate
        self.bookingCost = bookingCost
        self.advanceAmount = advanceAmount
        self.notes = notes
        self.title = title
        self.fatherSpouseName = fatherSpouseName
        self.dateOfBirth = dateOfBirth
        self.anniversaryDate = anniversaryDate
        self.alternateNumbers = alternateNumbers
        self.whatsappNumber = whatsappNumber
        self.email = email
        self.nationality = nationality
        self.homeAddress = homeAddress
        self.pincode = pincode
        self.state = state
        self.district = district
        self.location = location
        self.profession = profession
        self.designation = designation
        self.incomePerAnnum = incomePerAnnum
        self.officeName = officeName
        self.officeEmail = officeEmail
        self.officeMobile = officeMobile
        self.officePhone = officePhone
        self.officeAddress = officeAddress
        self.bookingType = bookingType
        self.bookingMode = bookingMode
        self.guidelineValue = guidelineValue
        self.registrationCharges = registrationCharges
        self.gstAmount = gstAmount
        self.documentCharges = documentCharges
        self.pattaCharges = pattaCharges
        self.otherCharges = otherCharges
        self.paymentMode = paymentMode
        self.customerPaymentCategory = customerPaymentCategory
        self.loanAmountRequested = loanAmountRequested
        self.paymentPlan = paymentPlan
    }
}

struct CreateCpVisitRequest: Encodable, Sendable {
    let leadId: String?
    let projectId: String?
    let clientName: String?
    let mobileNumber: String
    let assignedStaffId: String
    let scheduledDate: String
    let scheduledTime: String?
    let cpType: String?
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
    let arrivalPhotoStorageId: String?

    init(
        id: String,
        outcome: String,
        postponeReasons: [String]? = nil,
        notes: String? = nil,
        arrivalPhotoStorageId: String? = nil
    ) {
        self.id = id
        self.outcome = outcome
        self.postponeReasons = postponeReasons
        self.notes = notes
        self.arrivalPhotoStorageId = arrivalPhotoStorageId
    }
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
    let pickupLat: Double?
    let pickupLng: Double?
    let pickupGoogleMapsLink: String?
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
        pickupLat: Double? = nil,
        pickupLng: Double? = nil,
        pickupGoogleMapsLink: String? = nil,
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
        self.pickupLat = pickupLat
        self.pickupLng = pickupLng
        self.pickupGoogleMapsLink = pickupGoogleMapsLink
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
