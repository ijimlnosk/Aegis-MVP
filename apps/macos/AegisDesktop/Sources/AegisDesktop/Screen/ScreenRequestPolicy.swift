import Foundation

enum ScreenRequestPolicy {
  static func isExplicitFullScreen(_ request: String) -> Bool {
    ["전체 화면", "데스크탑 전체", "모든 모니터"].contains { request.contains($0) }
  }

  static func requestedProfile(_ request: String) -> VisionResourceProfile? {
    if request.contains("저메모리") { return .lowMemory }
    if request.contains("자세히") { return .highQuality }
    return nil
  }
}
