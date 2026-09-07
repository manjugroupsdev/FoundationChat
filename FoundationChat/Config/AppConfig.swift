import Foundation

struct AppConfig: Sendable {
  nonisolated static let baseURL = "https://api-mfpl.theairix.com"
  nonisolated static let chatBaseURL = "https://api-mfpl.theairix.com"
  nonisolated static let geoTrackBaseURL = "https://api-geo.theairix.com"
  nonisolated static let storageBaseURL = "https://mg.theairix.com"
  nonisolated static let storageUploadsEnabled = true
  nonisolated static let storageMaxFileBytes = 104_857_600
}
