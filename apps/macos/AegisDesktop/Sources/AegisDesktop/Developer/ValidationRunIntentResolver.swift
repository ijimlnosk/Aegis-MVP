import Foundation

/// "SoolSool lint 검사해줘" runs the named checks; it must not become a code-modification task.
enum ValidationRunIntentResolver {
  private static let checkKeywords: [(ProjectValidationCheck, [String])] = [
    (.typecheck, ["typecheck", "타입체크", "타입 체크", "타입 검사", "tsc"]),
    (.lint, ["lint", "린트"]),
    (.test, ["test", "테스트"]),
    (.build, ["build", "빌드"]),
  ]
  private static let runVerbs = ["실행", "검사", "돌려", "확인", "체크", "점검", "해봐", "해 봐", "해줘", "해 줘"]
  private static let changeVerbs = ["고쳐", "수정", "해결", "리팩터", "추가", "구현", "바꿔", "작성", "만들어",
    "통과시켜", "통과하게", "없애", "제거", "설명", "왜", "자세히"]

  static func checks(in request: String) -> [ProjectValidationCheck] {
    let text = request.lowercased()
    guard runVerbs.contains(where: text.contains), !changeVerbs.contains(where: text.contains) else { return [] }
    return checkKeywords.filter { $0.1.contains(where: text.contains) }.map(\.0)
  }

  static func plan(for request: String, repository: MemoryRepository) -> AgentPlan? {
    let requested = checks(in: request)
    guard !requested.isEmpty, ServerIntentParser.parse(request) == nil,
      let project = ProjectEntityResolver.resolve(in: request, repository: repository) else { return nil }
    return AgentPlan(steps: requested.map { AgentStep(action: action(for: $0), project: project.name) })
  }

  private static func action(for check: ProjectValidationCheck) -> AgentAction {
    switch check {
    case .typecheck: .runProjectTypecheck
    case .lint: .runProjectLint
    case .test: .runProjectTests
    case .build: .runProjectBuild
    }
  }
}
