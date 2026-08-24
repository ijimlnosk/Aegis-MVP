import Foundation
import Testing
@testable import AegisDesktop

@Test func exactWindowTargetPropagatesAcrossMultipleVSCodeWindows() throws {
  let windows = vscodeWindows(activeIndex: 2)
  let target = try ResolvedWindowTarget(windows[0])
  let shortcut = AgentStep(action: .pressKeyboardShortcut,
    application: "Visual Studio Code", shortcut: .quickOpen)
  let resolved = try UIWindowTargetResolver.resolve(step: shortcut, windows: windows,
    workflow: target, recent: nil)
  #expect(resolved.id == windows[0].id)
}

@Test func activeVSCodeWindowWinsForCurrentUIList() throws {
  let windows = vscodeWindows(activeIndex: 0)
  let unrelatedRecent = try ResolvedWindowTarget(windows[2])
  let list = AgentStep(action: .listUIElements, application: "Visual Studio Code")
  let resolved = try UIWindowTargetResolver.resolve(step: list, windows: windows,
    workflow: unrelatedRecent, recent: unrelatedRecent)
  #expect(resolved.id == windows[0].id)
}

@Test func explicitProjectFocusIgnoresUnrelatedRecentVSCodeWindow() throws {
  let windows = vscodeWindows(activeIndex: 2)
  let recent = try ResolvedWindowTarget(windows[2])
  let focus = AgentStep(action: .focusWindow, application: "Visual Studio Code",
    project: "PTFriends")
  let resolved = try UIWindowTargetResolver.resolve(step: focus, windows: windows,
    workflow: nil, recent: recent)
  #expect(resolved.id == windows[0].id)
}

@Test func approvedWindowIdentitySurvivesPreflightAndStaleTargetFails() throws {
  let plan = AgentPlan(steps: [
    AgentStep(action: .focusWindow, application: "Visual Studio Code", project: "PTFriends"),
    AgentStep(action: .setUIText, dependency: .requiresPreviousSuccess,
      application: "Visual Studio Code", content: "let value = 1", project: "PTFriends",
      uiLabel: "editor", inputPurpose: .editorContent),
  ])
  var executor = try AgentPlanExecutor(plan: plan,
    request: "PTFriends VSCode 코드에 let value = 1 입력해줘")
  let target = try ResolvedWindowTarget(vscodeWindows(activeIndex: 0)[0])
  let approvedTarget = try ApprovedUITarget(window: vscodeWindows(activeIndex: 0)[0],
    semanticTarget: "set_ui_text")
  guard case .preflightApproval(let id, _) = executor.next() else {
    Issue.record("preflight approval missing"); return
  }
  executor.setPreflightTarget(approvedTarget, resolvedWindow: target)
  #expect(executor.state.resolvedWindowTarget == target)
  #expect(executor.state.resolvedUIElement == nil)
  let approved = executor.approvePreflight(id)
  #expect(approved)
  #expect(executor.state.approvedUITarget == approvedTarget)
  #expect(throws: UIInteractionError.self) {
    try target.resolve(in: Array(vscodeWindows(activeIndex: 1).dropFirst()))
  }
}

@Test func requiredFailureSkipsDependentsAndSuppressesProposedSuccess() throws {
  let plan = VSCodeAdapter.quickOpenPlan(project: "PTFriends", filename: "build.gradle")
  var executor = try AgentPlanExecutor(plan: plan,
    request: "PTFriends VSCode 창에서 build.gradle 열어줘")
  _ = executor.next(); _ = executor.complete(plan.steps[0].id, succeeded: true)
  _ = executor.next(); _ = executor.complete(plan.steps[1].id, succeeded: false,
    result: "Quick Open을 실행하지 못했습니다.")
  guard case .skipped = executor.next() else { Issue.record("step 3 not skipped"); return }
  guard case .skipped = executor.next() else { Issue.record("step 4 not skipped"); return }
  guard case .finished(let summary) = executor.next() else { Issue.record("not finished"); return }
  let message = PlanExecutionFormatter.format(summary, plan: plan,
    request: "PTFriends VSCode 창에서 build.gradle 열어줘")
  #expect(summary.status == .partiallySucceeded)
  #expect(summary.skippedSteps.count == 2)
  #expect(summary.verifiedOutcome == false)
  #expect(message?.contains("열지 못했습니다") == true)
  #expect(message != plan.finalAnswer)
}

@Test func plannerFinalAnswerAppearsOnlyAfterVerifiedWorkflowSuccess() throws {
  let plan = VSCodeAdapter.quickOpenPlan(project: "PTFriends", filename: "build.gradle")
  var executor = try AgentPlanExecutor(plan: plan,
    request: "PTFriends VSCode 창에서 build.gradle 열어줘")
  for step in plan.steps {
    _ = executor.next()
    if step.action.requiresApproval {
      let approved = executor.approve(step.id); #expect(approved); _ = executor.next()
    }
    let completed = executor.complete(step.id, succeeded: true)
    #expect(completed)
  }
  guard case .finished(let summary) = executor.next() else { Issue.record("not finished"); return }
  #expect(summary.status == .succeeded)
  #expect(summary.verifiedOutcome)
  #expect(PlanExecutionFormatter.format(summary, plan: plan, request: "") == plan.finalAnswer)
}

@Test func openFileVerificationUsesSameWindowIdentity() throws {
  let before = vscodeWindows(activeIndex: 0)
  let target = try ResolvedWindowTarget(before[0])
  var after = before
  after[0] = window(id: before[0].id, title: "build.gradle — ptfriendsapp", active: true)
  #expect(VSCodeAdapter.verifiedOpenFile("build.gradle", target: target,
    windows: after)?.id == target.windowIdentifier)
  #expect(VSCodeAdapter.verifiedOpenFile("build.gradle", target: target,
    windows: before) == nil)
}

private func vscodeWindows(activeIndex: Int) -> [WindowDescriptor] {
  [window(id: 11, title: "CLAUDE.md — ptfriendsapp", active: activeIndex == 0),
   window(id: 12, title: "styling-performance.md — phoneorderweb", active: activeIndex == 1),
   window(id: 13, title: "KakaoTalkAutomation.swift — Aegis-MVP", active: activeIndex == 2)]
}

private func window(id: UInt32, title: String, active: Bool) -> WindowDescriptor {
  WindowDescriptor(id: id, applicationName: "Code", bundleIdentifier: "com.microsoft.VSCode",
    windowTitle: title, displayIndex: 0, isActive: active, isOnScreen: true,
    bounds: .init(x: 0, y: 0, width: 1000, height: 700))
}
