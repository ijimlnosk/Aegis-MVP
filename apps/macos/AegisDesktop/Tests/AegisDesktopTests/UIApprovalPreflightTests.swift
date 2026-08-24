import Foundation
import Testing
@testable import AegisDesktop

@Test func contextualInputPurposeControlsRisk() {
  for purpose in [UIInputPurpose.navigationSearch, .commandSearch, .find, .filter] {
    #expect(ApprovalPolicy.risk(for: inputStep(purpose)) == .safeNavigation)
    #expect(!ApprovalPolicy.requiresApproval(for: inputStep(purpose)))
  }
  #expect(ApprovalPolicy.risk(for: inputStep(.editorContent)) == .localMutation)
  #expect(ApprovalPolicy.risk(for: inputStep(.messageContent)) == .sensitiveInteraction)
  #expect(ApprovalPolicy.risk(for: inputStep(.terminalInput)) != .safeNavigation)
  #expect(ApprovalPolicy.requiresApproval(for: inputStep(.unknown)))
}

@Test func secureInputIsBlockedByPlanValidation() {
  let step = inputStep(.secureInput)
  #expect(AgentPlanValidator.errors(in: AgentPlan(step: step), for: "검색창에 value 입력해")
    .contains { $0.contains("secure UI input is blocked") })
}

@Test func quickOpenNavigationRunsWithoutPreflightOrMidWorkflowApproval() throws {
  let plan = VSCodeAdapter.quickOpenPlan(project: "PTFriends", filename: "build.gradle")
  var executor = try AgentPlanExecutor(plan: plan,
    request: "PTFriends VSCode 창에서 build.gradle 열어줘")
  for expected in plan.steps {
    guard case .execute(let step, _, _) = executor.next() else {
      Issue.record("unexpected approval before \(expected.action.rawValue)"); return
    }
    #expect(step.id == expected.id)
    _ = executor.complete(step.id, succeeded: true)
  }
}

@Test func knownMutationIsApprovedBeforeFocusAndReusesNoAXDescriptor() throws {
  let focus = AgentStep(action: .focusWindow, application: "Visual Studio Code",
    project: "PTFriends")
  let edit = AgentStep(action: .setUIText, dependency: .requiresPreviousSuccess,
    application: "Visual Studio Code", content: "value", project: "PTFriends",
    uiLabel: "editor", inputPurpose: .editorContent)
  var executor = try AgentPlanExecutor(plan: AgentPlan(steps: [focus, edit]),
    request: "PTFriends VSCode 코드에 value 입력해줘")
  guard case .preflightApproval(let id, let protected) = executor.next() else {
    Issue.record("mutation was not preflighted"); return
  }
  #expect(executor.state.index == 0)
  #expect(protected.map(\.id) == [edit.id])
  #expect(executor.state.resolvedUIElement == nil)
  let approved = executor.approvePreflight(id)
  #expect(approved)
  guard case .execute(let first, _, _) = executor.next() else {
    Issue.record("focus did not start after approval"); return
  }
  #expect(first.id == focus.id)
}

@Test func approvedTargetIsReresolvedExactlyAndNeverSubstituted() throws {
  let approvedWindow = window(id: 41, title: "CLAUDE.md — ptfriendsapp")
  let otherWindow = window(id: 42, title: "Other — ptfriendsapp")
  let target = try ApprovedUITarget(window: approvedWindow, semanticTarget: "close_window")
  #expect(try target.resolve(in: [approvedWindow, otherWindow]).id == 41)
  #expect(throws: UIInteractionError.self) { try target.resolve(in: [otherWindow]) }
}

private func inputStep(_ purpose: UIInputPurpose) -> AgentStep {
  let labels: [UIInputPurpose: String] = [.navigationSearch: "검색", .commandSearch: "Command Palette",
    .find: "Find", .filter: "Filter"]
  return AgentStep(action: .setUIText, content: "value", uiLabel: labels[purpose] ?? "field",
    inputPurpose: purpose)
}

private func window(id: UInt32, title: String) -> WindowDescriptor {
  WindowDescriptor(id: id, applicationName: "Code", bundleIdentifier: "com.microsoft.VSCode",
    windowTitle: title, displayIndex: 0, isActive: false, isOnScreen: true,
    bounds: .init(x: 0, y: 0, width: 900, height: 700))
}
