import AVFAudio
import SwiftUI
import UIKit

/// Telecaller dialer: 4×3 keypad, editable Station number persisted to defaults.
/// Tapping Call routes through the Modern Dialer WebRTC softphone when the
/// account has a mapping (token + extension); otherwise it falls back to the
/// Doocti PBX bridge so the agent's deskphone rings first.
///
/// Mirrors the Android `DialerFragment` behaviour. Station defaults key matches
/// Android: `dialer.station`. Default station mirrors Android: `6369487527`.
struct DialerView: View {
    private static let defaultStation = "6369487527"

    @Environment(AuthStore.self) private var authStore
    @ObservedObject private var dialer = ModernDialerBridge.shared

    @AppStorage("dialer.station") private var station: String = DialerView.defaultStation
    @State private var dialed: String = ""
    @State private var isEditingStation: Bool = false
    @State private var callError: String?
    @State private var statusMessage: String?
    @State private var isCalling: Bool = false
    /// Cached Modern Dialer mapping; `nil` until fetched, drives routing.
    @State private var dialerConfig: MobileDialerConfig?

    private let keys: [[DialerKey]] = [
        [.digit("1"), .digit("2", subtitle: "ABC"), .digit("3", subtitle: "DEF")],
        [.digit("4", subtitle: "GHI"), .digit("5", subtitle: "JKL"), .digit("6", subtitle: "MNO")],
        [.digit("7", subtitle: "PQRS"), .digit("8", subtitle: "TUV"), .digit("9", subtitle: "WXYZ")],
        [.symbol("*"), .digit("0", subtitle: "+"), .symbol("#")],
    ]

