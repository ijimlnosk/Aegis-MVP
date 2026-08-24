import Foundation

struct WindowBounds: Codable, Equatable, Sendable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
}

struct WindowDescriptor: Codable, Equatable, Identifiable, Sendable {
  let id: UInt32
  let applicationName: String
  let bundleIdentifier: String?
  let windowTitle: String?
  let displayIndex: Int?
  let isActive: Bool
  let isOnScreen: Bool
  let bounds: WindowBounds

  var canonicalApplication: String {
    KnownApplicationRegistry.canonicalName(applicationName: applicationName,
      bundleIdentifier: bundleIdentifier)
  }
}

enum WindowResolutionError: LocalizedError {
  case notFound(String), ambiguous(String)
  var errorDescription: String? {
    switch self {
    case .notFound(let target): "현재 보이는 \(target) 창을 찾지 못했습니다."
    case .ambiguous(let target): "\(target) 창이 여러 개입니다. 창 제목을 지정해 주세요."
    }
  }
}
