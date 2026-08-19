import Foundation

enum VisionResourceProfile: String, Codable, Sendable {
  case lowMemory, balanced, highQuality

  var defaultLongEdge: Int {
    switch self { case .lowMemory: 1_024; case .balanced: 1_280; case .highQuality: 1_920 }
  }

  var defaultJPEGQuality: Double {
    switch self { case .lowMemory: 0.55; case .balanced: 0.75; case .highQuality: 0.85 }
  }
}
