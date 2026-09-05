import AVFAudio
import CallKit
import Foundation
import PushKit

extension Notification.Name {
    static let didRegisterModernDialerVoIPToken = Notification.Name("didRegisterModernDialerVoIPToken")
    static let didInvalidateModernDialerVoIPToken = Notification.Name("didInvalidateModernDialerVoIPToken")
    static let didAnswerModernDialerCall = Notification.Name("didAnswerModernDialerCall")
    static let didEndModernDialerCall = Notification.Name("didEndModernDialerCall")
    static let didFailModernDialerMedia = Notification.Name("didFailModernDialerMedia")
}

enum ModernDialerVoIPTokenCache {
    private static let key = "modernDialer.voipToken"
    static var token: String? {
        get { UserDefaults.standard.string(forKey: key)?.nonBlank }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Native incoming-call surface for the Modern Dialer. PushKit wakes the app
/// for VoIP pushes and CallKit owns ringing, lock-screen UI, and system audio.
final class ModernDialerCallKitCoordinator: NSObject {
    static let shared = ModernDialerCallKitCoordinator()

    private let provider: CXProvider
    private var registry: PKPushRegistry?
    private var calls: [UUID: [String: String]] = [:]
    private var answeredCalls = Set<UUID>()

    private override init() {
        let configuration = CXProviderConfiguration(localizedName: "M-Chat Dialer")
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber]
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    func start() {
        guard registry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    var hasActiveCall: Bool { !calls.isEmpty }

    func handleFallbackRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        switch string(userInfo["type"])?.replacingOccurrences(of: "_", with: "-") {
        case "dialer-call-incoming", "modern-dialer-incoming", "incoming-call":
            reportIncoming(payload: stringPayload(userInfo), completion: nil)
            return true
        case "dialer-call-ended", "modern-dialer-ended", "call-ended":
            if let callId = string(userInfo["callId"] ?? userInfo["call_id"]) { endCall(callId: callId) }
            return true
        default:
            return false
        }
    }

    func endCall(callId: String, reason: CXCallEndedReason = .remoteEnded) {
        guard let entry = calls.first(where: { $0.value["callId"] == callId }) else { return }
        provider.reportCall(with: entry.key, endedAt: Date(), reason: reason)
        calls.removeValue(forKey: entry.key)
    }

    private func reportIncoming(payload: [String: String], completion: (() -> Void)?) {
        guard let callId = payload["callId"] ?? payload["call_id"], !callId.isEmpty else {
            completion?()
            return
        }
        if let expiresAt = payload["expiresAt"].flatMap(Self.parseDate), expiresAt <= Date() {
            completion?()
            return
        }
        let uuid = UUID(uuidString: payload["callUuid"] ?? "") ?? Self.stableUUID(callId)
        calls[uuid] = payload

        let update = CXCallUpdate()
        let number = payload["fromNumber"] ?? payload["from"] ?? "Unknown number"
        update.remoteHandle = CXHandle(type: .phoneNumber, value: number)
        update.localizedCallerName = payload["clientName"]?.nonBlank
            ?? payload["callerName"]?.nonBlank
            ?? payload["contactName"]?.nonBlank
            ?? payload["fromName"]?.nonBlank
        update.hasVideo = false
        provider.reportNewIncomingCall(with: uuid, update: update) { _ in completion?() }
    }

    private func stringPayload(_ source: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in source {
            guard let key = key as? String else { continue }
            if let string = string(value) { result[key] = string }
        }
        return result
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        if let milliseconds = Double(value) {
            return Date(timeIntervalSince1970: milliseconds > 10_000_000_000 ? milliseconds / 1_000 : milliseconds)
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func stableUUID(_ value: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in value.utf8.enumerated() {
            bytes[index % 16] = bytes[index % 16] &+ byte &+ UInt8(index & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

extension ModernDialerCallKitCoordinator: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        ModernDialerVoIPTokenCache.token = token
        NotificationCenter.default.post(name: .didRegisterModernDialerVoIPToken, object: token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        let invalidatedToken = ModernDialerVoIPTokenCache.token
        ModernDialerVoIPTokenCache.token = nil
        NotificationCenter.default.post(
            name: .didInvalidateModernDialerVoIPToken,
            object: invalidatedToken
        )
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        reportIncoming(payload: stringPayload(payload.dictionaryPayload), completion: completion)
    }
}

extension ModernDialerCallKitCoordinator: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        calls.removeAll()
        answeredCalls.removeAll()
        NotificationCenter.default.post(name: .didEndModernDialerCall, object: nil)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let payload = calls[action.callUUID] else {
            action.fail()
            return
        }
        answeredCalls.insert(action.callUUID)
        var actionPayload = payload
        actionPayload["operation"] = "pickup"
        actionPayload["callUuid"] = action.callUUID.uuidString
        NotificationCenter.default.post(name: .didAnswerModernDialerCall, object: actionPayload)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        var payload = calls.removeValue(forKey: action.callUUID)
        let wasAnswered = answeredCalls.remove(action.callUUID) != nil
        payload?["operation"] = wasAnswered ? "hangup" : "reject"
        payload?["callUuid"] = action.callUUID.uuidString
        NotificationCenter.default.post(name: .didEndModernDialerCall, object: payload)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
        try? audioSession.setActive(true)
    }
}
