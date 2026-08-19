import Foundation
import Testing
@testable import AegisDesktop

@Test func windowListingAndInspectionPlansAreTyped() throws {
  let (memory, _) = try DeveloperTestSupport.repositories(project: DeveloperTestSupport.gitProject())
  #expect(ScreenIntentResolver.plan(for: "열려 있는 창들 뭐 있어?",
    repository: memory)?.steps.map(\.action) == [.listVisibleWindows])
  let one = ScreenIntentResolver.plan(for: "VSCode 창 봐줘", repository: memory)
  #expect(one?.steps.first?.action == .inspectWindow)
  #expect(one?.steps.first?.application == "Visual Studio Code")
  #expect(ApprovalPolicy.risk(for: .listVisibleWindows) == .safeRead)
  #expect(ApprovalPolicy.risk(for: .inspectWindow) == .safeRead)
}

@Test func exactApplicationAndActiveWindowResolutionAreDeterministic() throws {
  let windows = [window(1, app: "Visual Studio Code", title: "one"),
    window(2, app: "Visual Studio Code", title: "two", active: true)]
  #expect(try WindowResolver.resolve("Visual Studio Code", displayIndex: nil,
    windows: windows).id == 2)
  #expect(try WindowResolver.resolve("two", displayIndex: nil, windows: windows).id == 2)
}

@Test func multipleSameAppWindowsRequireASelection() {
  let windows = [window(1, app: "Xcode", title: "one"),
    window(2, app: "Xcode", title: "two")]
  #expect(throws: WindowResolutionError.self) {
    try WindowResolver.resolve("Xcode", displayIndex: nil, windows: windows)
  }
}

@Test func selectedWindowNeverResolvesAnUnrelatedApp() throws {
  let windows = [window(7, app: "Xcode", title: "Project"),
    window(8, app: "Safari", title: "Private")]
  #expect(try WindowResolver.resolve("Xcode", displayIndex: nil, windows: windows).id == 7)
  #expect(throws: WindowResolutionError.self) {
    try WindowResolver.resolve("Visual Studio Code", displayIndex: nil, windows: windows)
  }
}

@Test func sensitiveWindowTargetsRemainBlocked() {
  guard case .blocked = ScreenPrivacyPolicy.decision(for: "1Password") else {
    Issue.record("Expected sensitive app block"); return
  }
}

@Test func twoWindowComparisonIsSequentialAndBounded() throws {
  let (memory, _) = try DeveloperTestSupport.repositories(project: DeveloperTestSupport.gitProject())
  let plan = ScreenIntentResolver.plan(for: "VSCode랑 Xcode 같이 봐줘", repository: memory)
  #expect(plan?.steps.map(\.application) == ["Visual Studio Code", "Xcode"])
  #expect(plan?.steps.allSatisfy { $0.action == .inspectWindow } == true)
  #expect((plan?.steps.count ?? 0) <= ScreenAnalysisConfiguration.maximumWindows())
}

@Test func displaySelectionIsPreservedForWindowResolution() throws {
  let windows = [window(1, app: "Visual Studio Code", title: "one", display: 1),
    window(2, app: "Visual Studio Code", title: "two", display: 2)]
  #expect(try WindowResolver.resolve("Visual Studio Code", displayIndex: 2,
    windows: windows).id == 2)
}

private func window(_ id: UInt32, app: String, title: String, active: Bool = false,
                    display: Int = 1) -> WindowDescriptor {
  WindowDescriptor(id: id, applicationName: app, bundleIdentifier: nil,
    windowTitle: title, displayIndex: display, isActive: active, isOnScreen: true,
    bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600))
}
