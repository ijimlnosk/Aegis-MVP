import Foundation

/// Replies mark fixed-width content (code, search hits, command tables) with ``` fences;
/// the Mac and phone chat render those parts in a monospace box.
enum MessageSegment: Equatable {
  case text(String)
  case code(String)
}

enum MessageSegments {
  static func code(_ body: String) -> String { "```\n\(body)\n```" }

  /// An unclosed fence (a truncated reply) still renders the rest as code.
  static func split(_ content: String) -> [MessageSegment] {
    var segments: [MessageSegment] = []
    var buffer: [String] = []
    var inCode = false
    func flush() {
      let joined = buffer.joined(separator: "\n")
      buffer.removeAll()
      if inCode { segments.append(.code(joined)) }
      else if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        segments.append(.text(joined.trimmingCharacters(in: .newlines)))
      }
    }
    for line in content.components(separatedBy: "\n") {
      if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { flush(); inCode.toggle() }
      else { buffer.append(line) }
    }
    flush()
    return segments
  }
}
