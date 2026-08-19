import Foundation

enum ContainerTargetError: LocalizedError, Equatable {
  case project(String)
  case unknown(String)
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .project(let name): "\(name)은 Docker 컨테이너가 아니라 등록된 프로젝트입니다. 프로젝트 열기나 상태 확인을 요청해 주세요."
    case .unknown(let name): "현재 Docker 목록에서 정확히 일치하는 컨테이너를 찾지 못했습니다: \(name)"
    case .invalid(let name): "안전하지 않은 컨테이너 이름이라 실행하지 않았습니다: \(name)"
    }
  }
}

enum ContainerTargetValidator {
  static func validate(_ name: String, inventory: [DockerContext], knownProjects: [ProjectEntity],
                       explicitDockerContext: Bool) -> Result<String, ContainerTargetError> {
    guard DockerInventoryParser.isSafeName(name) else { return .failure(.invalid(name)) }
    let project = knownProjects.first { item in
      ([item.name] + item.aliases).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
    if let project, !explicitDockerContext { return .failure(.project(project.name)) }
    guard let exact = inventory.first(where: { $0.name == name }) else { return .failure(.unknown(name)) }
    return .success(exact.name)
  }
}
