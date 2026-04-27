import Foundation

struct WebPageMetadata: Codable, Sendable {
  let title: String
  let thumbnail: String?
  let description: String?
}
