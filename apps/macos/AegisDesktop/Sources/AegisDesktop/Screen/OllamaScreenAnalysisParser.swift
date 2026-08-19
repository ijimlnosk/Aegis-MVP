import Foundation

enum OllamaScreenAnalysisParser {
  static func parse(_ data: Data) throws -> ScreenAnalysis {
    let envelope = try JSONDecoder().decode(OllamaEnvelope.self, from: data)
    guard let raw = envelope.response ?? envelope.message?.content else {
      throw ScreenAnalysisError.malformedResponse
    }
    let text = normalize(raw)
    guard !text.isEmpty else { throw ScreenAnalysisError.malformedResponse }
    do {
      return try JSONDecoder().decode(ScreenAnalysisDTO.self, from: Data(text.utf8)).analysis
    } catch {
      ScreenAnalysisDiagnostics.decoderFailure(error)
      guard useful(raw) else { throw ScreenAnalysisError.malformedResponse }
      return ScreenAnalysis(summary: boundedSanitized(raw), detectedApplication: nil,
        detectedWindow: nil, visibleErrors: [], visibleWarnings: [], visibleCodeContext: nil,
        visibleUIState: nil, confidence: nil,
        limitations: ["Vision provider returned unstructured output."])
    }
  }

  static func normalize(_ value: String) -> String {
    var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```") {
      text = text.replacingOccurrences(of: #"^```(?:json)?\s*|\s*```$"#,
        with: "", options: .regularExpression)
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return firstJSONObject(in: text) ?? text
  }

  private static func firstJSONObject(in text: String) -> String? {
    var start: String.Index?; var depth = 0; var quoted = false; var escaped = false
    for index in text.indices {
      let character = text[index]
      if quoted {
        if escaped { escaped = false } else if character == "\\" { escaped = true }
        else if character == "\"" { quoted = false }
        continue
      }
      if character == "\"" { quoted = true; continue }
      if character == "{" { if depth == 0 { start = index }; depth += 1 }
      if character == "}", depth > 0 {
        depth -= 1
        if depth == 0, let start { return String(text[start...index]) }
      }
    }
    return nil
  }

  private static func useful(_ text: String) -> Bool {
    text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
  }

  private static func boundedSanitized(_ text: String) -> String {
    let safe = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }
    return String(String.UnicodeScalarView(safe)).trimmingCharacters(in: .whitespacesAndNewlines).prefixString(2_000)
  }
}

private extension String {
  func prefixString(_ count: Int) -> String { String(prefix(count)) }
}

private struct OllamaEnvelope: Decodable {
  let response: String?
  let message: Message?
  struct Message: Decodable { let content: String? }
}
