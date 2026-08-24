import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

protocol ScreenCaptureProviding {
  func availability() -> ScreenCaptureAvailability
  func capture(_ request: ScreenCaptureRequest) async throws -> ScreenSnapshot
  func diagnostics() async -> ScreenDiagnostics
}

enum ScreenCaptureError: LocalizedError {
  case permissionRequired, unavailable, invalidDisplay(Int), activeWindowUnavailable
  case sensitiveApplication(String), captureFailed(String)
  var errorDescription: String? {
    switch self {
    case .permissionRequired: "화면을 확인하려면 macOS 시스템 설정에서 Aegis의 화면 기록 권한이 필요합니다."
    case .unavailable: "이 Mac에서는 화면 캡처를 사용할 수 없습니다."
    case .invalidDisplay(let value): "모니터 번호가 올바르지 않습니다: \(value)"
    case .activeWindowUnavailable: "현재 활성 창을 확인하지 못했습니다."
    case .sensitiveApplication(let value): value
    case .captureFailed(let value): "화면 캡처에 실패했습니다: \(value)"
    }
  }
}

final class ScreenCaptureService: ScreenCaptureProviding {
  func availability() -> ScreenCaptureAvailability {
    CGPreflightScreenCaptureAccess() ? .available : .permissionRequired
  }

  func capture(_ request: ScreenCaptureRequest) async throws -> ScreenSnapshot {
    let started = ContinuousClock.now
    guard availability() == .available else { throw ScreenCaptureError.permissionRequired }
    let app = await MainActor.run { NSWorkspace.shared.frontmostApplication }
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let window = activeWindow(in: content.windows, processID: app?.processIdentifier)
    let selectedWindow = request.windowID.flatMap { id in
      content.windows.first { $0.windowID == id }
    }
    let describedWindow = selectedWindow ?? window
    let appName = selectedWindow?.owningApplication?.applicationName ?? app?.localizedName
    if case .blocked(let reason) = ScreenPrivacyPolicy.decision(for: appName) {
      throw ScreenCaptureError.sensitiveApplication(reason)
    }
    let resizeStarted = ContinuousClock.now
    let target = try target(for: request, content: content, activeWindow: window)
    ScreenAnalysisDiagnostics.timing("resize", since: resizeStarted,
      dimensions: (target.width, target.height))
    let image = try await SCScreenshotManager.captureImage(contentFilter: target.filter,
      configuration: configuration(width: target.width, height: target.height))
    let profile = request.resourceProfile ?? ScreenAnalysisConfiguration.resourceProfile()
    let url = try temporaryJPEG(image, profile: profile)
    ScreenAnalysisDiagnostics.timing("capture", since: started,
      dimensions: (image.width, image.height))
    return ScreenSnapshot(displayCount: content.displays.count, activeApplication: appName,
      bundleIdentifier: describedWindow?.owningApplication?.bundleIdentifier,
      activeWindowTitle: describedWindow?.title, windowID: describedWindow?.windowID,
      displayIndex: describedWindow.flatMap { displayIndex(for: $0.frame, in: content.displays) },
      temporaryImageURL: url, width: image.width, height: image.height,
      captureSource: target.source)
  }

  func diagnostics() async -> ScreenDiagnostics {
    let app = await MainActor.run { NSWorkspace.shared.frontmostApplication }
    let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let window = activeWindow(in: content?.windows ?? [], processID: app?.processIdentifier)
    return ScreenDiagnostics(availability: availability(), activeApplication: app?.localizedName,
      activeWindowAvailable: window != nil, activeWindowTitle: window?.title,
      displayCount: content?.displays.count ?? 0)
  }

  private func activeWindow(in windows: [SCWindow], processID: pid_t?) -> SCWindow? {
    windows.first { $0.owningApplication?.processID == processID && $0.frame.width > 100 && $0.frame.height > 100 }
  }

  private func displayIndex(for bounds: CGRect, in displays: [SCDisplay]) -> Int? {
    displays.sorted { $0.displayID < $1.displayID }.enumerated().max { lhs, rhs in
      let left = lhs.element.frame.intersection(bounds)
      let right = rhs.element.frame.intersection(bounds)
      return (left.isNull ? 0 : left.width * left.height)
        < (right.isNull ? 0 : right.width * right.height)
    }.map { $0.offset + 1 }
  }
}
