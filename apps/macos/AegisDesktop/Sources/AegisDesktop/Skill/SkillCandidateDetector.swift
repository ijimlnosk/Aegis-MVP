import Foundation

struct SkillCandidateDetector {
  let threshold: Int
  init(threshold: Int = 3) { self.threshold = max(1, threshold) }

  func detect(sequences: [[AgentStep]], existing: [LearnedSkill] = []) -> SkillCandidate? {
    let valid = sequences.filter { !$0.isEmpty && $0.count <= AgentPlan.maximumSteps }
      .filter { AgentPlanValidator.errors(in: AgentPlan(steps: $0), for: "history", enforceRequestIntent: false).isEmpty }
    let groups = Dictionary(grouping: valid, by: SkillPattern.init)
    guard let group = groups.values.filter({ $0.count >= threshold })
      .sorted(by: { left, right in
        left.count == right.count ? (left.first?.count ?? 0) > (right.first?.count ?? 0)
          : left.count > right.count
      }).first, let steps = group.first else { return nil }
    let pattern = SkillPattern(steps: steps)
    guard !existing.contains(where: { SkillPattern(steps: $0.steps) == pattern }) else { return nil }
    let normalized = PlanDependencyNormalizer.normalize(AgentPlan(steps: steps)).steps
    return SkillCandidate(suggestedName: suggestedName(normalized), steps: normalized,
      evidenceCount: group.count)
  }

  func sequences(from records: [MemoryRecord]) -> [[AgentStep]] {
    let values = records.compactMap { record -> ActionHistoryValue? in
      guard record.type == .actionHistory else { return nil }
      return try? JSONDecoder().decode(ActionHistoryValue.self, from: Data(record.value.utf8))
    }.filter(\.succeeded).sorted { $0.timestamp < $1.timestamp }
    var sequences = Dictionary(grouping: values, by: { SkillMatcher.normalize($0.request) }).values.flatMap { group in
      let steps = group.compactMap(step)
      return repeatedChunks(steps)
    }
    sequences += repeatedChunks(values.compactMap(step))
    return sequences.map(normalizeProjectOpen)
  }

  func detect(records: [MemoryRecord], existing: [LearnedSkill] = []) -> SkillCandidate? {
    detect(sequences: sequences(from: records), existing: existing)
  }

  private func step(_ value: ActionHistoryValue) -> AgentStep? {
    guard let action = AgentAction(rawValue: value.action), action != .unknown else { return nil }
    switch action {
    case .openApplication: return AgentStep(action: action, application: value.target)
    case .openProject:
      return AgentStep(action: action, application: "Visual Studio Code", project: value.target)
    case .getRememberedProjectStatus, .getServerProjectStatus: return AgentStep(action: action, project: value.target)
    case .getDockerLogs, .startDockerContainer, .stopDockerContainer, .restartDockerContainer:
      return AgentStep(action: action, container: value.target)
    case .getServerStatus, .getDockerContainers, .getSystemStatus, .getClipboard,
         .getActiveApplication, .listRunningApplications: return AgentStep(action: action)
    default: return nil
    }
  }

  private func suggestedName(_ steps: [AgentStep]) -> String {
    if let project = steps.compactMap(\.project).first { return "\(project) 작업 시작" }
    if steps.contains(where: { $0.action == .getServerStatus }) { return "서버 점검" }
    return "자주 쓰는 작업"
  }

  private func repeatingPeriod(_ steps: [AgentStep]) -> Int? {
    guard !steps.isEmpty, steps.count >= threshold else { return nil }
    let maximum = min(AgentPlan.maximumSteps, steps.count / threshold)
    guard maximum >= 1 else { return nil }
    for size in 1...maximum {
      guard steps.count.isMultiple(of: size),
        let first = chunk(steps, start: 0, size: size) else { continue }
      let pattern = SkillPattern(steps: first)
      let chunks = completeChunks(steps, size: size)
      if chunks.count >= threshold, chunks.allSatisfy({ SkillPattern(steps: $0) == pattern }) { return size }
    }
    return nil
  }

  private func repeatedChunks(_ steps: [AgentStep]) -> [[AgentStep]] {
    guard let period = repeatingPeriod(steps), period > 0 else { return [] }
    return completeChunks(steps, size: period)
  }

  private func completeChunks(_ steps: [AgentStep], size: Int) -> [[AgentStep]] {
    guard size > 0, !steps.isEmpty, steps.count.isMultiple(of: size) else { return [] }
    var result: [[AgentStep]] = [], start = 0
    while start < steps.count {
      guard let value = chunk(steps, start: start, size: size) else { return [] }
      result.append(value); start += size
    }
    return result
  }

  private func chunk(_ steps: [AgentStep], start: Int, size: Int) -> [AgentStep]? {
    guard start >= 0, size > 0, start <= steps.count,
      size <= steps.count - start else { return nil }
    return Array(steps[start..<(start + size)])
  }

  private func normalizeProjectOpen(_ steps: [AgentStep]) -> [AgentStep] {
    guard steps.count > 1 else { return steps }
    return steps.enumerated().map { index, step in
      guard step.action == .openApplication, index + 1 < steps.count,
        let project = steps[index + 1].project, step.application == project else { return step }
      return AgentStep(action: .openApplication, application: "Visual Studio Code", project: project)
    }
  }
}
