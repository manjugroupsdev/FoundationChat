import AVFAudio
import AVFoundation
import Combine
import SwiftUI
import UIKit
import WebKit

// MARK: - Modern Dialer (WebRTC softphone) — OUTBOUND only
//
// iOS port of the Android `ModernDialerWebViewBridge`
// (app/.../notifications/ModernDialerWebViewBridge.kt).
//
// The "call engine" is a hidden `WKWebView` that loads a HOST html page whose
// origin is spoofed to https://mg.theairix.com (via `loadHTMLString(_,baseURL:)`,
// the iOS analogue of Android's `loadDataWithBaseURL`). That host page embeds the
// real hosted dialer https://dialer.theairix.com/embed/agent in an <iframe
// allow="microphone; autoplay; camera"> and relays messages both directions:
//   • parent → iframe : `window.__mdSend(json)` → `frame.contentWindow.postMessage`
//   • iframe → native : `window.webkit.messageHandlers.MconnectDialerBridge.postMessage(...)`
//
// Control commands  : {source:"modern-dialer-control", type:"call"|"pickup"|
//                       "hangup"|"set-muted"|"set-hold", ...}
// Inbound events    : ready, phone:registered, call:incoming, call:ringing-out,
//                     call:answered, call:ended, call:error, …
//
// Commands queue until the page has loaded AND the softphone has registered, with
// a ~6s fallback flush so a call is never silently stuck "connecting".
//
// INCOMING-call handling is intentionally NOT ported — that needs CallKit /
// PushKit / APNs-VoIP infrastructure and is out of scope. The incoming UI paths
// exist (`stage == .incoming`, pickup/reject) but are never triggered here.

// MARK: - Event & call-state model

/// A parsed `modern-dialer` event coming up from the iframe.
struct ModernDialerEvent {
    let type: String
    let payload: [String: Any]

    func string(_ key: String) -> String? { payload[key] as? String }
}

enum ModernCallStage: Equatable {
    case idle
    case incoming
    case connecting
    case inCall
}

@MainActor
final class ModernDialerBridge: NSObject, ObservableObject {

    static let shared = ModernDialerBridge()

    // Mirrors the Android constants exactly.
    private let dialerOrigin = "https://dialer.theairix.com"
    /// Origin the host page runs as — the trusted PARENT the embed expects. Gives
    /// the WebView an https origin so getUserMedia (mic) is allowed and the iframe
    /// accepts control messages from a proper parent.
    private let hostBaseURL = "https://mg.theairix.com"
    private let jsInterface = "MconnectDialerBridge"
    /// If registration is never reported, flush queued commands anyway after this.
    private let fallbackFlushMs: Int = 6_000
    /// Fail a stuck "Connecting" if no progress event arrives.
    private let connectingTimeoutSec: Double = 40

    // Published call-panel state (drives `CallPanelView`).
    @Published private(set) var stage: ModernCallStage = .idle
    @Published private(set) var peerNumber: String?
    @Published private(set) var muted: Bool = false
    @Published private(set) var held: Bool = false
    @Published var toast: String?

    private var webView: WKWebView?
    private var loadedURL: String?
    private var pageLoaded = false
    private var phoneRegistered = false
    private var fallbackFlushPosted = false
    private var pendingCommands: [(type: String, payload: [String: Any])] = []

    private var connectingTimeoutTask: Task<Void, Never>?
    private let ringback = RingbackTonePlayer()

    // MARK: WebView lifecycle

