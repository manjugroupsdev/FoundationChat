import SwiftUI
import UIKit

/// Reads a team member's live CP arrival OTP back to their manager.
///
/// Presented only from a row the viewer is already allowed to reveal — see
/// `CpOtpRevealAccess`. The reveal call fires as soon as the sheet appears: the
/// manager asking for the sheet IS the decision, and the audit record is
/// written server-side either way, so a second "Reveal" tap would add ceremony
/// without adding a choice.
///
/// The OTP is never cached or persisted — it lives in this view's state only.
struct CpOtpRevealSheet: View {
    @Environment(\.dismiss) private var dismiss

    let cpVisitId: String
    let staffName: String?
    let placeName: String?

    @State private var isLoading = true
    @State private var otp: String?
    @State private var fieldVisitId: String?
    @State private var metaLine: String?
    @State private var errorText: String?
    @State private var didCopy = false

    private let geoAPI = GeoTrackAPIService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Text("Reveal arrival OTP")
                .font(.headline)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else if let otp {
                revealed(otp)
            } else if let errorText {
                // The SERVER's wording ("No active OTP is available. Generate
                // OTP first.", "Arrival OTP is already verified.") — it tells
                // the manager what to do next, which a generic failure message
                // would not.
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            }

            // Shown from the start, not only after a successful reveal: the
            // manager should know the reveal is attributable BEFORE they ask.
            Text("Viewing and copying this OTP is recorded against your name.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            Button("Close") { dismiss() }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .task { await reveal() }
    }

    private var subtitle: String {
        let who = staffName?.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = (who?.isEmpty == false ? who : nil) ?? "This staff member"
        text += "'s active arrival OTP"
        if let placeName, !placeName.isEmpty { text += " at \(placeName)" }
        text += ". Read it out to them — do not share it with the client."
        return text
    }

    @ViewBuilder
    private func revealed(_ code: String) -> some View {
        VStack(spacing: 10) {
            Text(code)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .kerning(6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.10))
                )
                .textSelection(.enabled)

            if let metaLine, !metaLine.isEmpty {
                Text(metaLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(didCopy ? "Copied" : "Copy OTP") { copy(code) }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
    }

    private func reveal() async {
        do {
            let result = try await geoAPI.revealCpArrivalOtp(cpVisitId: cpVisitId)
            isLoading = false
            guard result.success, let code = result.otp, !code.isEmpty else {
                errorText = result.error ?? "No active OTP is available for this visit."
                return
            }
            otp = code
            fieldVisitId = result.fieldVisitId
            metaLine = Self.metaLine(for: result)
        } catch {
            isLoading = false
            if let apiError = error as? GeoTrackAPIError,
               case .badStatus(let code) = apiError,
               code == 404 || code == 405 {
                // The capability is backend-gated and this deployment has not
                // shipped the mobile route yet. Remember it so the action stops
                // being offered for the rest of the session instead of leading
                // every manager into the same dead end.
                CpOtpRevealSupport.markUnsupported()
                errorText = "OTP reveal is not enabled on this server yet. "
                    + "Ask the client for the code, or use Request GM from the staff's trip."
                return
            }
            errorText = error.localizedDescription
        }
    }

    private static func metaLine(for result: CpOtpRevealResponse) -> String {
        var parts: [String] = []
        if let masked = result.contactPhoneMasked, !masked.isEmpty {
            parts.append("Sent to \(masked)")
        }
        if let attempts = result.attempts, attempts > 0 {
            parts.append("\(attempts) failed attempt\(attempts == 1 ? "" : "s")")
        }
        if let resends = result.resendCount, resends > 0 {
            parts.append("resent \(resends) time\(resends == 1 ? "" : "s")")
        }
        return parts.joined(separator: " • ")
    }

    private func copy(_ code: String) {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: code]],
            // A client's verification code, not ordinary copied text: keep it
            // out of Universal Clipboard and expire it rather than leaving it
            // on the pasteboard indefinitely.
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(5 * 60),
            ]
        )
        didCopy = true

        // Best effort: the copy already happened locally, so a failed audit
        // write must not be reported as a failed copy. The server records the
        // reveal itself regardless, so nothing goes unlogged.
        guard let fieldVisitId, !fieldVisitId.isEmpty else { return }
        Task { try? await geoAPI.recordCpArrivalOtpCopied(fieldVisitId: fieldVisitId) }
    }
}
