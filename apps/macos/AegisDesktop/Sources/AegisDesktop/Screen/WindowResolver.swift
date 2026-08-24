import Foundation

enum WindowResolver {
  static func requestedApplications(in request: String) -> [String] {
    var matches = KnownApplicationRegistry.applications.compactMap { application -> (Int, String)? in
      guard let offset = application.aliases.compactMap({ aliasOffset($0, in: request) }).min()
      else { return nil }
      return (offset, application.canonicalName)
    }
    matches += configuredAliases().compactMap { alias, application in
      aliasOffset(alias, in: request).map { ($0, application) }
    }
    var seen = Set<String>()
    let ordered = matches.sorted { $0.0 < $1.0 }.map(\.1).filter {
      seen.insert($0.lowercased()).inserted
    }
    return Array(ordered.prefix(ScreenAnalysisConfiguration.maximumWindows()))
  }

  static func resolve(_ target: String, displayIndex: Int?, preferredTitle: String? = nil,
                      windows: [WindowDescriptor]) throws -> WindowDescriptor {
    let known = KnownApplicationRegistry.application(nameOrAlias: target)
    let canonical = known?.canonicalName ?? configuredAliases()[target.lowercased()] ?? target
    var ranked = windows.compactMap { window -> (Int, WindowDescriptor)? in
      if window.bundleIdentifier.map({ $0.caseInsensitiveCompare(target) == .orderedSame }) == true
        || known?.matches(bundleIdentifier: window.bundleIdentifier) == true { return (0, window) }
      if window.canonicalApplication.caseInsensitiveCompare(canonical) == .orderedSame {
        return (1, window)
      }
      if known?.matches(alias: window.applicationName) == true { return (2, window) }
      if window.windowTitle?.caseInsensitiveCompare(target) == .orderedSame { return (3, window) }
      return nil
    }
    if let displayIndex { ranked = ranked.filter { $0.1.displayIndex == displayIndex } }
    guard let bestRank = ranked.map(\.0).min() else { throw WindowResolutionError.notFound(canonical) }
    let candidates = ranked.filter { $0.0 == bestRank }.map(\.1)
    if candidates.count == 1 { return candidates[0] }
    if let preferredTitle, !preferredTitle.isEmpty {
      let titled = candidates.filter {
        $0.windowTitle?.range(of: preferredTitle, options: .caseInsensitive) != nil
      }
      if titled.count == 1 { return titled[0] }
      if titled.count > 1, let active = titled.first(where: \.isActive) { return active }
    }
    let active = candidates.filter(\.isActive)
    if active.count == 1 { return active[0] }
    throw WindowResolutionError.ambiguous(canonical)
  }

  private static func configuredAliases() -> [String: String] {
    guard let raw = ProcessInfo.processInfo.environment["AEGIS_WINDOW_ALIASES"] else { return [:] }
    return raw.split(separator: ",").reduce(into: [:]) { values, entry in
      let pair = entry.split(separator: "=", maxSplits: 1).map(String.init)
      if pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty {
        values[pair[0].lowercased()] = pair[1]
      }
    }
  }

  private static func aliasOffset(_ alias: String, in request: String) -> Int? {
    let escaped = NSRegularExpression.escapedPattern(for: alias)
    guard let regex = try? NSRegularExpression(
      pattern: "(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])", options: .caseInsensitive),
      let match = regex.firstMatch(in: request,
        range: NSRange(request.startIndex..., in: request)),
      let range = Range(match.range, in: request) else { return nil }
    return request.distance(from: request.startIndex, to: range.lowerBound)
  }
}
