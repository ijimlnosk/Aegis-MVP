import Foundation

enum RequestTimingSummary {
  static func format(_ records: [RequestTimingRecord], window: Int = 50) -> String {
    let recent = Array(records.suffix(window))
    guard !recent.isEmpty else { return "아직 기록된 요청 성능 데이터가 없습니다." }
    let planned = recent.filter { $0.route == "planner" }
    let rules = recent.filter { $0.route == "rule" }
    var lines = ["최근 요청 성능 (\(recent.count)건)",
      "- 전체: 중앙값 \(seconds(percentile(recent.map(\.totalMilliseconds), 0.5)))"
        + " · p90 \(seconds(percentile(recent.map(\.totalMilliseconds), 0.9)))",
      "- 규칙 처리: \(rules.count)건 · 중앙값 \(seconds(percentile(rules.map(\.totalMilliseconds), 0.5)))",
      "- AI planner: \(planned.count)건 · 계획 중앙값 \(seconds(percentile(planned.map(\.planningMilliseconds), 0.5)))"]
    let calls = planned.flatMap(\.plannerCalls)
    for backend in Array(Set(calls.map(\.backend))).sorted() {
      let matching = calls.filter { $0.backend == backend }
      let failed = matching.filter { !$0.succeeded }.count
      lines.append("  - \(backend): \(matching.count)회 (실패 \(failed)) · 중앙값 "
        + seconds(percentile(matching.map(\.milliseconds), 0.5)))
    }
    if !calls.isEmpty {
      lines.append("  - prompt 평균 \(calls.map(\.promptCharacters).reduce(0, +) / calls.count)자")
    }
    if let slowest = recent.max(by: { $0.totalMilliseconds < $1.totalMilliseconds }) {
      lines.append("- 가장 느린 요청: \"\(slowest.request.prefix(40))\" \(seconds(slowest.totalMilliseconds))")
    }
    return lines.joined(separator: "\n")
  }

  static func percentile(_ values: [Int], _ fraction: Double) -> Int {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))]
  }

  private static func seconds(_ milliseconds: Int) -> String {
    String(format: "%.1f초", Double(milliseconds) / 1_000)
  }
}
