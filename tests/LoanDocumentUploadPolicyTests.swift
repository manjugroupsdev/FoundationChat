import Foundation

@main
struct LoanDocumentUploadPolicyTests {
    static func main() {
        typealias P = LoanDocumentUploadPolicy
        // 4 Nov report: new cases are at Loan Initiation, where attaching is refused.
        precondition(P.mode(stage: "loan_initiation") == .onSubmit)
        precondition(P.mode(stage: "document_collection") == .attach)
        precondition(P.mode(stage: "Document_Verification") == .attach)
        precondition(P.mode(stage: "bank_allocation") == .locked)
        precondition(P.mode(stage: nil) == .attach)
        precondition(P.mode(stage: " ") == .attach)
        precondition(P.isStageRefusal("Documents can only be changed during collection or verification."))
        precondition(P.isStageRefusal("FORBIDDEN: Documents can only be changed during collection or verification."))
        precondition(!P.isStageRefusal("This loan document collection is assigned to another staff member."))
        precondition(!P.isStageRefusal(nil))
        precondition(P.sniff(Data("%PDF-1.7\n".utf8)) == .pdf)
        precondition(P.sniff(Data([0xFF, 0xD8, 0xFF, 0xE0])) == .image)
        precondition(P.sniff(Data([0x89, 0x50, 0x4E, 0x47, 0x0D])) == .image)
        precondition(P.sniff(Data([0, 0, 0, 0x18]) + Data("ftypheic".utf8)) == .image)
        precondition(P.sniff(Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBPVP8 ".utf8)) == .image)
        precondition(P.sniff(Data([0, 0, 0, 0x18]) + Data("ftypmp42".utf8)) == .other)
        precondition(P.sniff(Data()) == .other)
        print("LoanDocumentUploadPolicy: 17 assertions passed")
    }
}
