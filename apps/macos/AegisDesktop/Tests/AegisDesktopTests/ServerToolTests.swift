import Testing
@testable import AegisDesktop

@Test func readToolsUseOnlyFixedEndpoints() {
  #expect(ServerTool.status.path == "/v1/tools/system-status")
  #expect(ServerTool.containers.path == "/v1/tools/docker-containers")
  #expect(ServerTool.logs.path == "/v1/tools/docker-logs")
  #expect(ServerTool.projectStatus.path == "/v1/tools/project-status")
  #expect(!ServerTool.status.requiresApproval)
}

@Test func mutationsRequireApprovalAndUseFixedEndpoints() {
  #expect(ServerTool.start.requiresApproval)
  #expect(ServerTool.stop.requiresApproval)
  #expect(ServerTool.restart.requiresApproval)
  #expect(ServerTool.start.path == "/v1/tools/docker-start")
  #expect(ServerTool.stop.path == "/v1/tools/docker-stop")
  #expect(ServerTool.restart.path == "/v1/tools/docker-restart")
}
