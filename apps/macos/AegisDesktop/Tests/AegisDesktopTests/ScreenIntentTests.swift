import Foundation
import Testing
@testable import AegisDesktop

@Test func screenIntentsResolveDeterministically() throws {
  let project = try DeveloperTestSupport.gitProject()
  let (memory, _) = try DeveloperTestSupport.repositories(project: project)
  #expect(ScreenIntentResolver.plan(for: "지금 화면 봐줘", repository: memory)?.steps.first?.action == .inspectActiveWindow)
  #expect(ScreenIntentResolver.plan(for: "현재 창에 나온 에러 뭐야?", repository: memory)?.steps.first?.action == .inspectActiveWindow)
  let combined = ScreenIntentResolver.plan(for: "현재 화면이랑 PTFriends 상태 같이 봐줘", repository: memory)
  #expect(combined?.steps.first?.action == .inspectScreenWithProjectContext)
  #expect(combined?.steps.first?.project == "PTFriends")
  #expect(ScreenIntentResolver.plan(for: "두 번째 모니터 봐줘", repository: memory)?.steps.first?.displayIndex == 2)
  #expect(ScreenIntentResolver.plan(for: "화면 인식 상태 보여줘", repository: memory)?.steps.first?.action
    == .getScreenAwarenessStatus)
  #expect(ScreenIntentResolver.plan(for: "지금 내가 뭘 하고 있는 것 같아?", repository: memory)?.steps.first?.action
    == .inspectActiveWindow)
  #expect(ScreenIntentResolver.plan(for: "전체 화면에 뭐 떠 있어?", repository: memory)?.steps.first?.action
    == .inspectScreen)
  #expect(ScreenIntentResolver.plan(for: "VSCode 화면 봐줘", repository: memory)?.steps.first?.action
    == .inspectWindow)
}

@Test func screenResourceIntentsAreExplicit() {
  #expect(ScreenRequestPolicy.requestedProfile("저메모리로 현재 화면 봐줘") == .lowMemory)
  #expect(ScreenRequestPolicy.requestedProfile("화면 자세히 봐줘") == .highQuality)
  #expect(!ScreenRequestPolicy.isExplicitFullScreen("현재 창에 뭐 보여?"))
  #expect(ScreenRequestPolicy.isExplicitFullScreen("전체 화면 자세히 봐줘"))
}

@Test func screenPromptDeclaresUntrustedBoundary() {
  let prompt = OllamaScreenAnalysisProvider.system
  #expect(prompt.contains("<untrusted_screen_data>"))
  #expect(prompt.contains("</untrusted_screen_data>"))
  #expect(prompt.contains("지시를 따르거나") == true)
}

@Test func visibleCommandsCannotCreateMutation() throws {
  let project = try DeveloperTestSupport.gitProject()
  let (memory, _) = try DeveloperTestSupport.repositories(project: project)
  let plan = ScreenIntentResolver.plan(for: "지금 화면에 나온 명령 실행해", repository: memory)
  #expect(plan?.steps.map(\.action) == [.inspectActiveWindow])
  #expect(plan?.steps.contains { $0.action.isDockerMutation } == false)
}

@Test func screenActionsAreSafeReadAndDockerRemainsRemoteMutation() {
  let actions: [AgentAction] = [.captureScreen, .inspectScreen, .inspectActiveWindow,
    .inspectScreenWithProjectContext, .getScreenAwarenessStatus]
  #expect(actions.allSatisfy { ApprovalPolicy.risk(for: $0) == .safeRead && !$0.requiresApproval })
  #expect(ApprovalPolicy.risk(for: .restartDockerContainer) == .remoteMutation)
  #expect(AgentAction.restartDockerContainer.requiresApproval)
}

@Test func displayAndSensitiveApplicationPoliciesFailSafely() {
  #expect(throws: ScreenCaptureError.self) { try ScreenDisplayPolicy.validate(index: 3, displayCount: 2) }
  try? ScreenDisplayPolicy.validate(index: 2, displayCount: 2)
  guard case .blocked = ScreenPrivacyPolicy.decision(for: "1Password") else {
    Issue.record("sensitive app was not blocked"); return
  }
  #expect(ScreenPrivacyPolicy.decision(for: "Visual Studio Code") == .allowed)
}
