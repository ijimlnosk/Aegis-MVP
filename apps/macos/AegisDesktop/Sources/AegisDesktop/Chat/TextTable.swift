import Foundation

/// Re-aligns command output that loses its alignment on the way to the chat.
enum TextTable {
  /// Tab-separated rows (docker ps) padded into columns.
  static func columns(_ text: String) -> String {
    let rows = text.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    guard rows.contains(where: { $0.count > 1 }) else { return text }
    let count = rows.map(\.count).max() ?? 0
    let widths = (0..<count).map { column in rows.map { $0.indices.contains(column) ? $0[column].count : 0 }.max() ?? 0 }
    return rows.map { row in
      row.enumerated().map { index, cell in
        index == row.count - 1 ? cell : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
      }.joined(separator: "  ")
    }.joined(separator: "\n")
  }

  /// `free -h` whose header was trimmed: shift it so its first column ends where the values do.
  static func rightAlignHeader(_ text: String) -> String {
    var lines = text.components(separatedBy: "\n")
    guard lines.count > 1, let header = lines.first, !header.hasPrefix(" "),
      let headerEnd = firstTokenEnd(header), let valueEnd = secondTokenEnd(lines[1]), valueEnd > headerEnd else { return text }
    lines[0] = String(repeating: " ", count: valueEnd - headerEnd) + header
    return lines.joined(separator: "\n")
  }

  private static func firstTokenEnd(_ line: String) -> Int? {
    line.firstIndex(of: " ").map { line.distance(from: line.startIndex, to: $0) } ?? line.count
  }

  private static func secondTokenEnd(_ line: String) -> Int? {
    let pattern = #"^\S+\s+\S+"#
    guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
    return line.distance(from: line.startIndex, to: range.upperBound)
  }
}
