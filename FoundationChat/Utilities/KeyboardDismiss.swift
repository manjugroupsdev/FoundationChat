import SwiftUI
import UIKit

/// One place to close the keyboard (MMS-288).
///
/// The bug: after searching and picking a result, the keyboard stayed up on the
/// next screen or over the form a picker sheet returned to. Close it on SELECT,
/// NAVIGATION or SUBMIT only, never while the user is typing, and never on
/// screens that focus a field on purpose (chat composer, OTP, a form's next
/// field). Those set their focus after they appear, so dismissing before the
/// push or sheet does not affect them.
enum Keyboard {
    static func dismiss() {
        UIApplication.shared.fc_dismissKeyboard()
    }
}

extension View {
    /// Closes the keyboard when this row is tapped, without taking the tap away
    /// from the NavigationLink / Button it wraps.
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded { Keyboard.dismiss() })
    }

    /// Search results scroll with the full screen: dragging the list closes the
    /// keyboard. Typing is unaffected.
    func dismissKeyboardOnScroll() -> some View {
        scrollDismissesKeyboard(.immediately)
    }
}
