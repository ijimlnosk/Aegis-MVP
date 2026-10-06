import AppKit
import Foundation

enum MacApplicationLauncher {
  private static let actions = ["켜줘", "켜 줘", "실행해", "실행 해", "열어줘", "열어 줘", "열어"]

  static func requestedApplication(from text: String) -> String? {
    guard let action = actions.compactMap({ text.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
    let requested = String(text[..<action.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "을를은는이가"))
    guard !requested.isEmpty else { return nil }
    let compact = requested.lowercased().components(separatedBy: .whitespaces).joined()
    if compact.contains("리그오브레전드") || compact == "롤" { return "League of Legends" }
    if compact == "파인더" { return "Finder" }
    if compact == "사파리" { return "Safari" }
    if compact == "크롬" || compact == "구글크롬" { return "Google Chrome" }
    if compact == "파이어폭스" { return "Firefox" }
    if compact == "카카오톡" { return "KakaoTalk" }
    if compact == "비주얼스튜디오코드" || compact == "vscode" { return "Visual Studio Code" }
    if compact == "메모" { return "Notes" }
    if compact == "메시지" { return "Messages" }
    if compact == "캘린더" { return "Calendar" }
    if compact == "터미널" { return "Terminal" }
    return requested
  }

  static func open(_ application: String) async -> String {
    await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      if let bundleID = LearningStore.applicationBundleID(for: application) {
        process.arguments = ["-b", bundleID]
      } else if let path = installedApplicationPath(named: application) {
        process.arguments = [path]
      } else {
        process.arguments = ["-a", application]
      }
      do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "\(application)을 실행했습니다." : "\(application)을(를) 찾지 못했습니다. 설치된 앱 이름을 확인해 주세요."
      } catch {
        return "\(application)을(를) 실행하지 못했습니다: \(error.localizedDescription)"
      }
    }.value
  }

  static func close(_ application: String) async -> String {
    await Task.detached {
      let bundleID = LearningStore.applicationBundleID(for: application)
        ?? installedApplicationPath(named: application).flatMap { Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier }
      guard let bundleID,
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        return "\(application)은(는) 현재 실행 중이지 않습니다."
      }
      return running.terminate() ? "\(application)을 종료했습니다." : "\(application)을 종료하지 못했습니다. 저장하지 않은 작업이 있는지 확인해 주세요."
    }.value
  }

  private static func installedApplicationPath(named application: String) -> String? {
    let fileManager = FileManager.default
    let directories = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
    let target = application.lowercased().components(separatedBy: .whitespaces).joined()
    let candidates: [URL] = directories.flatMap { directory -> [URL] in
      guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
      var applications: [URL] = []
      while let url = enumerator.nextObject() as? URL {
        guard url.pathExtension == "app" else { continue }
        applications.append(url)
        enumerator.skipDescendants()
      }
      return applications
    }
    let named = candidates.map { url in
      (url, url.deletingPathExtension().lastPathComponent.lowercased().components(separatedBy: .whitespaces).joined())
    }
    if let exact = named.first(where: { $0.1 == target }) { return exact.0.path }
    return named.first(where: { $0.1.contains(target) || target.contains($0.1) })?.0.path
  }
}
