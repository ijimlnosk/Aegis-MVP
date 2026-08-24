import Foundation

struct ResolvedWindowTarget: Equatable, Sendable {
  let windowIdentifier: UInt32
  let bundleIdentifier: String
  let canonicalApplication: String
  let windowTitle: String?
  let resolvedAt: Date

  init(_ window: WindowDescriptor, resolvedAt: Date = Date()) throws {
    guard let bundleIdentifier = window.bundleIdentifier else {
      throw UIInteractionError.windowNotFound(window.canonicalApplication)
    }
    self.windowIdentifier = window.id
    self.bundleIdentifier = bundleIdentifier
    canonicalApplication = window.canonicalApplication
    windowTitle = window.windowTitle
    self.resolvedAt = resolvedAt
  }

  func resolve(in windows: [WindowDescriptor]) throws -> WindowDescriptor {
    guard let match = windows.first(where: {
      $0.id == windowIdentifier
        && $0.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }) else { throw UIInteractionError.staleElement }
    return match
  }

  func matches(application: String?) -> Bool {
    guard let application else { return true }
    return canonicalApplication.caseInsensitiveCompare(application) == .orderedSame
      || bundleIdentifier.caseInsensitiveCompare(application) == .orderedSame
      || KnownApplicationRegistry.application(nameOrAlias: application)?
        .matches(bundleIdentifier: bundleIdentifier) == true
  }
}
