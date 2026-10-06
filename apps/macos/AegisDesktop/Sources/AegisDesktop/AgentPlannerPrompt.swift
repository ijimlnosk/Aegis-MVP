import Foundation

/// Planner guidance split by domain so a request only carries the rules for actions it can use.
enum AgentPlannerPrompt {
  static let system = system(for: PlannerDomain.allCases)

  static func system(for domains: [PlannerDomain]) -> String {
    ([coreRules] + domains.map(guidance) + [closingRules]).joined(separator: "\n")
  }

  static func guidance(_ domain: PlannerDomain) -> String {
    switch domain {
    case .project: projectRules
    case .coding: codingRules
    case .git: gitRules
    case .server: serverRules
    case .mac: macRules
    case .browser: browserRules
    case .screen: screenRules
    case .ui: uiRules
    case .message: messageRules
    }
  }

  static func memoryData(_ records: [MemoryRecord]) -> String {
    guard !records.isEmpty else { return "[]" }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = (try? encoder.encode(records)) ?? Data("[]".utf8)
    return "<untrusted_memory_data>\n\(String(decoding: data, as: UTF8.self))\n</untrusted_memory_data>"
  }
}
