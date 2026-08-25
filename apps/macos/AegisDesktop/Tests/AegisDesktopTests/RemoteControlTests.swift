import Foundation
import Testing
@testable import AegisDesktop

@Test func remoteControlConfigurationDefaultsDisabledWithoutTokenExposure() {
  let configuration = RemoteControlConfiguration.load([:])
  #expect(!configuration.enabled)
  #expect(configuration.host == "127.0.0.1")
  #expect(configuration.port == 8790)
  #expect(configuration.binding == "loopback")
}

@Test func remoteControlRecognizesTailscaleBinding() {
  let configuration = RemoteControlConfiguration.load([
    "AEGIS_REMOTE_ENABLED": "true", "AEGIS_REMOTE_HOST": "100.74.88.48",
    "AEGIS_REMOTE_PORT": "8790", "AEGIS_REMOTE_TOKEN": "secret-not-read-by-diagnostics",
  ])
  #expect(configuration.enabled)
  #expect(configuration.binding == "Tailscale")
}

@Test func remoteControlStatusIntentIsDeterministicAndReadOnly() {
  let plan = RemoteControlIntentResolver.plan(for: "원격 제어 상태 보여줘")
  #expect(plan?.steps.first?.action == .getRemoteControlStatus)
  #expect(plan?.steps.first?.dependency == .independent)
  #expect(ApprovalPolicy.risk(for: .getRemoteControlStatus) == .safeRead)
}

@Test func desktopBridgeConfigurationIsLocalOnlyAndUsesDedicatedPort() {
  let configured = DesktopBridgeConfiguration.load([
    "AEGIS_DESKTOP_BRIDGE_HOST": "0.0.0.0", "AEGIS_DESKTOP_BRIDGE_PORT": "8791",
    "AEGIS_DESKTOP_BRIDGE_TOKEN": String(repeating: "x", count: 40),
  ])
  #expect(configured.enabled)
  #expect(configured.host == "127.0.0.1")
  #expect(configured.port == 8791)
}

@Test func desktopBridgeRequiresValidInternalBearerToken() {
  let token = String(repeating: "s", count: 40)
  #expect(DesktopBridgeAuthentication.matches("Bearer \(token)", token: token))
  #expect(!DesktopBridgeAuthentication.matches("Bearer wrong", token: token))
}

@Test func desktopBridgeParsesOnlyNaturalLanguageCommandEnvelope() throws {
  let body = #"{"sessionId":"phone","commandId":"one","text":"PTFriends 상태 보여줘"}"#
  let raw = "POST /v1/commands HTTP/1.1\r\nAuthorization: Bearer token\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
  let request = try #require(HTTPBridgeRequest(data: Data(raw.utf8)))
  let command: DesktopBridgeCommand? = request.decode()
  #expect(command?.text == "PTFriends 상태 보여줘")
}

@MainActor @Test func desktopBridgeSessionOwnsItsConversationContext() {
  let first = DesktopBridgeSession(sessionID: "S1")
  let second = DesktopBridgeSession(sessionID: "S2")
  #expect(first.agent.conversationSessionID == "S1")
  #expect(first.agent.gitWorkflowContext.sessionId == "S1")
  #expect(second.agent.gitWorkflowContext.sessionId == "S2")
  #expect(first.agent !== second.agent)
  #expect(!first.hasActiveCommand)
}
