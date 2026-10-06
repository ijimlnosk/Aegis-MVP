import AppKit
import Foundation

extension AegisAgent {
  func launch(_ application: String, request: String) {
    busy = true
    recordActivity("\(application) 실행")
    Task {
      let message = await MacApplicationLauncher.open(application)
      busy = false
      LearningMemory.record(request: request, action: "open_application", result: message)
      memoryStore.recordAction(request: request, action: "open_application", target: application,
        result: message, succeeded: resultSucceeded(message))
      speak(message)
      completeCurrentStep(succeeded: resultSucceeded(message))
    }
  }

  func close(_ application: String, request: String) {
    busy = true
    recordActivity("\(application) 종료")
    Task {
      let result = await MacApplicationLauncher.close(application)
      busy = false
      LearningMemory.record(request: request, action: "close_application", result: result)
      memoryStore.recordAction(request: request, action: "close_application", target: application,
        result: result, succeeded: resultSucceeded(result))
      speak(result)
      completeCurrentStep(succeeded: resultSucceeded(result))
    }
  }

  func search(browser: String, site: String, query: String, request: String) {
    busy = true
    recordActivity("\(browser)에서 \(site) 검색")
    Task {
      let result = await BrowserTools.search(browser: browser, site: site, query: query)
      busy = false
      LearningMemory.record(request: request, action: "browser_search", result: result)
      memoryStore.recordAction(request: request, action: "browser_search", target: "\(browser):\(site)",
        result: result, succeeded: resultSucceeded(result))
      speak(result)
      completeCurrentStep(succeeded: resultSucceeded(result))
    }
  }

  func openRememberedProject(_ project: String, request: String) {
    do {
      guard let memory = try memoryStore.repository.find(type: .project, key: project) else {
        throw MemoryProjectError.unknownProject(project)
      }
      let url = URL(fileURLWithPath: memory.value).standardizedFileURL
      guard memory.value.hasPrefix("/"), FileManager.default.fileExists(atPath: url.path) else {
        throw MemoryProjectError.invalidPath(memory.value)
      }
      let succeeded = NSWorkspace.shared.open(url)
      let result = succeeded ? "\(project) 프로젝트를 열었습니다." : "\(project) 프로젝트를 열지 못했습니다."
      memoryStore.recordAction(request: request, action: "open_application", target: project,
        result: result, succeeded: succeeded)
      speak(result)
      completeCurrentStep(succeeded: succeeded)
    } catch { failCurrentStep(error.localizedDescription) }
  }

  func openProject(_ project: String, application: String, request: String) {
    switch ProjectOpeningService.resolve(project: project, application: application,
      repository: memoryStore.repository) {
    case .failure(let error): failCurrentStep(error.localizedDescription)
    case .success(let resolved):
      busy = true
      Task {
        let result = await ProjectOpeningService.open(resolved)
        busy = false
        switch result {
        case .success(let message):
          memoryStore.recordAction(request: request, action: AgentAction.openProject.rawValue,
            target: resolved.project, result: message, succeeded: true)
          speak(message); completeCurrentStep(succeeded: true)
        case .failure(let error):
          memoryStore.recordAction(request: request, action: AgentAction.openProject.rawValue,
            target: resolved.project, result: error.localizedDescription, succeeded: false)
          failCurrentStep(error.localizedDescription)
        }
      }
    }
  }
}
