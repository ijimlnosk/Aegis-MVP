import Foundation

enum GitWorkflowIntentResolver {
  static func plan(for request: String, repository: MemoryRepository,
                   context: GitWorkflowContext) -> AgentPlan? {
    let text = request.lowercased()
    guard let project = resolveProject(request, repository, context) else { return nil }
    if context.plan != nil,
      ["첫 번째", "두 번째", "세 번째", "1번", "2번", "3번", "빼고", "제외"].contains(where: text.contains) {
      return one(.proposeCommitPlan, project, content: request)
    }
    if text.contains("머지") { return AgentPlan(steps: [], finalAnswer: "자동 PR merge는 Phase 12에서 지원하지 않습니다.") }
    if text.contains("git 작업 상태") { return one(.getGitWorkflowStatus, project) }
    if text.contains("ci 상태") { return one(.getCIStatus, project) }
    if text.contains("pr 상태") || text.contains("pull request") { return one(.getPullRequestStatus, project) }
    let noPush = text.contains("푸시는 하지") || text.contains("커밋까지만")
    let push = !noPush && ["푸시", "push"].contains(where: text.contains)
    let commit = ["커밋", "commit"].contains(where: text.contains)
    guard push || commit else { return nil }
    if push && !commit {
      return AgentPlan(steps: [step(.proposePush, project),
        step(.pushCurrentBranch, project, .requiresPreviousSuccess)])
    }
    let proposalOnly = ["정리해줘", "계획 보여", "단위로 보여", "나눠서 커밋하자"].contains(where: text.contains)
    var steps = [step(.proposeCommitPlan, project, content: request)]
    if !proposalOnly { steps.append(step(.createCommit, project, .requiresPreviousSuccess)) }
    if push {
      steps.append(step(.proposePush, project, .requiresPreviousSuccess))
      steps.append(step(.pushCurrentBranch, project, .requiresPreviousSuccess))
    }
    return AgentPlan(steps: steps)
  }

  private static func resolveProject(_ request: String, _ repository: MemoryRepository,
                                     _ context: GitWorkflowContext) -> String? {
    if let project = ProjectEntityResolver.resolve(in: request, repository: repository) { return project.name }
    return context.plan?.projectId ?? context.pushProposal?.project
  }

  private static func one(_ action: AgentAction, _ project: String,
                          content: String? = nil) -> AgentPlan {
    AgentPlan(steps: [step(action, project, content: content)])
  }
  private static func step(_ action: AgentAction, _ project: String,
                           _ dependency: StepDependency = .independent,
                           content: String? = nil) -> AgentStep {
    AgentStep(action: action, dependency: dependency, content: content, project: project)
  }
}
