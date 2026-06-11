import Observation
import SwiftUI

/// Placeholder – FoundationModels (on-device AI) has been removed.
/// Chat is now backed by the Convex HTTP API.
@Observable
class ChatEngine {
  private let conversation: Conversation

  var isAvailable: Bool { false }

  var availabilityMessage: String? {
    "On-device AI is not enabled in this build."
  }

  init(conversation: Conversation) {
    self.conversation = conversation
  }

  func prewarm() {}
}
