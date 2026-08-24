import Foundation

enum CodexJSONOutputParser {
  struct Parsed: Sendable, Equatable { let userResult: String; let events: [CodingProviderEvent] }

  static func userResult(from data: Data, projectRoot: URL, limit: Int = 3_000) -> String {
    parse(data, projectRoot: projectRoot, limit: limit).userResult
  }

  static func parse(_ data: Data, projectRoot: URL, limit: Int = 3_000) -> Parsed {
    let objects = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
      .compactMap(jsonObject)
    let messages = objects.compactMap(parseAgentMessage)
    let result = messages.last.map { sanitize(String($0.prefix(limit)), projectRoot: projectRoot) } ?? ""
    return Parsed(userResult: result, events: objects.compactMap(event))
  }

  private static func jsonObject(_ line: Substring) -> [String: Any]? {
    guard let data = String(line).data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  private static func parseAgentMessage(_ root: [String: Any]) -> String? {
    guard
      root["type"] as? String == "item.completed",
      let item = root["item"] as? [String: Any], item["type"] as? String == "agent_message"
    else { return nil }
    return item["text"] as? String ?? item["content"] as? String
  }

  private static func event(_ root: [String: Any]) -> CodingProviderEvent? {
    switch root["type"] as? String {
    case "thread.started": .started
    case "turn.started": .analyzing
    case "item.completed": parseAgentMessage(root) == nil ? nil : .resultReceived
    case "turn.completed": .completed
    case "turn.failed", "error": .failed
    default: nil
    }
  }

  private static func sanitize(_ value: String, projectRoot: URL) -> String {
    let root = projectRoot.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let forbidden = ["Reading additional input from stdin", "OpenAI Codex v", "workdir:",
      "model:", "approval:", "sandbox:", "session id:", "tokens used", "exec", "/bin/zsh -lc"]
    return value.replacingOccurrences(of: "file://", with: "")
      .replacingOccurrences(of: "/\(root)/", with: "")
      .split(whereSeparator: \.isNewline)
      .filter { line in !forbidden.contains { line.trimmingCharacters(in: .whitespaces).hasPrefix($0) } }
      .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
