import Foundation

/// OpenAI structured outputs (behind `codex exec --output-schema`) reject any object that does not
/// require every property and forbid extra keys, so optional fields become nullable instead.
enum StrictOutputSchema {
  static func make(_ schema: [String: Any]) -> [String: Any] {
    var result = schema
    if let items = schema["items"] as? [String: Any] { result["items"] = make(items) }
    guard let properties = schema["properties"] as? [String: Any] else { return result }
    let required = Set(schema["required"] as? [String] ?? [])
    result["properties"] = properties.reduce(into: [String: Any]()) { converted, entry in
      guard let property = entry.value as? [String: Any] else { return }
      let strict = make(property)
      converted[entry.key] = required.contains(entry.key) ? strict : nullable(strict)
    }
    result["required"] = properties.keys.sorted()
    result["additionalProperties"] = false
    return result
  }

  private static func nullable(_ property: [String: Any]) -> [String: Any] {
    var result = property
    if let type = property["type"] as? String { result["type"] = [type, "null"] }
    if let values = property["enum"] as? [Any] { result["enum"] = values + [NSNull()] }
    return result
  }
}
