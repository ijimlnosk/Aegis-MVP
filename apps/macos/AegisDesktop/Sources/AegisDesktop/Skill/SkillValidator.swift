import Foundation

enum SkillValidator {
  static func errors(in skill: LearnedSkill) -> [String] {
    var errors: [String] = []
    if skill.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors.append("skill name is required")
    }
    let plan = AgentPlan(steps: skill.steps)
    errors += AgentPlanValidator.errors(in: plan, for: "stored skill",
      enforceRequestIntent: false)
    if skill.steps.contains(where: containsExecutableText) {
      errors.append("executable command text is forbidden in skills")
    }
    return errors
  }

  static func validate(_ skill: LearnedSkill) throws {
    let problems = errors(in: skill)
    guard problems.isEmpty else { throw SkillError.invalid(problems) }
  }

  private static func containsExecutableText(_ step: AgentStep) -> Bool {
    let values = [step.recipient, step.body, step.application, step.browser, step.site,
      step.query, step.content, step.project, step.container].compactMap { $0?.lowercased() }
    let forbidden = ["rm -rf", "sudo ", "/bin/sh", "bash -c", "zsh -c", "curl http", "wget http"]
    return values.contains { value in forbidden.contains(where: value.contains) }
  }
}

enum SkillError: Error, LocalizedError {
  case invalid([String])
  case notFound
  case storage(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let errors): "유효하지 않은 Skill입니다: \(errors.joined(separator: ", "))"
    case .notFound: "Skill을 찾지 못했습니다."
    case .storage(let message): "Skill 저장소 오류: \(message)"
    }
  }
}
