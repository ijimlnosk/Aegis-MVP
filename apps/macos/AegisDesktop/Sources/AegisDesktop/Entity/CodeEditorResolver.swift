import Foundation

enum CodeEditorResolver {
  private static let defaults = ["Visual Studio Code", "Cursor", "Xcode"]
  static var allowed: [String] {
    guard let configured = ProcessInfo.processInfo.environment["AEGIS_ALLOWED_CODE_EDITORS"],
      !configured.isEmpty else { return defaults }
    let requested = configured.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    return defaults.filter { editor in requested.contains { $0.caseInsensitiveCompare(editor) == .orderedSame } }
  }
  private static let aliases = ["vscode": "Visual Studio Code", "vs code": "Visual Studio Code",
    "비주얼 스튜디오 코드": "Visual Studio Code", "커서": "Cursor", "엑스코드": "Xcode"]

  static func resolve(for request: String, repository: MemoryRepository) -> String {
    if let explicit = explicitEditor(in: request) { return explicit }
    if let unknown = explicitUnknownEditor(in: request) { return unknown }
    if let preference = try? repository.find(type: .preference, key: "default_code_editor"),
       let editor = canonical(preference.value) { return editor }
    return "Visual Studio Code"
  }

  static func canonical(_ value: String) -> String? {
    if let editor = allowed.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { return editor }
    let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard let editor = aliases[normalized], allowed.contains(editor) else { return nil }
    return editor
  }

  static func isAllowed(_ value: String) -> Bool { canonical(value) != nil }

  private static func explicitEditor(in request: String) -> String? {
    for editor in allowed where request.localizedCaseInsensitiveContains(editor) { return editor }
    let lower = request.lowercased()
    return aliases.first { lower.contains($0.key) }?.value
  }

  private static func explicitUnknownEditor(in request: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: "([A-Za-z][A-Za-z0-9_-]{1,30})\\s*(?:에서|으로|로)"),
      let match = regex.firstMatch(in: request, range: NSRange(request.startIndex..., in: request)),
      let range = Range(match.range(at: 1), in: request) else { return nil }
    return String(request[range])
  }
}
