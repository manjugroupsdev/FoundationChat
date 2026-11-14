import Combine
import SwiftUI
import UIKit

/// The app's one in-app notice (same as Android's Floater): a small tinted
/// capsule at the top of the screen ("Server busy · retrying",
/// "Leave applied"). Every error popup and HTTP failure lands here.
///
///     Floater.shared.error("Couldn't save leave")
///     Floater.shared.success("Leave applied")
///     Floater.shared.show(anyText)          // kind picked from the text
///     Floater.shared.show(error: error)     // readable text for any failure
///     .floaterAlert($errorMessage)          // view modifier for error state
///
/// - Lives in its own pass-through window above sheets and alerts; touches
///   outside a capsule reach the app underneath, and it never takes focus.
/// - Up to three capsules stack; the same text twice restarts its timer.
/// - One line by default; tapping a cut-off capsule shows the full text,
///   tapping again dismisses it. It hides itself after a few seconds.
/// - Raw text is cleaned first: "HTTP 500 …", "(HTTP 413)", URLError
///   descriptions and JSON error bodies become plain sentences.
@MainActor
final class Floater: ObservableObject {
    static let shared = Floater()

    nonisolated enum Kind: Equatable, Sendable {
        case error, warning, offline, success, info

        var symbol: String {
            switch self {
            case .error: return "exclamationmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .offline: return "icloud.slash"
            case .success: return "checkmark"
            case .info: return "info.circle"
            }
        }

        var tint: Color {
            switch self {
            case .error: return Color(red: 0.85, green: 0.18, blue: 0.13)
            case .warning, .offline: return Color(red: 0.80, green: 0.42, blue: 0.02)
            case .success: return Color(red: 0.03, green: 0.58, blue: 0.33)
            case .info: return Color(red: 0.04, green: 0.38, blue: 0.79)
            }
        }

        var seconds: Double {
            switch self {
            case .error: return 4.5
            case .warning, .offline: return 3.8
            case .success: return 2.6
            case .info: return 3.0
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let kind: Kind
        var expanded = false
    }

    @Published fileprivate(set) var items: [Item] = []
    fileprivate var capsuleFrames: [UUID: CGRect] = [:]
    private var timers: [UUID: Task<Void, Never>] = [:]
    private var window: FloaterWindow?

    private static let maxVisible = 3

    func error(_ text: String?, file: String = #fileID) { show(text, kind: .error, file: file) }
    func warning(_ text: String?, file: String = #fileID) { show(text, kind: .warning, file: file) }
    func success(_ text: String?, file: String = #fileID) { show(text, kind: .success, file: file) }
    func info(_ text: String?, file: String = #fileID) { show(text, kind: .info, file: file) }

    /// Readable capsule for any failure (URLError, server error, decoding…).
    func show(error: Error, file: String = #fileID) {
        guard let notice = FloaterText.notice(for: error) else { return }
        show(notice.text, kind: notice.kind, file: file)
    }

    /// Shows [text]; [kind] nil = picked from the text.
    func show(_ text: String?, kind: Kind? = nil, file: String = #fileID) {
        let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let notice = FloaterText.notice(for: raw) else { return }
        let resolved = kind ?? notice.kind
        // An error the user saw = a flow that did not finish (Mobile → Issues).
        IssueReporter.shared.onNotice(notice.text, kind: resolved, file: file)
        if let existing = items.first(where: { $0.text == notice.text }) {
            schedule(existing.id, after: resolved.seconds)
            return
        }
        guard installWindow() else { return }
        while items.count >= Self.maxVisible, let oldest = items.first { remove(oldest.id) }
        let item = Item(text: notice.text, kind: resolved)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { items.append(item) }
        UIAccessibility.post(notification: .announcement, argument: notice.text)
        schedule(item.id, after: min(resolved.seconds + Double(notice.text.count) * 0.025, 7))
    }

    fileprivate func tap(_ item: Item, truncated: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if truncated && !items[index].expanded {
            withAnimation(.easeOut(duration: 0.2)) { items[index].expanded = true }
            schedule(item.id, after: 8)
        } else {
            remove(item.id)
        }
    }

    fileprivate func remove(_ id: UUID) {
        timers[id]?.cancel()
        timers[id] = nil
        capsuleFrames[id] = nil
        withAnimation(.easeIn(duration: 0.18)) { items.removeAll { $0.id == id } }
    }

    private func schedule(_ id: UUID, after seconds: Double) {
        timers[id]?.cancel()
        timers[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.remove(id)
        }
    }

    private func installWindow() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return false
        }
        if let window, window.windowScene === scene { return true }
        let window = FloaterWindow(windowScene: scene)
        window.floater = self
        // Above sheets and alerts, below the status bar.
        window.windowLevel = UIWindow.Level.alert + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: FloaterStack(floater: self))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.overrideUserInterfaceStyle = scene.windows.first(where: { $0.isKeyWindow })?.overrideUserInterfaceStyle
            ?? .unspecified
        window.isHidden = false
        self.window = window
        return true
    }
}

/// Lets touches through everywhere except on a capsule.
private final class FloaterWindow: UIWindow {
    weak var floater: Floater?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let floater else { return nil }
        let hit = MainActor.assumeIsolated {
            floater.capsuleFrames.values.contains { $0.insetBy(dx: -4, dy: -4).contains(point) }
        }
        return hit ? super.hitTest(point, with: event) : nil
    }

    // Never steal the keyboard from the field being typed in.
    override var canBecomeKey: Bool { false }
}

private struct FloaterStack: View {
    @ObservedObject var floater: Floater

    var body: some View {
        VStack(spacing: 6) {
            ForEach(floater.items) { item in
                FloaterCapsule(item: item) { truncated in floater.tap(item, truncated: truncated) }
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { floater.capsuleFrames[item.id] = proxy.frame(in: .global) }
                                .onChange(of: proxy.frame(in: .global)) { _, frame in
                                    floater.capsuleFrames[item.id] = frame
                                }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct FloaterCapsule: View {
    let item: Floater.Item
    let onTap: (Bool) -> Void
    @State private var fullHeight: CGFloat = 0
    @State private var lineHeight: CGFloat = 0

    private var truncated: Bool { fullHeight > lineHeight + 1 }

    var body: some View {
        HStack(alignment: item.expanded ? .top : .center, spacing: 8) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(item.kind.tint)
                .accessibilityHidden(true)
            Text(item.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(item.kind.tint)
                .lineLimit(item.expanded ? 8 : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear { lineHeight = proxy.size.height }
                    }
                )
                .background(
                    // Same text unconstrained: tells whether one line cuts it off.
                    Text(item.text)
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(GeometryReader { proxy in
                            Color.clear.onAppear { fullHeight = proxy.size.height }
                        })
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: item.expanded ? 16 : 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: item.expanded ? 16 : 20, style: .continuous)
                        .fill(item.kind.tint.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: item.expanded ? 16 : 20, style: .continuous)
                        .stroke(item.kind.tint.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap(truncated) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

extension View {
    /// Shows [message] as a top capsule whenever it becomes non-nil, then
    /// clears it (what the old OK-only error alert's OK button did).
    func floaterAlert(_ message: Binding<String?>, kind: Floater.Kind? = nil, file: String = #fileID) -> some View {
        onChange(of: message.wrappedValue) { _, newValue in
            guard let newValue, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Floater.shared.show(newValue, kind: kind, file: file)
            message.wrappedValue = nil
        }
    }

    /// Same, for a Bool flag with a separate message (alerts bound to `$showError`).
    func floaterAlert(isPresented: Binding<Bool>, message: String?, kind: Floater.Kind? = nil, file: String = #fileID) -> some View {
        onChange(of: isPresented.wrappedValue) { _, shown in
            guard shown else { return }
            Floater.shared.show(message, kind: kind, file: file)
            isPresented.wrappedValue = false
        }
    }
}

/// Turns any message or error into one readable sentence and a kind.
nonisolated enum FloaterText {
    struct Notice {
        let text: String
        let kind: Floater.Kind
    }

    static func forStatus(_ code: Int) -> Notice {
        switch code {
        case 400: return Notice(text: "The server couldn't accept this request. Check the details and try again.", kind: .warning)
        case 401: return Notice(text: "Your session expired. Sign in again.", kind: .warning)
        case 403: return Notice(text: "You don't have permission to do this.", kind: .warning)
        case 404: return Notice(text: "Not found. It may have been removed or isn't available yet.", kind: .warning)
        case 405: return Notice(text: "This action isn't supported by the server yet. Update the app.", kind: .warning)
        case 408: return Notice(text: timeout, kind: .offline)
        case 409: return Notice(text: "This was changed by someone else. Refresh and try again.", kind: .warning)
        case 410: return Notice(text: "This is no longer available.", kind: .warning)
        case 413: return Notice(text: "That file is too large to upload.", kind: .warning)
        case 415: return Notice(text: "That file type isn't supported.", kind: .warning)
        case 422: return Notice(text: "Some details are missing or invalid. Check the form and try again.", kind: .warning)
        case 426: return Notice(text: "Update the app to keep using this feature.", kind: .warning)
        case 429: return Notice(text: "Too many requests. Wait a moment and try again.", kind: .warning)
        case 500: return Notice(text: "Something went wrong on the server. Try again.", kind: .error)
        case 502, 503: return Notice(text: "The server is busy right now. Try again shortly.", kind: .error)
        case 504: return Notice(text: timeout, kind: .offline)
        case 400..<500: return Notice(text: "The request couldn't be completed (\(code)). Try again.", kind: .warning)
        case 500..<600: return Notice(text: "Server error (\(code)). Try again shortly.", kind: .error)
        default: return Notice(text: "Something went wrong. Try again.", kind: .error)
        }
    }

    private static let timeout = "The server took too long to respond. Try again."
    private static let offline = "No internet connection. Check your network and try again."
    private static let ssl = "Secure connection failed. Check the phone's date and time, then try again."
    private static let lost = "Connection lost. Check your network and try again."

    /// nil = nothing to show (a cancelled request).
    static func notice(for error: Error) -> Notice? {
        if let url = error as? URLError {
            switch url.code {
            case .cancelled: return nil
            case .timedOut: return Notice(text: timeout, kind: .offline)
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .internationalRoamingOff, .dataNotAllowed:
                return Notice(text: offline, kind: .offline)
            case .networkConnectionLost: return Notice(text: lost, kind: .offline)
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
                return Notice(text: ssl, kind: .offline)
            default: break
            }
        }
        if error is CancellationError { return nil }
        return notice(for: error.localizedDescription)
    }

    private static let stockPhrases: Set<String> = [
        "ok", "bad request", "unauthorized", "forbidden", "not found", "method not allowed", "request timeout",
        "conflict", "gone", "payload too large", "unsupported media type", "unprocessable entity",
        "unprocessable content", "upgrade required", "too many requests", "internal server error",
        "bad gateway", "service unavailable", "gateway timeout",
    ]
    private static let barePrefixes: Set<String> = [
        "error", "failed", "failure", "exception", "request failed", "server returned", "server error",
    ]

    /// nil = nothing to show.
    static func notice(for raw: String) -> Notice? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("{"), let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = (json["error"] as? String) ?? (json["message"] as? String),
           !message.isEmpty {
            text = message
        }
        if let range = text.range(of: "Uncaught Error:") {
            text = String(text[range.upperBound...])
                .components(separatedBy: "\n").first?
                .trimmingCharacters(in: .whitespaces) ?? text
        }
        let lower = text.lowercased()
        if lower == "cancelled" || lower == "canceled" { return nil }
        if let network = networkNotice(lower) { return network }

        if let match = text.range(of: #"\(?\bHTTP\s+(\d{3})\b\)?[\s:.\-]*"#, options: [.regularExpression, .caseInsensitive]) {
            let token = String(text[match])
            let code = Int(token.filter(\.isNumber).prefix(3)) ?? 0
            let before = String(text[..<match.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: " :-.").union(.whitespaces))
            var after = String(text[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            if after.trimmingCharacters(in: CharacterSet(charactersIn: ".) ")).isEmpty
                || stockPhrases.contains(after.lowercased()) {
                after = ""
            }
            let prefixOnly = before.isEmpty || barePrefixes.contains(before.lowercased())
            let status = forStatus(code)
            if !after.isEmpty {
                return Notice(text: capitalised(prefixOnly ? after : "\(before): \(after)"), kind: status.kind)
            }
            return prefixOnly ? status : Notice(text: "\(capitalised(before)). \(status.text)", kind: status.kind)
        }
        if let label = text.range(of: #"^(?i)(error|exception)\s*:\s*"#, options: .regularExpression) {
            text = String(text[label.upperBound...])
        }
        guard !text.isEmpty else { return Notice(text: "Something went wrong. Try again.", kind: .error) }
        return Notice(text: capitalised(text), kind: classify(text.lowercased()))
    }

    private static func networkNotice(_ lower: String) -> Notice? {
        if lower.contains("request timed out") || lower == "timeout" || lower.contains("timed out") {
            return Notice(text: timeout, kind: .offline)
        }
        if lower.contains("internet connection appears to be offline")
            || lower.contains("could not connect to the server")
            || lower.contains("hostname could not be found") {
            return Notice(text: offline, kind: .offline)
        }
        if lower.contains("network connection was lost") { return Notice(text: lost, kind: .offline) }
        if lower.contains("ssl error") || lower.contains("secure connection") && lower.contains("fail") {
            return Notice(text: ssl, kind: .offline)
        }
        return nil
    }

    private static let offlineWords = [
        "no internet", "offline", "no network", "network error", "check your network", "took too long",
    ]
    private static let errorWords = [
        "fail", "error", "couldn't", "could not", "unable", "went wrong", "not saved", "crash", "exception",
    ]
    private static let warningWords = [
        "please", "required", "select ", "enter ", "must", "invalid", "not allowed", "denied", "permission",
        "expired", "already", "not found", "cannot", "can't", "too many", "limit", "exceed", "missing",
        "need", "allow", "only ", "not available", "isn't available", "wait", "too far", "outside",
    ]
    private static let successWords = [
        "saved", "applied", "created", "updated", "approved", "submitted", "sent", "uploaded", "deleted",
        "removed", "added", "copied", "done", "success", "marked", "assigned", "completed", "cancelled",
        "canceled", "rejected", "verified", "confirmed", "started", "stopped", "scheduled", "postponed",
        "punched", "clocked", "shared", "downloaded", "restored", "accepted", "logged",
    ]

    private static func classify(_ lower: String) -> Floater.Kind {
        if offlineWords.contains(where: lower.contains) { return .offline }
        if errorWords.contains(where: lower.contains) { return .error }
        if warningWords.contains(where: lower.contains) { return .warning }
        if successWords.contains(where: lower.contains) { return .success }
        return .info
    }

    private static func capitalised(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
