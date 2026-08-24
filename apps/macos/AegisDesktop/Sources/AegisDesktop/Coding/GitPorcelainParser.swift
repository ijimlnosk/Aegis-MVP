import Foundation

enum GitPorcelainParser {
  static func parse(_ data: Data) -> [GitWorkingTreeEntry] {
    let fields = CodingGitInspector.split(data); var index = 0; var result: [GitWorkingTreeEntry] = []
    while index < fields.count {
      let field = fields[index]; index += 1
      guard field.count >= 4, field[field.startIndex.advanced(by: 2)] == 32 else { continue }
      let x = String(decoding: field.prefix(1), as: UTF8.self)
      let y = String(decoding: field.dropFirst().prefix(1), as: UTF8.self)
      let path = String(decoding: field.dropFirst(3), as: UTF8.self)
      var original: String?
      if (x == "R" || x == "C"), index < fields.count {
        original = String(decoding: fields[index], as: UTF8.self); index += 1
      }
      result.append(.init(path: path, originalPath: original, indexStatus: x,
        workTreeStatus: y, kind: kind(x, y), contentFingerprint: ""))
    }
    return result
  }

  private static func kind(_ x: String, _ y: String) -> GitWorkingTreeKind {
    if x == "?" && y == "?" { return .untracked }
    if x == "R" || y == "R" { return .renamed }
    if x == "C" || y == "C" { return .copied }
    if x == "U" || y == "U" || ["DD", "AA"].contains(x + y) { return .conflicted }
    if x == "D" || y == "D" { return .deleted }
    if x == "A" || y == "A" { return .added }
    return .modified
  }
}

enum GitNameStatusParser {
  static func parse(_ data: Data) -> [GitNameStatusEntry] {
    let fields = CodingGitInspector.split(data); var index = 0; var result: [GitNameStatusEntry] = []
    while index < fields.count {
      let status = String(decoding: fields[index], as: UTF8.self); index += 1
      guard index < fields.count else { break }
      let first = String(decoding: fields[index], as: UTF8.self); index += 1
      if (status.hasPrefix("R") || status.hasPrefix("C")), index < fields.count {
        let second = String(decoding: fields[index], as: UTF8.self); index += 1
        result.append(.init(status: status, path: second, originalPath: first))
      } else { result.append(.init(status: status, path: first, originalPath: nil)) }
    }
    return result
  }
}
