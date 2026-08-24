import Testing
@testable import AegisDesktop

@Test func capabilityQuestionsReturnAnswerWithoutActions() {
  for request in ["너가 지금 할 수 있는 기능이 뭐가있어?", "뭘 할 수 있어?", "도움말"] {
    let plan = CapabilityIntentResolver.plan(for: request)
    #expect(plan?.steps.isEmpty == true)
    #expect(plan?.finalAnswer?.contains("현재 창") == true)
    #expect(AgentPlanValidator.errors(in: plan!, for: request).isEmpty)
  }
  let reordered = CapabilityIntentResolver.plan(for: "너가 할 수 있는게 뭐가 있어?")
  #expect(reordered?.steps.isEmpty == true)
  #expect(reordered?.finalAnswer?.contains("현재 창") == true)
}

@Test func ordinaryFeatureRequestIsNotClaimedAsCapabilityQuestion() {
  #expect(CapabilityIntentResolver.plan(for: "현재 창 설명해줘") == nil)
  #expect(CapabilityIntentResolver.plan(for: "PTFriends 상태 보여줘") == nil)
}
