import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Makes a picked Loan Desk document upload-ready: copies it out of the
/// security-scoped picker URL, names it after what it really is, and turns
/// photos (HEIC, PNG, WebP, JPEG) into upright JPEGs with the long edge
/// capped, so every reviewer can open them and they stay light on field
/// networks. PDFs go up untouched.
nonisolated enum LoanDocumentFilePreparer {
    static let maxImageEdge = 2400

    enum Failure: LocalizedError {
        case unreadable, unsupported, empty
        var errorDescription: String? {
            switch self {
            case .unreadable: return "Couldn't read the selected file."
            case .unsupported: return "Only PDF and image documents are supported."
            case .empty: return "The selected document is empty."
            }
        }
    }

    static func prepare(_ source: URL) throws -> URL {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: source) else { throw Failure.unreadable }
        guard !data.isEmpty else { throw Failure.empty }
        let base = source.deletingPathExtension().lastPathComponent.isEmpty
            ? "loan_document"
            : source.deletingPathExtension().lastPathComponent
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("loan-docs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        switch LoanDocumentUploadPolicy.sniff(data) {
        case .pdf:
            let out = folder.appendingPathComponent("\(base).pdf")
            try? FileManager.default.removeItem(at: out)
            try data.write(to: out, options: .atomic)
            return out
        case .image:
            let out = folder.appendingPathComponent("\(base)_doc.jpg")
            guard let jpeg = normalizedJPEG(data) else { throw Failure.unsupported }
            try? FileManager.default.removeItem(at: out)
            try jpeg.write(to: out, options: .atomic)
            return out
        case .other:
            throw Failure.unsupported
        }
    }

    /// Decoded with the EXIF orientation applied and the long edge capped;
    /// ImageIO handles HEIC/WebP without decoding the full-size image first.
    static func normalizedJPEG(_ data: Data, quality: Double = 0.88) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxImageEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
