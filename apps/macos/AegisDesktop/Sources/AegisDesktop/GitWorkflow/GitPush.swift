import Foundation

struct GitPushProposal: Codable, Equatable {
  let project: String; let branch: String; let remote: String
  let upstream: String; let commitsAhead: Int; let commitsBehind: Int
  var refspec: String { "\(branch):\(branch)" }
}

enum GitPushPolicy {
  static let protectedBranches = Set(["main", "master", "production", "release"])

  static func proposal(project: String, root: URL) throws -> GitPushProposal {
    let branch = try ProjectInspector.branch(at: root)
    guard !protectedBranches.contains(branch.lowercased()) else { throw GitWorkflowError.protectedBranch }
    let proposal = try status(project: project, root: root)
    if proposal.commitsBehind > 0, proposal.commitsAhead > 0 { throw GitWorkflowError.diverged }
    if proposal.commitsBehind > 0 { throw GitWorkflowError.remoteAhead }
    return proposal
  }

  static func status(project: String, root: URL) throws -> GitPushProposal {
    let branch = try ProjectInspector.branch(at: root)
    let upstream: String
    do { upstream = try ProjectCommandPolicy.run("/usr/bin/git", ["rev-parse", "--abbrev-ref", "@{upstream}"], at: root) }
    catch { throw GitWorkflowError.noUpstream }
    let parts = upstream.split(separator: "/", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { throw GitWorkflowError.noUpstream }
    let counts = try ProjectCommandPolicy.run("/usr/bin/git",
      ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], at: root)
      .split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
    guard counts.count == 2 else { throw GitWorkflowError.remoteUnavailable }
    return GitPushProposal(project: project, branch: branch, remote: parts[0], upstream: upstream,
                           commitsAhead: counts[0], commitsBehind: counts[1])
  }
}

enum GitPushExecutor {
  static func push(_ proposal: GitPushProposal, root: URL) throws -> String {
    let current = try GitPushPolicy.proposal(project: proposal.project, root: root)
    guard current == proposal else { throw GitWorkflowError.stalePlan }
    do {
      _ = try ProjectCommandPolicy.run("/usr/bin/git", ["push", proposal.remote, proposal.refspec], at: root)
    } catch {
      let detail = error.localizedDescription.lowercased()
      if detail.contains("authentication") || detail.contains("could not read username") { throw GitWorkflowError.authenticationRequired }
      if detail.contains("permission denied") || detail.contains("403") { throw GitWorkflowError.permissionDenied }
      throw GitWorkflowError.remoteUnavailable
    }
    return "\(proposal.project) \(proposal.branch) 브랜치를 \(proposal.upstream)으로 push했습니다."
  }
}
