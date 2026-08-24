import Foundation

struct ApprovedUITarget: Equatable, Sendable {
  let bundleIdentifier: String
  let windowIdentifier: UInt32
  let semanticTarget: String
  let expectedWindowTitle: String?

  init(window: WindowDescriptor, semanticTarget: String) throws {
    guard let bundleIdentifier = window.bundleIdentifier else {
      throw UIInteractionError.windowNotFound(window.canonicalApplication)
    }
    self.bundleIdentifier = bundleIdentifier
    windowIdentifier = window.id
    self.semanticTarget = semanticTarget
    expectedWindowTitle = window.windowTitle
  }

  func resolve(in windows: [WindowDescriptor]) throws -> WindowDescriptor {
    guard let window = windows.first(where: {
      $0.id == windowIdentifier
        && $0.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }) else { throw UIInteractionError.staleElement }
    return window
  }
}
