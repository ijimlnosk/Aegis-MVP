import Foundation

enum WatchOutcome: Equatable {
  case waiting
  /// Condition met; the message goes to chat and the phone.
  case met(String)
  /// The check itself cannot work (no gh, bad token); the watch stops with this reason.
  case broken(String)
}

/// Read-only checks behind each watch. Runs off the main thread because `gh` is a subprocess.
enum WatchEvaluator {
  static func evaluate(_ kind: WatchKind, repository: MemoryRepository) async -> WatchOutcome {
    switch kind {
    case .ciFinished(let project): await ci(project, repository: repository)
    case .serverReachable: await server()
    }
  }

  static func ciOutcome(status: String, conclusion: String?, name: String, project: String) -> WatchOutcome {
    guard status.lowercased() == "completed" else { return .waiting }
    let result = conclusion ?? "completed"
    let mark = result == "success" ? "성공" : "실패 (\(result))"
    return .met("\(project) CI '\(name)'이 끝났습니다: \(mark)")
  }

  private static func ci(_ project: String, repository: MemoryRepository) async -> WatchOutcome {
    await Task.detached {
      do {
        let root = try ProjectCommandPolicy.projectURL(project, repository: repository)
        guard let run = try GitHubStatusReader.latestRun(root: root) else { return .broken("\(project)에서 CI 실행 기록을 찾지 못했습니다.") }
        return ciOutcome(status: run.status, conclusion: run.conclusion, name: run.name, project: project)
      } catch GitWorkflowError.authenticationRequired {
        return .broken("GitHub CLI(gh)가 없거나 로그인되지 않아 CI를 확인할 수 없습니다.")
      } catch {
        return .broken("\(project) CI를 확인하지 못했습니다: \(error.localizedDescription)")
      }
    }.value
  }

  private static func server() async -> WatchOutcome {
    do {
      _ = try await ServerAgentClient.call(.status)
      return .met("sol-server 연결이 복구됐습니다.")
    } catch ServerAgentError.offline, ServerAgentError.networkUnavailable {
      return .waiting
    } catch {
      return .broken("sol-server 상태를 확인할 수 없습니다: \(error.localizedDescription)")
    }
  }
}
