import SwiftUI

/// Approving attendance with a value other than the shift-based system result
/// needs a reason (web parity: the web prompts for one). The server says
/// "Approval differs from the shift-based system result (absent). Enter an
/// override reason before approving." (HTTP 422 OVERRIDE_REASON_REQUIRED on new
/// servers, HTTP 500 on older ones). Approving used to stop there.
enum ApprovalOverrideReason {
    /// The system result named in an override error, or nil for any other error.
    static func systemResult(in message: String) -> String? {
        guard let range = message.range(
            of: #"shift-based system result \(([a-z-]+)\)"#,
            options: .regularExpression
        ) else { return nil }
        let match = String(message[range])
        guard let open = match.firstIndex(of: "("), let close = match.lastIndex(of: ")") else { return nil }
        let value = String(match[match.index(after: open)..<close])
        return value.isEmpty ? nil : value
    }

    static func label(_ value: String) -> String {
        switch value {
        case "half-day": return "Half-day"
        case "weekoff": return "Week off"
        default: return value.prefix(1).uppercased() + value.dropFirst()
        }
    }

    /// Shown when the reason was sent but this server doesn't read it yet.
    static func serverNotReadyMessage(system: String) -> String {
        "The server couldn't save the reason yet. Approve as \(label(system)) for now, or ask HR to approve it on the web."
    }
}

struct ApprovalOverridePrompt: Identifiable, Equatable {
    let id = UUID()
    /// Attendance (or request) id being approved.
    let recordId: String
    let chosen: String
    let system: String
}

private struct ApprovalOverrideReasonAlert: ViewModifier {
    @Binding var prompt: ApprovalOverridePrompt?
    let onApprove: (ApprovalOverridePrompt, String) -> Void
    @State private var reason = ""

    func body(content: Content) -> some View {
        content.alert(
            "Reason needed",
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            ),
            presenting: prompt
        ) { current in
            TextField("Reason for approving as \(ApprovalOverrideReason.label(current.chosen))", text: $reason)
            Button("Approve") {
                let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                reason = ""
                guard !text.isEmpty else { return }
                onApprove(current, String(text.prefix(500)))
            }
            Button("Cancel", role: .cancel) { reason = "" }
        } message: { current in
            Text("The shift-based result for this day is \(ApprovalOverrideReason.label(current.system)). Add a reason to approve it as \(ApprovalOverrideReason.label(current.chosen)).")
        }
    }
}

extension View {
    /// Asks for the override reason and hands it back to retry the approval.
    func approvalOverrideReasonAlert(
        prompt: Binding<ApprovalOverridePrompt?>,
        onApprove: @escaping (ApprovalOverridePrompt, String) -> Void
    ) -> some View {
        modifier(ApprovalOverrideReasonAlert(prompt: prompt, onApprove: onApprove))
    }
}
