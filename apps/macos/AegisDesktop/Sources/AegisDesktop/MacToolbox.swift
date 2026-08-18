import AppKit
import Foundation

struct PendingMacAction: Identifiable {
  let id = UUID()
  let kind: String
  let title: String
  let detail: String
  let request: String
  let arguments: [String: String]
}

enum MacToolbox {
  static func systemStatus() -> String {
    let info = ProcessInfo.processInfo
    let memoryGB = Double(info.physicalMemory) / 1_073_741_824
    let uptime = Int(info.systemUptime / 3600)
    return "macOS \(info.operatingSystemVersionString), 메모리 \(String(format: "%.1f", memoryGB))GB, 가동 시간 약 \(uptime)시간입니다."
  }

  static func runningApplications() -> String {
    let names = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }
      .compactMap(\.localizedName)
      .sorted()
    return names.isEmpty ? "실행 중인 앱을 확인하지 못했습니다." : "실행 중인 앱: \(names.joined(separator: ", "))"
  }

  static func clipboardText() -> String {
    guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
      return "클립보드에 텍스트가 없습니다."
    }
    return "현재 클립보드: \(String(value.prefix(1_000)))"
  }

  static func setClipboard(_ text: String) -> String {
    let board = NSPasteboard.general
    board.clearContents()
    return board.setString(text, forType: .string)
      ? "클립보드에 텍스트를 저장했습니다."
      : "클립보드 저장에 실패했습니다."
  }
}
