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
  let projectWindow = ScreenIntentResolver.plan(
    for: "VSCode 창 보고 PTFriends에서 지금 뭘 작업하는 것 같은지 알려줘",
    repository: memory)
  #expect(projectWindow?.steps.first?.application == "Visual Studio Code")
  #expect(projectWindow?.steps.first?.project == "PTFriends")
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

@Test func codeSystemNameNormalizesAndResolvesToVisualStudioCode() throws {
  let code = window(10, app: "Code", bundle: "com.microsoft.VSCode", title: "PTFriends")
  #expect(code.canonicalApplication == "Visual Studio Code")
  #expect(try WindowResolver.resolve("Visual Studio Code", displayIndex: nil,
    windows: [code]).id == 10)
}

@Test func visualStudioCodeBundleIdentifierHasHighestPriority() throws {
  let code = window(11, app: "Unexpected Name", bundle: "com.microsoft.VSCode",
    title: "PTFriends")
  #expect(try WindowResolver.resolve("VSCode", displayIndex: nil, windows: [code]).id == 11)
  #expect(try WindowResolver.resolve("com.microsoft.VSCode", displayIndex: nil,
    windows: [code]).id == 11)
}

@Test func allVisualStudioCodeAliasesResolveCanonically() {
  for request in ["VSCode 창 봐줘", "VS Code 창 봐줘", "Visual Studio Code 창 봐줘",
                  "Code 창 봐줘"] {
    #expect(WindowResolver.requestedApplications(in: request) == ["Visual Studio Code"])
  }
  #expect(WindowResolver.requestedApplications(in: "Xcode 창 봐줘") == ["Xcode"])
}

@Test func projectTitleIsPreferredAcrossMultipleVSCodeWindows() throws {
  let windows = [window(20, app: "Code", bundle: "com.microsoft.VSCode", title: "Other"),
    window(21, app: "Code", bundle: "com.microsoft.VSCode", title: "PTFriends — Code")]
  #expect(try WindowResolver.resolve("VSCode", displayIndex: nil,
    preferredTitle: "PTFriends", windows: windows).id == 21)
}

@Test func multipleVSCodeWindowsPreferActiveThenRemainAmbiguous() throws {
  let active = [window(30, app: "Code", bundle: "com.microsoft.VSCode", title: "One"),
    window(31, app: "Code", bundle: "com.microsoft.VSCode", title: "Two", active: true)]
  #expect(try WindowResolver.resolve("VSCode", displayIndex: nil, windows: active).id == 31)
  let ambiguous = active.map { window($0.id, app: $0.applicationName,
    bundle: $0.bundleIdentifier, title: $0.windowTitle ?? "", active: false) }
  #expect(throws: WindowResolutionError.self) {
    try WindowResolver.resolve("VSCode", displayIndex: nil, windows: ambiguous)
  }
}

@Test func unknownApplicationRemainsUnresolved() {
  let windows = [window(40, app: "Unknown Editor", bundle: "dev.unknown.editor", title: "Work")]
  #expect(throws: WindowResolutionError.self) {
    try WindowResolver.resolve("Mystery App", displayIndex: nil, windows: windows)
  }
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

private func window(_ id: UInt32, app: String, bundle: String? = nil, title: String,
                    active: Bool = false, display: Int = 1) -> WindowDescriptor {
  WindowDescriptor(id: id, applicationName: app, bundleIdentifier: bundle,
    windowTitle: title, displayIndex: display, isActive: active, isOnScreen: true,
    bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600))
}
