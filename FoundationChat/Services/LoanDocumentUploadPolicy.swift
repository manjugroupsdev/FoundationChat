import Foundation

/// Where a Loan Desk document upload goes. Same rules as Android.
///
/// The server attaches a file to the loan case only at Document Collection or
/// Document Verification. A new case starts at Loan Initiation: there the
/// file is uploaded on its own and /api/postsales/loans/submit attaches it.
/// Past verification the documents are locked.
nonisolated enum LoanDocumentUploadPolicy {
    enum Mode: Equatable {
        /// Attach each upload to the case as it finishes.
        case attach
        /// Upload the file only; Submit attaches it.
        case onSubmit
        /// Documents can't change at this stage: view only.
        case locked
    }

    static func mode(stage: String?) -> Mode {
        switch stage?.trimmingCharacters(in: .whitespaces).lowercased() ?? "" {
        // Older servers don't send the stage: attach, falling back on refusal.
        case "": return .attach
        case "loan_initiation": return .onSubmit
        case "document_collection", "document_verification": return .attach
        default: return .locked
        }
    }

    /// The server refused to attach because of the case's stage.
    static func isStageRefusal(_ message: String?) -> Bool {
        message?.range(of: "can only be changed during collection or verification", options: .caseInsensitive) != nil
    }

    enum Kind: Equatable { case pdf, image, other }

    /// What a file really is, from its first bytes (picked files can carry
    /// no extension or a wrong one).
    static func sniff(_ header: Data) -> Kind {
        let bytes = [UInt8](header.prefix(32))
        func at(_ offset: Int, _ expected: [UInt8]) -> Bool {
            bytes.count >= offset + expected.count && Array(bytes[offset..<offset + expected.count]) == expected
        }
        func ascii(_ offset: Int, _ text: String) -> Bool { at(offset, Array(text.utf8)) }
        if ascii(0, "%PDF") { return .pdf }
        if at(0, [0xFF, 0xD8, 0xFF]) || at(0, [0x89, 0x50, 0x4E, 0x47]) || ascii(0, "GIF8") { return .image }
        if ascii(0, "RIFF") && ascii(8, "WEBP") { return .image }
        if ascii(4, "ftyp") && ["heic", "heix", "hevc", "hevx", "mif1", "msf1", "avif"].contains(where: { ascii(8, $0) }) {
            return .image
        }
        return .other
    }
}
