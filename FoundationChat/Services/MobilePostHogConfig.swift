import Foundation

/// Public, write-only mobile project token; never an MMS or personal API key.
nonisolated enum MobilePostHogConfig {
    static let enabled = true
    static let batchURL = URL(string: "https://us.i.posthog.com/batch/")!
    static let projectToken = "phc_zxNkVWBu5hjr2sMQZEEMJTBMrXGnnT7GmAdLJbhXATqL"
}
