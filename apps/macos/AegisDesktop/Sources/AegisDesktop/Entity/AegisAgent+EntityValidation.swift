import Foundation

@MainActor
extension AegisAgent {
  func validateThenRequestDockerApproval(_ step: AgentStep, request: String, progress: String) {
    busy = true
    Task {
      switch await validateContainer(step.container ?? "", request: request) {
      case .success:
        busy = true
        requestStepApproval(step, request: request, progress: progress)
      case .failure(let error): failCurrentStep(error.localizedDescription)
      }
    }
  }

  func runValidatedDockerMutation(_ step: AgentStep, container: String, request: String) {
    busy = true
    Task {
      switch await validateContainer(container, request: request) {
      case .failure(let error): failCurrentStep(error.localizedDescription)
      case .success(let exact):
        let operation = step.action.rawValue.replacingOccurrences(of: "_docker_container", with: "")
        guard let tool = ServerTool(rawValue: operation) else {
          failCurrentStep("지원하지 않는 서버 작업입니다."); return
        }
        runServerTool(tool, request: request, arguments: ["container": exact], approved: true)
      }
    }
  }

  private func validateContainer(_ name: String, request: String) async
    -> Result<String, ContainerTargetError> {
    guard DockerInventoryParser.isSafeName(name) else { return .failure(.invalid(name)) }
    do {
      let output = try await ServerAgentClient.call(.containers)
      let inventory = DockerInventoryParser.parse(output)
      let projects = ProjectEntityResolver.knownProjects(repository: memoryStore.repository)
      return ContainerTargetValidator.validate(name, inventory: inventory, knownProjects: projects,
        explicitDockerContext: ProjectIntentResolver.hasExplicitDockerContext(request))
    } catch {
      return .failure(.unknown("\(name) · Docker inventory 확인 실패: \(error.localizedDescription)"))
    }
  }
}
