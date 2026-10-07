import Foundation

/// Chat presentation of Server Agent results. The raw text stays the contract for
/// machine readers; only what the user sees goes through here.
enum ServerResultFormatter {
  static func display(_ tool: ServerTool, raw: String) -> String {
    if tool == .status { return status(raw) }
    return raw.contains("\n") ? MessageSegments.code(TextTable.columns(raw)) : raw
  }

  static func status(_ raw: String) -> String {
    let uptime = section("Uptime:", in: raw, untilAny: ["Memory:"])
    let memory = section("Memory:", in: raw, untilAny: ["Disk:"])
    let disk = section("Disk:", in: raw, untilAny: ["Docker:"])
    let docker = section("Docker:", in: raw, untilAny: [])
    guard let uptime, let memory, let disk, let docker else { return raw }
    // Command tables (free, df, docker ps) only line up in a monospace block.
    return "sol-server · \(uptime)\n\n메모리\n\(MessageSegments.code(TextTable.rightAlignHeader(memory)))"
      + "\n디스크\n\(MessageSegments.code(disk))\nDocker\n\(MessageSegments.code(TextTable.columns(docker)))"
  }

  private static func section(_ marker: String, in text: String, untilAny ends: [String]) -> String? {
    guard let start = text.range(of: marker) else { return nil }
    let rest = text[start.upperBound...]
    let end = ends.compactMap { rest.range(of: "\n" + $0)?.lowerBound }.min() ?? rest.endIndex
    return rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
