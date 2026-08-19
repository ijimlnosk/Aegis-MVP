import Foundation

struct ResolvedProjectOpening: Equatable {
  let project: String
  let application: String
  let path: String
}

enum ProjectOpeningError: LocalizedError, Equatable {
  case unknownProject(String), missingPath(String), invalidPath(String), unknownEditor(String), launchFailed(String)
  var errorDescription: String? {
    switch self {
    case .unknownProject(let value): "등록되거나 기억된 프로젝트가 아닙니다: \(value)"
    case .missingPath(let value): "프로젝트 경로가 설정되지 않았습니다: \(value)"
    case .invalidPath(let value): "프로젝트 경로가 존재하는 디렉터리가 아닙니다: \(value)"
    case .unknownEditor(let value): "허용되지 않은 코드 에디터입니다: \(value)"
    case .launchFailed(let value): "프로젝트를 열지 못했습니다: \(value)"
    }
  }
}

enum ProjectOpeningService {
  static func resolve(project: String, application: String, repository: MemoryRepository,
                      environment: [String: String]? = nil) -> Result<ResolvedProjectOpening, ProjectOpeningError> {
    guard let entity = ProjectEntityResolver.resolve(name: project, repository: repository,
      environment: environment) else { return .failure(.unknownProject(project)) }
    guard let rawPath = entity.path, rawPath.hasPrefix("/") else { return .failure(.missingPath(entity.name)) }
    let url = URL(fileURLWithPath: rawPath).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue else { return .failure(.invalidPath(rawPath)) }
    guard let editor = CodeEditorResolver.canonical(application) else { return .failure(.unknownEditor(application)) }
    return .success(ResolvedProjectOpening(project: entity.name, application: editor, path: url.path))
  }

  static func open(_ value: ResolvedProjectOpening) async -> Result<String, ProjectOpeningError> {
    await Task.detached {
      let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      process.arguments = ["-a", value.application, value.path]
      do { try process.run(); process.waitUntilExit() }
      catch { return .failure(.launchFailed(error.localizedDescription)) }
      return process.terminationStatus == 0
        ? .success("\(value.project) 프로젝트를 \(value.application)에서 열었습니다.")
        : .failure(.launchFailed("open 종료 코드 \(process.terminationStatus)"))
    }.value
  }
}
