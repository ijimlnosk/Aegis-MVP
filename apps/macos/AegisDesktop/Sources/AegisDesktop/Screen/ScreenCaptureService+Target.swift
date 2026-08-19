import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct ScreenCaptureTarget {
  let filter: SCContentFilter
  let width: Int
  let height: Int
  let source: ScreenCaptureSource
}

extension ScreenCaptureService {
  func target(for request: ScreenCaptureRequest, content: SCShareableContent,
              activeWindow: SCWindow?) throws -> ScreenCaptureTarget {
    if let windowID = request.windowID {
      guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
        throw ScreenCaptureError.activeWindowUnavailable
      }
      let size = bounded(width: Int(window.frame.width), height: Int(window.frame.height),
        profile: request.resourceProfile)
      return ScreenCaptureTarget(filter: SCContentFilter(desktopIndependentWindow: window),
        width: size.width, height: size.height, source: .activeWindow)
    }
    if request.activeWindowOnly {
      guard let activeWindow else { throw ScreenCaptureError.activeWindowUnavailable }
      let size = bounded(width: Int(activeWindow.frame.width), height: Int(activeWindow.frame.height),
        profile: request.resourceProfile)
      return ScreenCaptureTarget(filter: SCContentFilter(desktopIndependentWindow: activeWindow),
        width: size.width, height: size.height,
        source: .activeWindow)
    }
    let displays = content.displays.sorted { $0.displayID < $1.displayID }
    try ScreenDisplayPolicy.validate(index: request.displayIndex, displayCount: displays.count)
    let selected: SCDisplay
    if let index = request.displayIndex {
      selected = displays[index - 1]
    } else if let activeWindow {
      guard let best = displays.max(by: {
        intersection($0.frame, activeWindow.frame) < intersection($1.frame, activeWindow.frame)
      }) else { throw ScreenCaptureError.unavailable }
      selected = best
    } else { guard let first = displays.first else { throw ScreenCaptureError.unavailable }; selected = first }
    let size = bounded(width: selected.width, height: selected.height,
      profile: request.resourceProfile)
    return ScreenCaptureTarget(filter: SCContentFilter(display: selected, excludingWindows: []),
      width: size.width, height: size.height,
      source: request.displayIndex == nil ? .activeDisplay : .display)
  }

  func configuration(width: Int, height: Int) -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration(); configuration.width = width
    configuration.height = height; configuration.showsCursor = false
    configuration.captureResolution = .best
    return configuration
  }

  func temporaryJPEG(_ image: CGImage, profile: VisionResourceProfile) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "aegis-screen-\(UUID().uuidString).jpg")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
      UTType.jpeg.identifier as CFString, 1, nil) else {
      throw ScreenCaptureError.captureFailed("임시 이미지 생성 실패")
    }
    let options = [kCGImageDestinationLossyCompressionQuality:
      ScreenAnalysisConfiguration.jpegQuality(for: profile)] as CFDictionary
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else {
      throw ScreenCaptureError.captureFailed("JPEG 저장 실패")
    }
    return url
  }

  private func bounded(width: Int, height: Int,
                       profile: VisionResourceProfile?) -> (width: Int, height: Int) {
    let profile = profile ?? ScreenAnalysisConfiguration.resourceProfile()
    return ScreenImageSizing.bounded(width: width, height: height,
      maximum: ScreenAnalysisConfiguration.maximumLongEdge(for: profile),
      maximumPixels: ScreenAnalysisConfiguration.maximumPixels())
  }
  private func intersection(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let value = lhs.intersection(rhs); return value.isNull ? 0 : value.width * value.height
  }
}
