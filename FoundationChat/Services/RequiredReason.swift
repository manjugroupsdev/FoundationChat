import Foundation

/// Trimmed reason, or nil when nothing meaningful was typed. Shared by
/// `MconnectReasonSheet` and the callers that must refuse a blank reason
/// (parity with Android `AppBottomSheets.requiredReason`).
enum RequiredReason {
    static func normalized(_ text: String?) -> String? {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// JSON body for `/api/dailyTasks/updateStatus`; a reason only rides along
    /// on a rejection (status "cancelled") and only when it isn't blank.
    static func dailyTaskStatusBody(id: String, status: String, reason: String?) -> [String: Any] {
        var body: [String: Any] = ["id": id, "status": status]
        if status == "cancelled", let reason = normalized(reason) {
            body["reason"] = reason
        }
        return body
    }
}
