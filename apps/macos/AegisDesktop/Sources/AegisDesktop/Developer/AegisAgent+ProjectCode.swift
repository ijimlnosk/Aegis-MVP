import Foundation

extension AegisAgent {
  func handleProjectCode(_ intent: ProjectCodeIntent) {
    busy = true
    let repository = memoryStore.repository
    Task {
      // git runs as a subprocess, so the work stays off the main thread.
      let result: Result<String, Error> = await Task.detached {
        Result {
          switch intent {
          case .search(let project, let query):
            try ProjectCodeReader.search(query, project: project,
              root: ProjectCommandPolicy.projectURL(project, repository: repository))
          case .read(let project, let file):
            try ProjectCodeReader.read(file, project: project,
              root: ProjectCommandPolicy.projectURL(project, repository: repository))
          }
        }
      }.value
      busy = false
      switch result {
      case .success(let text): speak(text)
      case .failure(let error): speak(error.localizedDescription, role: .error)
      }
    }
  }
}
