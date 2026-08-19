import Foundation

final class SkillStore {
  let repository: SkillRepository
  init(repository: SkillRepository = SkillRepository()) {
    self.repository = repository; try? repository.bootstrap()
  }

  func handle(_ intent: SkillIntent) throws -> String {
    switch intent {
    case .teach(let name, let aliases, let plan):
      let existing = try repository.find(name)
      let skill = LearnedSkill(id: existing?.id ?? UUID(), name: name, aliases: aliases,
        description: "사용자가 직접 가르친 작업", steps: plan.steps, confidence: 1,
        usageCount: existing?.usageCount ?? 0, createdAt: existing?.createdAt ?? .now)
      _ = try repository.save(skill)
      return "Skill을 저장했습니다: \(name)\n\(describe(skill))"
    case .list:
      let skills = try repository.skills()
      return skills.isEmpty ? "배운 Skill이 없습니다." : skills.map { "• \($0.name) · \($0.steps.count)단계 · 신뢰도 \(percent($0.confidence))" }.joined(separator: "\n")
    case .inspect(let name):
      guard let skill = try repository.find(name) else { throw SkillError.notFound }
      return describe(skill)
    case .forget(let name):
      return try repository.delete(name) ? "Skill을 잊었습니다: \(name)" : "Skill을 찾지 못했습니다: \(name)"
    case .rename(let old, let new):
      guard var skill = try repository.find(old) else { throw SkillError.notFound }
      skill.name = new; skill.updatedAt = .now; _ = try repository.save(skill)
      return "Skill 이름을 바꿨습니다: \(old) → \(new)"
    }
  }

  func describe(_ skill: LearnedSkill) -> String {
    let aliases = skill.aliases.isEmpty ? "없음" : skill.aliases.joined(separator: ", ")
    let steps = skill.steps.enumerated().map { "\($0.offset + 1). \($0.element.action.rawValue)\(target($0.element))" }.joined(separator: "\n")
    return "\(skill.name)\n별칭: \(aliases)\n\(steps)"
  }

  private func target(_ step: AgentStep) -> String {
    let value = step.project ?? step.container ?? step.application ?? step.site
    return value.map { " (\($0))" } ?? ""
  }
  private func percent(_ value: Double) -> String { "\(Int(value * 100))%" }
}
