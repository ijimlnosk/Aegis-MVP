import Foundation

struct CodingFindingContext: Identifiable, Sendable, Equatable {
  let id: UUID
  let projectId: String
  let projectName: String
  let title: String
  let summary: String
  let evidenceLocations: [String]
  let recommendation: String
  let createdAt: Date
  let sourceTaskId: UUID

  var boundedEvidence: String {
    (["Finding: \(title)", "Summary: \(summary)"]
      + evidenceLocations.map { "Evidence: \($0)" }
      + ["Recommended outcome: \(recommendation)"]).joined(separator: "\n")
  }
}

enum CodingFindingParser {
  static func parse(result: CodingTaskResult) -> CodingFindingContext? {
    guard result.mode == .readOnlyAnalysis, result.status == .succeeded else { return nil }
    let text = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    let title = lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty
      && !$0.hasSuffix(":") } ?? "코드 개선점"
    let evidence = evidenceLocations(in: text)
    let recommendation = section(after: ["권장", "개선 방향", "recommendation"], lines: lines)
      ?? String(text.prefix(600))
    return .init(id: UUID(), projectId: result.project.lowercased(), projectName: result.project,
      title: String(title.prefix(180)), summary: String(text.prefix(1_500)),
      evidenceLocations: Array(evidence.prefix(8)), recommendation: String(recommendation.prefix(600)),
      createdAt: .now, sourceTaskId: result.taskID)
  }

  private static func evidenceLocations(in text: String) -> [String] {
    let pattern = #"(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+:\d+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    var seen = Set<String>()
    return regex.matches(in: text, range: range).compactMap { match in
      guard let range = Range(match.range, in: text) else { return nil }
      let value = String(text[range])
      return seen.insert(value).inserted ? value : nil
    }
  }

  private static func section(after labels: [String], lines: [String]) -> String? {
    guard let index = lines.firstIndex(where: { line in
      labels.contains { line.lowercased().contains($0) }
    }), lines.indices.contains(index + 1) else { return nil }
    return lines[(index + 1)...].prefix { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      .joined(separator: " ")
  }
}
