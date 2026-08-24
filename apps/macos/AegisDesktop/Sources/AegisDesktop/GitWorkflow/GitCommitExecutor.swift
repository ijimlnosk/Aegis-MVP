import Foundation

struct GitCommitExecutionResult {
  let commits: [GitCreatedCommit]
  let failedGroup: GitCommitGroup?
  let failureReason: String?

  var succeeded: Bool { failedGroup == nil && !commits.isEmpty }
}

enum GitCommitExecutor {
  static func execute(_ plan: GitCommitPlan, root: URL,
                      validate: () -> ProjectValidationReport) throws -> GitCommitExecutionResult {
    try GitCommitPolicy.validate(plan)
    guard plan.baseSnapshot.stagedChanges.isEmpty else { throw GitWorkflowError.existingStaged }
    let current = try CodingGitInspector.snapshot(at: root)
    guard current.branch == plan.branch, current.entries == plan.baseSnapshot.entries else { throw GitWorkflowError.stalePlan }
    let validation = validate()
    guard validation.allowsCommit else { throw GitWorkflowError.validationFailed(validation) }
    var commits: [GitCreatedCommit] = []
    for group in plan.groups {
      do { commits.append(try commit(group, snapshot: plan.baseSnapshot, root: root)) }
      catch { return GitCommitExecutionResult(commits: commits, failedGroup: group, failureReason: error.localizedDescription) }
    }
    return GitCommitExecutionResult(commits: commits, failedGroup: nil, failureReason: nil)
  }

  private static func commit(_ group: GitCommitGroup, snapshot: GitWorkingTreeSnapshot,
                             root: URL) throws -> GitCreatedCommit {
    guard GitCommitPolicy.validMessage(group.proposedMessage) else { throw GitWorkflowError.invalidPlan }
    let entries = snapshot.entries.filter { group.files.contains($0.path) }
    let paths = Array(Set(group.files + entries.compactMap(\.originalPath))).sorted()
    _ = try ProjectCommandPolicy.run("/usr/bin/git", ["add", "--"] + paths, at: root)
    let staged = try nulPaths(["diff", "--cached", "--name-only", "-z"], root: root)
    guard Set(staged) == Set(group.files) else { throw GitWorkflowError.stagingMismatch }
    do { _ = try ProjectCommandPolicy.run("/usr/bin/git", ["commit", "-m", group.proposedMessage, "--"] + paths, at: root) }
    catch { throw GitWorkflowError.commitFailed(error.localizedDescription) }
    let sha = try ProjectCommandPolicy.run("/usr/bin/git", ["rev-parse", "--short", "HEAD"], at: root)
    let message = try ProjectCommandPolicy.run("/usr/bin/git", ["log", "-1", "--pretty=%s"], at: root)
    let committed = try nulPaths(["diff-tree", "--no-commit-id", "--name-only", "-r", "-z", "HEAD"], root: root)
    guard Set(committed) == Set(group.files), message == group.proposedMessage else { throw GitWorkflowError.commitFailed("커밋 검증 불일치") }
    return GitCreatedCommit(sha: sha, message: message, files: committed.sorted())
  }

  private static func nulPaths(_ arguments: [String], root: URL) throws -> [String] {
    let text = try ProjectCommandPolicy.run("/usr/bin/git", arguments, at: root)
    return text.split(separator: "\0").map(String.init)
  }
}
