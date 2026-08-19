import Foundation

enum WindowResolver {
  private static let defaultAliases = ["vscode": "Visual Studio Code",
    "vs code": "Visual Studio Code", "비주얼 스튜디오 코드": "Visual Studio Code",
    "엑스코드": "Xcode", "xcode": "Xcode", "커서": "Cursor", "cursor": "Cursor"]

  private static var aliases: [String: String] {
    guard let raw = ProcessInfo.processInfo.environment["AEGIS_WINDOW_ALIASES"] else {
      return defaultAliases
    }
    return raw.split(separator: ",").reduce(into: defaultAliases) { values, entry in
      let pair = entry.split(separator: "=", maxSplits: 1).map(String.init)
      if pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty {
        values[pair[0].lowercased()] = pair[1]
      }
    }
  }

  static func requestedApplications(in request: String) -> [String] {
    let lower = request.lowercased()
    var matches = aliases.compactMap { alias, application -> (Int, String)? in
      guard let range = lower.range(of: alias) else { return nil }
      return (lower.distance(from: lower.startIndex, to: range.lowerBound), application)
    }.sorted { $0.0 < $1.0 }.map(\.1)
    var seen = Set<String>(); matches = matches.filter { seen.insert($0).inserted }
    return Array(matches.prefix(ScreenAnalysisConfiguration.maximumWindows()))
  }

  static func resolve(_ target: String, displayIndex: Int?,
                      windows: [WindowDescriptor]) throws -> WindowDescriptor {
    let canonical = aliases[target.lowercased()] ?? target
    var candidates = windows.filter {
      $0.applicationName.caseInsensitiveCompare(canonical) == .orderedSame
    }
    if candidates.isEmpty {
      candidates = windows.filter { $0.windowTitle?.caseInsensitiveCompare(target) == .orderedSame }
    }
    if let displayIndex { candidates = candidates.filter { $0.displayIndex == displayIndex } }
    guard !candidates.isEmpty else { throw WindowResolutionError.notFound(target) }
    if candidates.count == 1 { return candidates[0] }
    let active = candidates.filter(\.isActive)
    if active.count == 1 { return active[0] }
    throw WindowResolutionError.ambiguous(target)
  }
}
