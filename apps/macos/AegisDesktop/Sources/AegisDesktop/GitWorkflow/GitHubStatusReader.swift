import Foundation

enum GitHubStatusReader {
  private struct Run: Decodable { let name: String; let status: String; let conclusion: String?; let headBranch: String; let headSha: String }
  private struct PullRequest: Decodable { let number: Int; let title: String; let state: String; let headRefName: String }

  static func ci(project: String, root: URL) throws -> String {
    let output = try run(["run", "list", "--limit", "10",
      "--json", "name,status,conclusion,headBranch,headSha"], root: root)
    guard let data = output.data(using: .utf8), let runs = try? JSONDecoder().decode([Run].self, from: data) else {
      return "\(project) CI 상태를 읽지 못했습니다."
    }
    guard !runs.isEmpty else { return noRunsMessage(project) }
    let lines = runs.prefix(10).map { item in
      let state = item.conclusion?.isEmpty == false ? item.conclusion! : item.status
      return "\(item.name)\t\(state)\t\(item.headBranch)\t\(item.headSha.prefix(7))"
    }
    return "\(project) CI\n" + MessageSegments.code(TextTable.columns(lines.joined(separator: "\n")))
  }

  static func noRunsMessage(_ project: String) -> String {
    "\(project)에는 GitHub Actions 실행 기록이 없습니다. 저장소에 워크플로(.github/workflows)가 없을 수 있습니다."
  }

  /// The most recent run on the current repository, used to watch for CI completion.
  static func latestRun(root: URL) throws -> (name: String, status: String, conclusion: String?)? {
    let output = try run(["run", "list", "--limit", "1", "--json", "name,status,conclusion,headBranch,headSha"], root: root)
    guard let data = output.data(using: .utf8), let run = try? JSONDecoder().decode([Run].self, from: data).first
    else { return nil }
    return (run.name, run.status, run.conclusion?.isEmpty == false ? run.conclusion : nil)
  }

  static func pullRequest(project: String, root: URL) throws -> String {
    let output = try run(["pr", "view", "--json", "number,title,state,headRefName"], root: root)
    guard let data = output.data(using: .utf8), let pr = try? JSONDecoder().decode(PullRequest.self, from: data) else {
      return "\(project) PR\n- unavailable"
    }
    return "\(project) PR\n- #\(pr.number) \(pr.title)\n- state: \(pr.state)\n- branch: \(pr.headRefName)"
  }

  private static func run(_ arguments: [String], root: URL) throws -> String {
    let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    else { throw GitWorkflowError.authenticationRequired }
    do { return try ProjectCommandPolicy.run(executable, arguments, at: root) }
    catch {
      let detail = error.localizedDescription.lowercased()
      if detail.contains("auth") || detail.contains("login") { throw GitWorkflowError.authenticationRequired }
      if detail.contains("permission") || detail.contains("403") { throw GitWorkflowError.permissionDenied }
      throw GitWorkflowError.remoteUnavailable
    }
  }
}