    var body: some View {
        VStack(spacing: 0) {
            stationField
            displaySection
            keypad
            callRow
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .navigationTitle("Dialer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Cannot Call", isPresented: Binding(
            get: { callError != nil },
            set: { if !$0 { callError = nil } }
        )) {
            Button("OK", role: .cancel) { callError = nil }
        } message: {
            Text(callError ?? "")
        }
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote.weight(.medium))
                    .font(AppModuleFont.rowMetaSemibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        // In-call panel driven by the Modern Dialer bridge events.
        .overlay {
            if dialer.stage != .idle {
                CallPanelView(dialer: dialer)
                    .transition(.opacity)
            }
        }
        // Hidden 1×1 WebRTC softphone host — kept attached to the hierarchy so
        // mic capture works. Never visible.
        .background(
            ModernDialerWebViewContainer()
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
        )
        .task { await prefetchDialerConfig() }
        // Surface bridge toasts (placing/timeout) in the existing status pill.
        .onChange(of: dialer.toast) { _, newValue in
            statusMessage = newValue
        }
    }

    // MARK: - Sections

    private var stationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STATION")
                .font(AppModuleFont.rowMetaSemibold)
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                TextField("Station number", text: $station)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .autocorrectionDisabled()
                    .onSubmit { isEditingStation = false }
                if !station.isEmpty {
                    Button {
                        station = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.top, 8)
    }

    private var displaySection: some View {
        VStack(spacing: 4) {
            Text(dialed.isEmpty ? " " : dialed)
                .font(.system(size: 40, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            if !dialed.isEmpty {
                Text(formattedPreview(dialed))
                    .font(AppModuleFont.rowMeta)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var keypad: some View {
        VStack(spacing: 14) {
            ForEach(0..<keys.count, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(keys[row]) { key in
                        DialerKeyButton(key: key) {
                            handleKey(key)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var callRow: some View {
        ZStack {
            Button {
                placeCall()
            } label: {
                Group {
                    if isCalling {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "phone.fill")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 72, height: 72)
                .background(Circle().fill((callEnabled && !isCalling) ? Color.green : Color.green.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!callEnabled || isCalling)
            .accessibilityLabel("Call")

            HStack {
                Spacer()

                Button {
                    if !dialed.isEmpty { dialed.removeLast() }
                } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.title3.weight(.regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .disabled(dialed.isEmpty)
                .accessibilityLabel("Backspace")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Actions

    private var callEnabled: Bool {
        !sanitizedNumberForCall.isEmpty
    }

    private var sanitizedNumberForCall: String {
        let allowed = Set("0123456789+*#")
        return dialed.filter { allowed.contains($0) }
    }

    private func handleKey(_ key: DialerKey) {
        switch key {
        case .digit(let value, _):
            dialed.append(value)
        case .symbol(let value):
            dialed.append(value)
        }
    }

    private func placeCall() {
        let number = sanitizedNumberForCall
        let digits = number.filter(\.isNumber)
        guard digits.count >= 10 else {
            callError = "Enter a valid phone number (min 10 digits)"
            return
        }
        guard !isCalling else { return }
        isCalling = true
        statusMessage = "Checking dialer…"
        Task {
            let config = dialerConfig ?? (await fetchDialerConfig())
            if let config { dialerConfig = config }
            await routeCall(digits: digits, config: config)
        }
    }

    /// Route to the Modern Dialer softphone when the account is configured
    /// (token + extension); otherwise fall back to Doocti. Mirrors the Android
    /// `DialerFragment.routeCall`.
    @MainActor
    private func routeCall(digits: String, config: MobileDialerConfig?) async {
        let token = config?.mapping?.token?.nonBlank
        let ext = config?.mapping?.`extension`?.nonBlank
        if config?.configured == true, token != nil, ext != nil, let config {
            let granted = await requestMicPermission()
            guard granted else {
                isCalling = false
                statusMessage = nil
                callError = "Microphone permission is required for Modern Dialer calls"
                return
            }
            isCalling = false
            statusMessage = nil
            dialer.startOutboundCall(destination: digits, config: config)
        } else if config == nil {
            // Couldn't reach the config service at all — don't place a call on
            // the (potentially dead) Doocti endpoint; tell the user to retry.
            isCalling = false
            statusMessage = nil
            callError = "Couldn't reach the dialer service. Check your connection and try again."
        } else {
            await placeDooctiCall(digits: digits)
        }
    }

    /// Existing Doocti click-to-call path, preserved unchanged as the fallback.
    @MainActor
    private func placeDooctiCall(digits: String) async {
        statusMessage = "Placing call…"
        let stationNumber = station.filter(\.isNumber).isEmpty
            ? Self.defaultStation
            : station.filter(\.isNumber)
        defer { isCalling = false }
        do {
            _ = try await TelecallerConvexAPIService.dialDoocti(
                phoneNumber: digits,
                station: stationNumber
            )
            statusMessage = "Call placed — your phone will ring shortly"
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            statusMessage = nil
        } catch {
            statusMessage = nil
            callError = "Call failed: \(error.localizedDescription)"
        }
    }

    /// Fetch the Modern Dialer mapping with a small retry (mirrors Android's
    /// `fetchDialerConfigWithRetry` — a transient failure must not be mistaken
    /// for "no mapping" and wrongly drop to Doocti).
    private func fetchDialerConfig() async -> MobileDialerConfig? {
        guard let token = authStore.currentSession?.token else { return nil }
        for attempt in 0..<3 {
            if let result = try? await TelecallerConvexAPIService.getMobileDialerConfig(token: token) {
                return result
            }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        }
        return nil
    }

    private func prefetchDialerConfig() async {
        if dialerConfig == nil { dialerConfig = await fetchDialerConfig() }
    }

    private func requestMicPermission() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func formattedPreview(_ value: String) -> String {
        // Light-touch formatting hint — does not mutate the dialed value.
        let digits = value.filter(\.isNumber)
        switch digits.count {
        case 10:
            let a = digits.prefix(5)
            let b = digits.suffix(5)
            return "\(a) \(b)"
        case 11:
            let a = digits.prefix(1)
            let mid = digits.dropFirst(1).prefix(5)
            let last = digits.suffix(5)
            return "\(a) \(mid) \(last)"
        default:
            return value
        }
    }
}

// MARK: - Key

private enum DialerKey: Identifiable, Hashable {
    case digit(String, subtitle: String? = nil)
    case symbol(String)

    var id: String { primary }

    var primary: String {
        switch self {
        case .digit(let v, _): return v
        case .symbol(let v): return v
        }
    }

    var subtitle: String? {
        if case .digit(_, let s) = self { return s }
        return nil
    }
}

private struct DialerKeyButton: View {
    let key: DialerKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(key.primary)
                    .font(.system(size: 30, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                if let subtitle = key.subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .font(AppModuleFont.rowMetaSemibold)
                        .foregroundStyle(.secondary)
                        .tracking(1)
                } else {
                    Text(" ")
                        .font(.caption2)
                        .font(AppModuleFont.rowMeta)
                }
            }
            .frame(width: 78, height: 78)
            .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(key.primary))
    }
}

// MARK: - In-call panel

/// Modern Dialer in-call overlay. Driven entirely by `ModernDialerBridge` events.
/// Pickup/Reject are rendered for the (out-of-scope, never-triggered) incoming
/// case; outbound calls only ever reach Connecting → In call.
private struct CallPanelView: View {
    @ObservedObject var dialer: ModernDialerBridge

    private var statusText: String {
        switch dialer.stage {
        case .incoming: return "Incoming call"
        case .connecting: return "Connecting"
        case .inCall: return "In call"
        case .idle: return ""
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(statusText)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(dialer.peerNumber?.nonBlank ?? "Modern Dialer")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                if dialer.stage == .inCall {
                    HStack(spacing: 40) {
                        panelButton(
                            title: dialer.muted ? "Unmute" : "Mute",
                            systemImage: dialer.muted ? "mic.slash.fill" : "mic.fill",
                            tint: dialer.muted ? .orange : .gray
                        ) { dialer.toggleMute() }
                        panelButton(
                            title: dialer.held ? "Resume" : "Hold",
                            systemImage: dialer.held ? "play.fill" : "pause.fill",
                            tint: dialer.held ? .orange : .gray
                        ) { dialer.toggleHold() }
                    }
                }

                HStack(spacing: 40) {
                    if dialer.stage == .incoming {
                        panelButton(title: "Pickup", systemImage: "phone.fill", tint: .green) {
                            dialer.pickup()
                        }
                    }
                    panelButton(
                        title: dialer.stage == .incoming ? "Reject" : "Hang up",
                        systemImage: "phone.down.fill",
                        tint: .red
                    ) { dialer.hangup() }
                }
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding()
        }
    }

    private func panelButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(tint))
                Text(title)
                    .font(AppModuleFont.rowMetaSemibold)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

#Preview {
    NavigationStack { DialerView() }
        .environment(AuthStore())
}
