import Testing
@testable import AegisDesktop

@Test func lockedScreenBlocksOnlyScreenDependentActions() {
  for action: AgentAction in [.kakaoMessage, .inspectScreen, .pressUIElement, .listVisibleWindows] {
    #expect(ScreenLockState.blockingMessage(for: action, locked: true) == ScreenLockState.lockedMessage)
    #expect(ScreenLockState.blockingMessage(for: action, locked: false) == nil)
  }
  for action: AgentAction in [.getProjectGitStatus, .runProjectTests, .getUIControlStatus, .getServerStatus] {
    #expect(ScreenLockState.blockingMessage(for: action, locked: true) == nil)
  }
}

@Test func keepAwakeFollowsRemoteSettingUnlessOverridden() {
  #expect(RemoteKeepAwake.isEnabled(["AEGIS_REMOTE_ENABLED": "true"]))
  #expect(!RemoteKeepAwake.isEnabled([:]))
  #expect(!RemoteKeepAwake.isEnabled(["AEGIS_REMOTE_ENABLED": "true", "AEGIS_REMOTE_KEEP_AWAKE": "false"]))
  #expect(RemoteKeepAwake.isEnabled(["AEGIS_REMOTE_KEEP_AWAKE": "true"]))
}
