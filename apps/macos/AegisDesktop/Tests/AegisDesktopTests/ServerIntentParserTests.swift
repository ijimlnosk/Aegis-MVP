import Testing
@testable import AegisDesktop

@Test func parsesServerStatusAcceptancePhrase() {
  #expect(ServerIntentParser.parse("sol-server 상태 확인해")?.action == .getServerStatus)
}

@Test func parsesDockerListAcceptancePhrase() {
  #expect(ServerIntentParser.parse("서버 Docker 보여줘")?.action == .getDockerContainers)
}

@Test func parsesRestartAsApprovalActionWithContainerOnly() {
  let plan = ServerIntentParser.parse("dksfhomepage 재시작해")
  #expect(plan?.action == .restartDockerContainer)
  #expect(plan?.container == "dksfhomepage")
}

@Test func rejectsCommandLikeContainerInput() {
  #expect(ServerIntentParser.parse("$(whoami) 재시작해") == nil)
}