    /// Build (once) the hidden WebView. Returned to the SwiftUI representable so it
    /// is attached to the window hierarchy — WebRTC mic capture is most reliable
    /// when the WebView lives in a window (matches the Android decor-view attach).
    func makeWebViewIfNeeded() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let ucc = WKUserContentController()
        ucc.add(self, name: jsInterface)
        config.userContentController = ucc

        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.isOpaque = false
        view.backgroundColor = .clear
        view.alpha = 0
        view.isUserInteractionEnabled = false
        webView = view
        return view
    }

    /// Load the host page (which embeds the dialer iframe) once per token/deviceId.
    func ensureLoaded(config: MobileDialerConfig) {
        guard let token = config.mapping?.token, !token.isEmpty else { return }
        let url = buildEmbedURL(token: token)
        let view = makeWebViewIfNeeded()
        if loadedURL != url {
            pageLoaded = false
            phoneRegistered = false
            fallbackFlushPosted = false
            loadedURL = url
            view.loadHTMLString(buildHostHTML(embedURL: url), baseURL: URL(string: hostBaseURL))
        }
    }

    // MARK: Outbound call control

    /// Start an OUTBOUND call. Assumes mic permission is already granted and the
    /// caller has (or will) attach the hidden WebView to the hierarchy.
    func startOutboundCall(destination: String, config: MobileDialerConfig) {
        peerNumber = destination
        muted = false
        held = false
        stage = .connecting
        activateAudioSession()
        ensureLoaded(config: config)
        send("call", payload: ["destination": destination])
        startConnectingTimeout()
        showToast("Placing call…")
    }

    func pickup() {
        send("pickup")
        stage = .connecting
    }

    /// Reject (incoming) or hang up (outbound) — both map to "hangup" on the wire.
    func hangup() {
        send("hangup")
        resetCallState()
    }

    func toggleMute() {
        muted.toggle()
        send("set-muted", payload: ["muted": muted])
    }

    func toggleHold() {
        held.toggle()
        send("set-hold", payload: ["held": held])
    }

    // MARK: Command queue

    private func send(_ type: String, payload: [String: Any] = [:]) {
        // Queue until page loaded AND softphone registered — matching the web
        // dialer, which waits for phoneState==="registered" before dispatching.
        guard pageLoaded, phoneRegistered else {
            pendingCommands.append((type, payload))
            return
        }
        evaluateCommand(type: type, payload: payload)
    }

    private func maybeFlush() {
        guard pageLoaded, phoneRegistered else { return }
        let commands = pendingCommands
        pendingCommands.removeAll()
        for command in commands { evaluateCommand(type: command.type, payload: command.payload) }
    }

    /// Safety net: if registration is never confirmed, send queued commands anyway.
    private func scheduleFallbackFlush() {
        guard !fallbackFlushPosted else { return }
        fallbackFlushPosted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(fallbackFlushMs)) { [weak self] in
            guard let self else { return }
            if !self.phoneRegistered, self.pageLoaded, !self.pendingCommands.isEmpty {
                let commands = self.pendingCommands
                self.pendingCommands.removeAll()
                for command in commands { self.evaluateCommand(type: command.type, payload: command.payload) }
            }
        }
    }

    private func evaluateCommand(type: String, payload: [String: Any]) {
        var dict: [String: Any] = ["source": "modern-dialer-control", "type": type]
        for (key, value) in payload { dict[key] = value }
        guard
            let data = try? JSONSerialization.data(withJSONObject: dict),
            let json = String(data: data, encoding: .utf8)
        else { return }
        // Hand the command to the host page, which posts it to the iframe's
        // contentWindow (the dialer) with the trusted parent origin.
        webView?.evaluateJavaScript("window.__mdSend(\(json))", completionHandler: nil)
    }

    // MARK: Inbound events

    private func handleRawEvent(_ raw: String) {
        guard
            let data = raw.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = parsed["type"] as? String
        else { return }
        onDialerMessage(type: type, parsed: parsed)
    }

    /// Update registration from the event, flush queued commands once registered,
    /// then drive the call-panel state. Mirrors the Android bridge + fragment.
    private func onDialerMessage(type: String, parsed: [String: Any]) {
        switch type {
        case "ready":
            let ps = parsed["phoneState"] as? String
            phoneRegistered = (ps == nil || ps == "registered")
            maybeFlush()
        case "phone:registered":
            phoneRegistered = true
            maybeFlush()
        case "phone:state", "phone:status":
            let st = (parsed["state"] as? String) ?? (parsed["status"] as? String)
            phoneRegistered = (st == "registered")
            if phoneRegistered { maybeFlush() }
        case "phone:unregistered":
            phoneRegistered = false
        default:
            break
        }

        let event = ModernDialerEvent(type: type, payload: parsed)
        switch type {
        case "call:incoming":
            // NOTE: outbound-only port — this path is never triggered without
            // CallKit/PushKit. Rendered defensively to match Android.
            peerNumber = event.string("from") ?? "Incoming call"
            stage = .incoming
            muted = false
            held = false
        case "call:ringing-out":
            cancelConnectingTimeout()
            ringback.start()
            peerNumber = event.string("to") ?? peerNumber
            stage = .connecting
        case "call:picked-up":
            cancelConnectingTimeout()
            ringback.stop()
            stage = .connecting
        case "call:answered":
            cancelConnectingTimeout()
            ringback.stop()
            peerNumber = event.string("from") ?? event.string("to") ?? peerNumber
            stage = .inCall
        case "call:ended", "call:error", "call:incoming-suppressed":
            resetCallState()
        default:
            break
        }
    }

    private func resetCallState() {
        cancelConnectingTimeout()
        ringback.stop()
        deactivateAudioSession()
        stage = .idle
        peerNumber = nil
        muted = false
        held = false
    }

    // MARK: Connecting timeout

    private func startConnectingTimeout() {
        cancelConnectingTimeout()
        connectingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.connectingTimeoutSec ?? 40) * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if self.stage == .connecting {
                self.showToast("Call didn't connect. Check the station/registration and try again.")
                self.resetCallState()
            }
        }
    }

    private func cancelConnectingTimeout() {
        connectingTimeoutTask?.cancel()
        connectingTimeoutTask = nil
    }

    private func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }

    // MARK: Audio session

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Host HTML + embed URL

    private func buildEmbedURL(token: String) -> String {
        let deviceId = LoginDeviceInfo.persistentDeviceId() ?? "mconnect-ios"
        return "\(dialerOrigin)/embed/agent?token=\(urlEncode(token))&deviceId=\(urlEncode(deviceId))"
    }

    private func urlEncode(_ value: String) -> String {
        // application/x-www-form-urlencoded style, matching Android URLEncoder.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Host page that embeds the dialer in an iframe and relays postMessages —
    /// mirrors the Android `buildHostHtml`, adapted so iframe → native uses the
    /// WKWebView message handler (`window.webkit.messageHandlers.<name>`).
    private func buildHostHTML(embedURL: String) -> String {
        let safeSrc = embedURL.replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#fff}
        iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style></head>
        <body>
        <iframe id="mdframe" src="\(safeSrc)" allow="microphone; autoplay; camera"></iframe>
        <script>
        (function(){
          var ORIGIN = "\(dialerOrigin)";
          var frame = document.getElementById('mdframe');
          // native -> dialer: post the control message to the iframe window.
          window.__mdSend = function(d){
            try { frame.contentWindow.postMessage(d, ORIGIN); }
            catch(e){ console.error('mdSend failed', e); }
          };
          // dialer -> native: relay any 'modern-dialer' event from the iframe.
          window.addEventListener('message', function(ev){
            try {
              if (ev.origin !== ORIGIN) return;
              var d = ev.data;
              if (d && d.source === 'modern-dialer') {
                window.webkit.messageHandlers.\(jsInterface).postMessage(JSON.stringify(d));
              }
            } catch(e){}
          });
          frame.addEventListener('load', function(){ console.log('md iframe loaded'); });
        })();
        </script>
        </body></html>
        """
    }
}

// MARK: - WebKit delegates

extension ModernDialerBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == jsInterface, let raw = message.body as? String else { return }
        handleRawEvent(raw)
    }
}

extension ModernDialerBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The host page's own script relays messages to/from the iframe.
        pageLoaded = true
        maybeFlush()
        scheduleFallbackFlush()
    }
}

extension ModernDialerBridge: WKUIDelegate {
    /// Grant the softphone's getUserMedia mic request (deny camera — audio only,
    /// mirroring the Android `onPermissionRequest` filter).
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }
}

// MARK: - Hidden WebView host (SwiftUI)

/// Attaches the shared engine's hidden WebView to the SwiftUI hierarchy so WebRTC
/// mic capture works. Rendered ~1×1 and fully transparent so the user never sees
/// it (mirrors the Android invisible decor-view attach).
struct ModernDialerWebViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        ModernDialerBridge.shared.makeWebViewIfNeeded()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Ringback tone

/// Plays a looping ringback cadence (440+480 Hz, 2s on / 4s off) so the agent
/// hears the outbound call ringing. Simple, self-contained — synthesizes a WAV
/// once and loops it via AVAudioPlayer. (Android used ToneGenerator's
/// TONE_SUP_RINGTONE, which has no direct iOS equivalent.)
final class RingbackTonePlayer {
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        guard let data = RingbackTonePlayer.makeWav() else { return }
        player = try? AVAudioPlayer(data: data)
        player?.numberOfLoops = -1
        player?.volume = 0.5
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private static func makeWav() -> Data? {
        let sampleRate = 8000.0
        let toneDuration = 2.0
        let silenceDuration = 4.0
        let totalSamples = Int((toneDuration + silenceDuration) * sampleRate)
        let toneSamples = Int(toneDuration * sampleRate)
        var samples = [Int16](repeating: 0, count: totalSamples)
        let amplitude = 0.28 * 32767.0
        for i in 0..<toneSamples {
            let t = Double(i) / sampleRate
            let value = (sin(2 * .pi * 440 * t) + sin(2 * .pi * 480 * t)) / 2
            samples[i] = Int16(max(-32767, min(32767, value * amplitude)))
        }

        var data = Data()
        func appendString(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func appendU32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func appendU16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }

        let dataSize = samples.count * 2
        let byteRate = UInt32(sampleRate) * 2
        appendString("RIFF"); appendU32(UInt32(36 + dataSize)); appendString("WAVE")
        appendString("fmt "); appendU32(16); appendU16(1); appendU16(1)
        appendU32(UInt32(sampleRate)); appendU32(byteRate); appendU16(2); appendU16(16)
        appendString("data"); appendU32(UInt32(dataSize))
        for sample in samples { var x = sample.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        return data
    }
}
