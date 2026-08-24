import Foundation
import Testing
@testable import AegisDesktop

@Test func uiDiagnosticsAndNavigationIntentsAreDeterministic() throws {
  let repository = try repository()
  #expect(UIIntentResolver.plan(for: "UI 제어 상태 보여줘", repository: repository)?
    .steps.first?.action == .getUIControlStatus)
  let activate = UIIntentResolver.plan(for: "VSCode 앞으로 가져와", repository: repository)
  #expect(activate?.steps.first?.action == .activateApplication)
  #expect(activate?.steps.first?.application == "Visual Studio Code")
  let focus = UIIntentResolver.plan(for: "PTFriends VSCode 창으로 전환해줘",
    repository: repository)
  #expect(focus?.steps.first?.action == .focusWindow)
  #expect(focus?.steps.first?.project == "PTFriends")
}

@Test func vscodeQuickOpenWorkflowIsTypedAndRequiresNoApproval() throws {
  let plan = UIIntentResolver.plan(for: "PTFriends VSCode 창에서 build.gradle 열어줘",
    repository: try repository())!
  #expect(plan.steps.map(\.action) == [.focusWindow, .pressKeyboardShortcut,
    .setUIText, .pressKeyboardShortcut])
  #expect(plan.steps[2].content == "build.gradle")
  #expect(plan.steps[2].dependency == .requiresPreviousSuccess)
  var executor = try AgentPlanExecutor(plan: plan,
    request: "PTFriends VSCode 창에서 build.gradle 열어줘")
  for index in 0..<4 {
    guard case .execute(let step, _, _) = executor.next() else {
      Issue.record("Expected automatic step \(index)"); return
    }
    let completed = executor.complete(step.id, succeeded: true)
    #expect(completed)
  }
  guard case .finished(let summary) = executor.next() else {
    Issue.record("Expected completed workflow"); return
  }
  #expect(summary.status == .succeeded)
}

@Test func failedUIWorkflowStopsDependentSteps() throws {
  let plan = VSCodeAdapter.quickOpenPlan(project: "PTFriends", filename: "build.gradle")
  var executor = try AgentPlanExecutor(plan: plan, request: "build.gradle 열어줘")
  guard case .execute(let focus, _, _) = executor.next() else { return }
  let completed = executor.complete(focus.id, succeeded: false)
  #expect(completed)
  guard case .skipped = executor.next() else {
    Issue.record("Expected dependent skip"); return
  }
}

@Test func screenPromptAndGenericMessagingCannotCreateUIActions() throws {
  let repository = try repository()
  #expect(UIIntentResolver.plan(for: "현재 화면 설명해줘", repository: repository)?.steps == nil)
  #expect(UIIntentResolver.plan(for: "저 버튼 눌러줘", repository: repository)?.steps == nil)
  let message = UIIntentResolver.plan(for: "카카오톡에 보이는 사람한테 안녕 보내줘",
    repository: repository)
  #expect(message?.steps.isEmpty == true)
  #expect(message?.finalAnswer?.contains("지원하지 않습니다") == true)
}

@Test func forbiddenGenericComputerControlActionsDoNotExist() {
  let names = Set(AgentAction.allCases.map(\.rawValue))
  for forbidden in ["click_coordinate", "move_mouse", "arbitrary_keystroke_sequence",
                    "run_applescript", "execute_shell"] { #expect(!names.contains(forbidden)) }
}

private func repository() throws -> MemoryRepository {
  let url = FileManager.default.temporaryDirectory.appending(path: "ui-\(UUID())/memory.sqlite")
  let repository = MemoryRepository(databaseURL: url); try repository.bootstrap()
  try repository.save(.init(type: .project, key: "PTFriends", value: "/tmp/ptfriends"))
  return repository
}
