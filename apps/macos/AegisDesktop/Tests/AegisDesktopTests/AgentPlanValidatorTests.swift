import Testing
@testable import AegisDesktop

@Test func unspecifiedBrowserIsValid() {
  let plan = AgentPlan(step: AgentStep(action: .browserSearch, site: "Google", query: "Swift"))
  #expect(AgentPlanValidator.errors(in: plan, for: "Swift 검색해줘").isEmpty)
}

@Test func validatesGoogleSearch() {
  let plan = AgentPlan(step: AgentStep(action: .browserSearch, browser: "Firefox", site: "Google", query: "MacBook"))
  #expect(AgentPlanValidator.errors(in: plan, for: "Firefox로 MacBook 검색해줘").isEmpty)
}

@Test func validatesYouTubeInternalSearch() {
  let plan = AgentPlan(step: AgentStep(action: .browserSearch, site: "YouTube", query: "아이유 콘서트"))
  #expect(AgentPlanValidator.errors(in: plan, for: "유튜브에서 아이유 콘서트 검색해줘").isEmpty)
}

@Test func siteOnlyOpenRequiresEmptyQuery() {
  let valid = AgentPlan(step: AgentStep(action: .browserSearch, site: "YouTube", query: ""))
  let invalid = AgentPlan(step: AgentStep(action: .browserSearch, site: "YouTube", query: "아이유"))
  #expect(AgentPlanValidator.errors(in: valid, for: "유튜브 열어줘").isEmpty)
  #expect(!AgentPlanValidator.errors(in: invalid, for: "유튜브 열어줘").isEmpty)
}

@Test func searchIntentRequiresQuery() {
  let plan = AgentPlan(step: AgentStep(action: .browserSearch, site: "Google", query: ""))
  #expect(!AgentPlanValidator.errors(in: plan, for: "무언가 검색해줘").isEmpty)
}

@Test func invalidRequiredParametersAreRejected() {
  #expect(!AgentPlanValidator.errors(in: AgentPlan(step: AgentStep(action: .kakaoMessage)), for: "메시지 보내").isEmpty)
  #expect(!AgentPlanValidator.errors(in: AgentPlan(step: AgentStep(action: .getServerProjectStatus)), for: "프로젝트 상태").isEmpty)
  #expect(!AgentPlanValidator.errors(in: AgentPlan(step: AgentStep(action: .restartDockerContainer)), for: "재시작").isEmpty)
}

@Test func validatorStillRejectsFirstStepDependencyWhenNormalizationIsBypassed() {
  let malformed = AgentPlan(steps: [AgentStep(action: .getSystemStatus,
    dependency: .requiresPreviousSuccess)])
  #expect(AgentPlanValidator.errors(in: malformed, for: "Mac 상태")
    .contains("step 1 cannot depend on a previous step"))
}

@Test func clipboardActionsRequireExplicitClipboardIntent() {
  let set = AgentPlan(step: AgentStep(action: .setClipboard, content: "수정하자"))
  let get = AgentPlan(step: AgentStep(action: .getClipboard))
  #expect(!AgentPlanValidator.errors(in: set, for: "수정하자").isEmpty)
  #expect(!AgentPlanValidator.errors(in: get, for: "방금 개선사항에서 나온 거 개선해").isEmpty)
  #expect(AgentPlanValidator.errors(in: set, for: "수정하자를 클립보드에 저장해").isEmpty)
  #expect(AgentPlanValidator.errors(in: get, for: "클립보드 보여줘").isEmpty)
}
