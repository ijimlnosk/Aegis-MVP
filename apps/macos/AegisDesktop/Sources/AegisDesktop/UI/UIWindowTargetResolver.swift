import Foundation

enum UIWindowTargetResolver {
  static func resolve(step: AgentStep, windows: [WindowDescriptor],
                      workflow: ResolvedWindowTarget?, recent: ResolvedWindowTarget?,
                      now: Date = Date()) throws -> WindowDescriptor {
    if step.action == .listUIElements,
      let active = activeWindow(for: step.application, in: windows) { return active }
    if let workflow { return try workflow.resolve(in: windows) }
    if step.action == .focusWindow, let application = step.application {
      return try WindowResolver.resolve(application, displayIndex: step.displayIndex,
        preferredTitle: step.project, windows: windows)
    }
    if let recent, now.timeIntervalSince(recent.resolvedAt) < 120,
      recent.matches(application: step.application), let resolved = try? recent.resolve(in: windows) {
      return resolved
    }
    if let active = activeWindow(for: step.application, in: windows) { return active }
    if let application = step.application {
      return try WindowResolver.resolve(application, displayIndex: step.displayIndex,
        preferredTitle: step.project, windows: windows)
    }
    guard let active = windows.first(where: \.isActive) else {
      throw UIInteractionError.windowNotFound("활성")
    }
    return active
  }

  private static func activeWindow(for application: String?,
                                   in windows: [WindowDescriptor]) -> WindowDescriptor? {
    windows.first { window in
      guard window.isActive else { return false }
      guard let application else { return true }
      if window.canonicalApplication.caseInsensitiveCompare(application) == .orderedSame {
        return true
      }
      if window.bundleIdentifier?.caseInsensitiveCompare(application) == .orderedSame {
        return true
      }
      return KnownApplicationRegistry.application(nameOrAlias: application)?
        .matches(bundleIdentifier: window.bundleIdentifier) == true
    }
  }
}
