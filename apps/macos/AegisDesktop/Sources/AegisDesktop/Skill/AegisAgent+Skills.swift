import Foundation

@MainActor
extension AegisAgent {
  func matchedSkill(_ request: String) -> LearnedSkill? {
    guard let skills = try? skillStore.repository.skills(),
          let skill = SkillMatcher.match(request, skills: skills),
          SkillValidator.errors(in: skill).isEmpty else { return nil }
    chat.append(.system, "Skill 실행: \(skill.name)")
    return skill
  }

  func finishSkillExecution(_ executor: AgentPlanExecutor) {
    if let skill = activeSkill {
      let outcomes = executor.state.outcomes.values
      let succeeded = outcomes.count == executor.state.plan.steps.count && outcomes.allSatisfy { $0 == .succeeded }
      try? skillStore.repository.recordUsage(skill: skill, request: executor.state.request,
        succeeded: succeeded)
      activeSkill = nil
      return
    }
    proposeRepeatedSkillIfNeeded()
  }

  func proposeRepeatedSkillIfNeeded() {
    guard pendingSkillProposal == nil else { return }
    let analysis = SkillProposalAnalysis.detect(
      loadHistory: { try memoryStore.repository.records(type: .actionHistory) },
      loadSkills: { try skillStore.repository.skills() })
    let candidate: SkillCandidate
    switch analysis {
    case .success(let value): guard let value else { return }; candidate = value
    case .failure(let error):
      NSLog("Aegis skill candidate detection skipped: %@", error.localizedDescription)
      return
    }
    guard !ignoredSkillPatterns.contains(SkillPattern(steps: candidate.steps)) else { return }
    pendingSkillProposal = PendingSkillProposal(candidate: candidate)
    let actions = candidate.steps.map(\.action.rawValue).joined(separator: " → ")
    chat.appendApproval(id: candidate.id, content:
      "이 작업을 \(candidate.evidenceCount)번 성공했어요. ‘\(candidate.suggestedName)’ Skill로 저장할까요?\n\(actions)",
      kind: "skill_save")
  }

  func saveSkillProposal() {
    guard let proposal = pendingSkillProposal else { return }
    let candidate = proposal.candidate
    let skill = LearnedSkill(name: candidate.suggestedName,
      description: "반복된 성공 작업에서 제안됨", steps: candidate.steps)
    do {
      _ = try skillStore.repository.save(skill)
      chat.resolveApproval(id: candidate.id, state: .approved)
      chat.append(.assistant, "Skill을 저장했습니다: \(skill.name)")
    } catch { chat.append(.error, error.localizedDescription) }
    pendingSkillProposal = nil
  }

  func rejectSkillProposal() {
    guard let candidate = pendingSkillProposal?.candidate else { return }
    ignoredSkillPatterns.insert(SkillPattern(steps: candidate.steps))
    chat.resolveApproval(id: candidate.id, state: .rejected)
    chat.append(.system, "Skill 제안을 무시했습니다. 저장된 내용은 없습니다.")
    pendingSkillProposal = nil
  }
}
