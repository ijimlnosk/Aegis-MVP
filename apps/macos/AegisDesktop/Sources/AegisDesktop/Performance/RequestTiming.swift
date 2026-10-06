import Foundation

struct PlannerCallTiming: Codable, Equatable {
  let backend: String
  let milliseconds: Int
  let promptCharacters: Int
  let scope: [PlannerDomain]
  let succeeded: Bool
}

/// AgentPlanner is stateless, so each request passes one of these in to collect its planner calls.
final class PlannerMetrics: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [PlannerCallTiming] = []
  var calls: [PlannerCallTiming] { lock.withLock { values } }
  func record(_ call: PlannerCallTiming) { lock.withLock { values.append(call) } }
}

struct RequestTimingRecord: Codable, Equatable {
  let createdAt: Date
  let source: String
  let request: String
  let plannerCalls: [PlannerCallTiming]
  let totalMilliseconds: Int
  let actions: [String]
  let outcome: String

  var route: String { plannerCalls.isEmpty ? "rule" : "planner" }
  var planningMilliseconds: Int { plannerCalls.reduce(0) { $0 + $1.milliseconds } }
}

/// One in-flight request, from `send` until the agent is idle or waiting for approval.
@MainActor
final class RequestTimingTracker {
  let startedAt = ContinuousClock.now
  let createdAt = Date.now
  let source: String
  let request: String
  let planner = PlannerMetrics()
  private(set) var actions: [String] = []

  init(source: String, request: String) {
    self.source = source
    self.request = SecretRedactor.redact(String(request.prefix(160)))
  }

  func setPlan(_ actions: [String]) { self.actions = actions }

  func finish(outcome: String, now: ContinuousClock.Instant = .now) -> RequestTimingRecord {
    RequestTimingRecord(createdAt: createdAt, source: source, request: request,
      plannerCalls: planner.calls, totalMilliseconds: (now - startedAt).milliseconds,
      actions: actions, outcome: outcome)
  }
}

extension Duration {
  var milliseconds: Int {
    let parts = components
    return Int(parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000)
  }
}

enum SecretRedactor {
  private static let patterns = [#"(?i)(bearer\s+)[A-Za-z0-9._~+/-]+"#,
    #"(?i)((?:api[_-]?key|token|password|secret)\s*[:=]\s*)[^\s,;]+"#,
    #"\b(?:sk|ghp|github_pat)_[A-Za-z0-9_\-]{12,}\b"#]

  static func redact(_ value: String) -> String {
    patterns.reduce(value) { text, pattern in
      text.replacingOccurrences(of: pattern, with: "$1[REDACTED]", options: .regularExpression)
    }
  }
}

struct TimedPlannerCall {
  let promptCharacters: Int
  let scope: PlannerActionScope
  let metrics: PlannerMetrics?

  func run(_ backend: String, _ body: () async throws -> AgentPlan) async throws -> AgentPlan {
    let started = ContinuousClock.now
    do {
      let plan = try await body()
      record(backend, started, succeeded: true)
      return plan
    } catch {
      record(backend, started, succeeded: false)
      throw error
    }
  }

  private func record(_ backend: String, _ started: ContinuousClock.Instant, succeeded: Bool) {
    metrics?.record(PlannerCallTiming(backend: backend, milliseconds: (ContinuousClock.now - started).milliseconds,
      promptCharacters: promptCharacters, scope: scope.domains, succeeded: succeeded))
  }
}
