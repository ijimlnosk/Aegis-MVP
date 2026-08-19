enum PlanDependencyNormalizer {
  static func normalize(_ plan: AgentPlan) -> AgentPlan {
    var previous: AgentStep?
    let steps = plan.steps.map { step -> AgentStep in
      let forced = previous.map {
        $0.action.requiresApproval || step.action.requiresApproval
          || $0.action == .openApplication || $0.action == .openProject
      } ?? false
      let dependency: StepDependency = forced ? .requiresPreviousSuccess : step.dependency
      previous = step
      return AgentStep(id: step.id, action: step.action, dependency: dependency,
        recipient: step.recipient, body: step.body, application: step.application,
        browser: step.browser, site: step.site, query: step.query, content: step.content,
        project: step.project, container: step.container, lines: step.lines)
    }
    return AgentPlan(steps: steps, finalAnswer: plan.finalAnswer)
  }
}
