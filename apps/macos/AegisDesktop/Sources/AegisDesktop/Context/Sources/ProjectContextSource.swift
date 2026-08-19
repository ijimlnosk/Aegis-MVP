import Foundation

struct ProjectContextSource: ContextSource {
  let kind = ContextSourceKind.projects
  let repository: MemoryRepository

  func collect() async throws -> ContextSourceResult {
    let memories = (try? repository.records(type: .project)) ?? []
    let projects = memories.map { memory -> ProjectContext in
      do {
        let status = try MemoryProjectTool.status(project: memory.key, repository: repository)
        let lines = status.split(separator: "\n").map(String.init)
        let header = lines.first(where: { $0.hasPrefix("##") })
        let branch = header?.dropFirst(2).trimmingCharacters(in: .whitespaces)
          .split(separator: ".").first.map(String.init)
        let changes = lines.filter { !$0.hasPrefix("##") && $0 != "변경 사항 없음" }.count
        return ProjectContext(name: memory.key, available: true, branch: branch,
          isDirty: changes > 0, changedFileCount: changes)
      } catch {
        return ProjectContext(name: memory.key, available: false, branch: nil,
          isDirty: false, changedFileCount: 0)
      }
    }
    return .projects(projects)
  }
}
