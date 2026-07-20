import Foundation

struct FrontDeskAdditionalVisitor: Decodable, Equatable, Sendable {
    let name: String?
    let phone: String?
    let age: Int?
    let email: String?
}

struct FrontDeskInvitation: Decodable, Equatable, Sendable {
    let _id: String?
    let token: String?
    let visitorName: String?
    let visitorPhone: String?
    let visitorEmail: String?
    let visitorCompany: String?
    let visitorAge: Int?
    let additionalVisitors: [FrontDeskAdditionalVisitor]?
    let categoryName: String?
    let purposeName: String?
    let hostName: String?
    let hostDepartment: String?
    let expectedDate: String?
    let expectedTimeFrom: String?
    let expectedTimeTo: String?
    let meetingNotes: String?
    var status: String?
    var checkinId: String?
    var checkinState: String?
    var checkinAt: Int64?
    var checkoutAt: Int64?
    var passNumber: String?

    var invitationID: String? {
        _id.nilIfBlank
    }
}

struct FrontDeskCheckInResult: Sendable {
    let passNumber: String?
}

struct FrontDeskCheckOutResult: Sendable {
    let checkoutAt: Int64?
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
