import AppKit
import Foundation
import ScreenCaptureKit

protocol VisibleWindowProviding: Sendable {
  func list() async throws -> [WindowDescriptor]
}

struct VisibleWindowService: VisibleWindowProviding {
  func list() async throws -> [WindowDescriptor] {
    let content = try await SCShareableContent.excludingDesktopWindows(true,
      onScreenWindowsOnly: true)
    let displays = content.displays.sorted { $0.displayID < $1.displayID }
    let activePID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    let activeWindowID = content.windows.first {
      $0.owningApplication?.processID == activePID && $0.frame.width > 100 && $0.frame.height > 100
    }?.windowID
    return content.windows.compactMap { window in
      guard window.isOnScreen, window.frame.width > 100, window.frame.height > 100,
        let application = window.owningApplication?.applicationName,
        case .allowed = ScreenPrivacyPolicy.decision(for: application) else { return nil }
      return WindowDescriptor(id: window.windowID, applicationName: application,
        bundleIdentifier: window.owningApplication?.bundleIdentifier,
        windowTitle: window.title?.isEmpty == false ? window.title : nil,
        displayIndex: displayIndex(window.frame, displays: displays),
        isActive: window.windowID == activeWindowID,
        isOnScreen: window.isOnScreen,
        bounds: WindowBounds(x: window.frame.origin.x, y: window.frame.origin.y,
          width: window.frame.width, height: window.frame.height))
    }.sorted { lhs, rhs in
      if lhs.isActive != rhs.isActive { return lhs.isActive }
      if lhs.applicationName != rhs.applicationName { return lhs.applicationName < rhs.applicationName }
      return lhs.id < rhs.id
    }
  }

  private func displayIndex(_ bounds: CGRect, displays: [SCDisplay]) -> Int? {
    displays.enumerated().max { lhs, rhs in
      intersection(lhs.element.frame, bounds) < intersection(rhs.element.frame, bounds)
    }.map { $0.offset + 1 }
  }

  private func intersection(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let value = lhs.intersection(rhs); return value.isNull ? 0 : value.width * value.height
  }
}
