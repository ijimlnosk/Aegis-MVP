import Foundation

enum ScreenImageSizing {
  static func bounded(width: Int, height: Int, maximum: Int,
                      maximumPixels: Int = .max) -> (width: Int, height: Int) {
    let width = max(1, width); let height = max(1, height)
    let longest = max(width, height)
    let edgeScale = Double(maximum) / Double(longest)
    let pixelScale = sqrt(Double(maximumPixels) / (Double(width) * Double(height)))
    let scale = min(1, edgeScale, pixelScale)
    guard scale < 1 else { return (width, height) }
    return (max(1, Int(Double(width) * scale)),
      max(1, Int(Double(height) * scale)))
  }
}
