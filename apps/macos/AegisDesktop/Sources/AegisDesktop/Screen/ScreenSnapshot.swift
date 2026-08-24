import Foundation

enum ScreenCaptureAvailability: String, Codable {
  case available, permissionRequired, unavailable, failed
}
enum ScreenCaptureSource: String, Codable { case activeWindow, activeDisplay, display }

struct ScreenSnapshot: Identifiable, Equatable {
  let id: UUID
  let capturedAt: Date
  let displayCount: Int
  let activeApplication: String?
  let bundleIdentifier: String?
  let activeWindowTitle: String?
  let windowID: UInt32?
  let displayIndex: Int?
  let temporaryImageURL: URL
  let width: Int
  let height: Int
  let scale: Double
  let captureSource: ScreenCaptureSource

  init(id: UUID = UUID(), capturedAt: Date = .now, displayCount: Int,
       activeApplication: String?, bundleIdentifier: String? = nil,
       activeWindowTitle: String?, windowID: UInt32? = nil, displayIndex: Int? = nil,
       temporaryImageURL: URL,
       width: Int, height: Int, scale: Double = 1, captureSource: ScreenCaptureSource) {
    self.id = id; self.capturedAt = capturedAt; self.displayCount = displayCount
    self.activeApplication = activeApplication; self.bundleIdentifier = bundleIdentifier
    self.activeWindowTitle = activeWindowTitle; self.windowID = windowID
    self.displayIndex = displayIndex
    self.temporaryImageURL = temporaryImageURL; self.width = width; self.height = height
    self.scale = scale; self.captureSource = captureSource
  }

  var canonicalApplication: String? {
    activeApplication.map { KnownApplicationRegistry.canonicalName(applicationName: $0,
      bundleIdentifier: bundleIdentifier) }
  }
}

struct ScreenCaptureRequest: Equatable {
  let activeWindowOnly: Bool
  let displayIndex: Int?
  let resourceProfile: VisionResourceProfile?
  let windowID: UInt32?

  init(activeWindowOnly: Bool, displayIndex: Int?, resourceProfile: VisionResourceProfile? = nil,
       windowID: UInt32? = nil) {
    self.activeWindowOnly = activeWindowOnly; self.displayIndex = displayIndex
    self.resourceProfile = resourceProfile; self.windowID = windowID
  }
}
