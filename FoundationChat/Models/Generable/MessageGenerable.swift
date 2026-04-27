import Foundation

struct MessageGenerable: Codable, Sendable {
  let role: Role
  let content: String
  let metadata: WebPageMetadata?
}
