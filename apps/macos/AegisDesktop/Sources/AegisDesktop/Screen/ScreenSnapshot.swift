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
  let activeWindowTitle: String?
  let temporaryImageURL: URL
  let width: Int
  let height: Int
  let scale: Double
  let captureSource: ScreenCaptureSource

  init(id: UUID = UUID(), capturedAt: Date = .now, displayCount: Int,
       activeApplication: String?, activeWindowTitle: String?, temporaryImageURL: URL,
       width: Int, height: Int, scale: Double = 1, captureSource: ScreenCaptureSource) {
    self.id = id; self.capturedAt = capturedAt; self.displayCount = displayCount
    self.activeApplication = activeApplication; self.activeWindowTitle = activeWindowTitle
    self.temporaryImageURL = temporaryImageURL; self.width = width; self.height = height
    self.scale = scale; self.captureSource = captureSource
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
