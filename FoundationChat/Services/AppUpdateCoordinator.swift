import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppUpdateCoordinator {
    static let shared = AppUpdateCoordinator()

    private enum DefaultsKey {
        static let requiredVersion = "appUpdate.requiredVersion"
        static let requiredBuild = "appUpdate.requiredBuild"
        static let storeURL = "appUpdate.storeURL"
    }

    private struct LookupResponse: Decodable {
        let results: [LookupResult]
    }

    private struct LookupResult: Decodable {
        let version: String
        let trackViewUrl: String
    }

    private struct VersionPolicyResponse: Decodable {
        let success: Bool
        let platform: String?
        let latestVersion: String?
        let latestBuildNumber: Int?
        let minimumSupportedVersion: String?
        let minimumSupportedBuildNumber: Int?
        let updateRequired: Bool?
        let updateUrl: String?
        let publishedAt: String?
    }

    private(set) var requiredVersion: String?
    private(set) var requiredBuild: Int?
    private(set) var storeURL: URL?
    private let defaults: UserDefaults
    private var lastStoreCheck: Date?

    var mustShowUpdate: Bool {
        hasNewerVersion
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreKnownUpdate()
    }

    func refresh(token _: String?, isExternalFleetPrincipal _: Bool) async {
        if lastStoreCheck.map({ Date().timeIntervalSince($0) >= Self.storeCheckInterval }) != false {
            lastStoreCheck = Date()
            let serverPolicyFound = await fetchServerVersionPolicy()
            if !serverPolicyFound {
                await fetchLatestStoreVersion()
            }
        }

        guard hasNewerVersion else {
            clearKnownUpdate()
            return
        }
    }

    func openAppStore() {
        guard let storeURL else { return }
        UIApplication.shared.open(storeURL)
    }

    private func fetchLatestStoreVersion() async {
        lastStoreCheck = Date()
        guard
            let bundleId = Bundle.main.bundleIdentifier,
            var components = URLComponents(string: "https://itunes.apple.com/lookup")
        else { return }
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            URLQueryItem(name: "country", value: "in"),
        ]
        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            guard let latest = try await BackgroundJSONDecoder.decode(LookupResponse.self, from: data).results.first else {
                return
            }
            guard Self.isNewer(latest.version, than: Self.currentVersion),
                  let url = URL(string: latest.trackViewUrl)
            else {
                clearKnownUpdate()
                return
            }
            saveKnownUpdate(version: latest.version, build: nil, url: url)
        } catch {
            // A previously detected mandatory update remains enforced offline.
        }
    }

    private func fetchServerVersionPolicy() async -> Bool {
        guard var components = URLComponents(string: "\(AppConfig.baseURL)/api/mobile/app-version") else {
            return false
        }
        components.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "currentVersion", value: Self.currentVersion),
            URLQueryItem(name: "buildNumber", value: String(Self.currentBuildNumber)),
        ]
        guard let url = components.url else { return false }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            request.setValue(Self.currentVersion, forHTTPHeaderField: "X-App-Version")
            request.setValue(String(Self.currentBuildNumber), forHTTPHeaderField: "X-App-Build")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let policy = try await BackgroundJSONDecoder.decode(VersionPolicyResponse.self, from: data)
            guard policy.success else { return false }

            let candidateVersion = policy.minimumSupportedVersion ?? policy.latestVersion
            let candidateBuild = policy.minimumSupportedBuildNumber
                ?? (policy.updateRequired == true ? policy.latestBuildNumber : nil)
            let belowMinimumBuild = candidateBuild.map { Self.currentBuildNumber < $0 } == true
            guard (policy.updateRequired == true || belowMinimumBuild),
                  let candidateBuild,
                  let rawURL = policy.updateUrl,
                  let url = URL(string: rawURL)
            else {
                clearKnownUpdate()
                return false
            }
            saveKnownUpdate(
                version: candidateVersion ?? Self.currentVersion,
                build: candidateBuild,
                url: url
            )
            return true
        } catch {
            return false
        }
    }

    private func restoreKnownUpdate() {
        guard
            let version = defaults.string(forKey: DefaultsKey.requiredVersion),
            let rawURL = defaults.string(forKey: DefaultsKey.storeURL),
            let url = URL(string: rawURL)
        else {
            clearKnownUpdate()
            return
        }
        let build = (defaults.object(forKey: DefaultsKey.requiredBuild) as? NSNumber)?.intValue
        let newerBuild = build.map { $0 > Self.currentBuildNumber } == true
        let newerMarketingVersion = Self.isNewer(version, than: Self.currentVersion)
        guard newerBuild || newerMarketingVersion else {
            clearKnownUpdate()
            return
        }
        requiredVersion = version
        requiredBuild = build
        storeURL = url
    }

    private func clearKnownUpdate() {
        requiredVersion = nil
        requiredBuild = nil
        storeURL = nil
        defaults.removeObject(forKey: DefaultsKey.requiredVersion)
        defaults.removeObject(forKey: DefaultsKey.requiredBuild)
        defaults.removeObject(forKey: DefaultsKey.storeURL)
    }

    private func saveKnownUpdate(version: String, build: Int?, url: URL) {
        requiredVersion = version
        requiredBuild = build
        storeURL = url
        defaults.set(version, forKey: DefaultsKey.requiredVersion)
        if let build {
            defaults.set(build, forKey: DefaultsKey.requiredBuild)
        } else {
            defaults.removeObject(forKey: DefaultsKey.requiredBuild)
        }
        defaults.set(url.absoluteString, forKey: DefaultsKey.storeURL)
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private static var currentBuildNumber: Int {
        let raw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return Int(raw) ?? 0
    }

    private static func isNewer(_ candidate: String, than installed: String) -> Bool {
        candidate.compare(installed, options: .numeric) == .orderedDescending
    }

    private var hasNewerVersion: Bool {
        requiredBuild.map { $0 > Self.currentBuildNumber } == true ||
            requiredVersion.map { Self.isNewer($0, than: Self.currentVersion) } == true
    }

    private static let storeCheckInterval: TimeInterval = 15 * 60
}
