import Foundation

enum ClaudeCodeOutputParser {
  static func userResult(from data: Data, projectRoot: URL) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
    let raw = (object["result"] as? String) ?? (object["message"] as? String) ?? ""
    return sanitize(raw, root: projectRoot)
  }

  private static func sanitize(_ value: String, root: URL) -> String {
    var text = value.replacingOccurrences(of: root.path + "/", with: "")
    text = text.replacingOccurrences(of: "file://", with: "")
    return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000))
  }
}
