import Foundation

final class DevelopmentSessionCoordinator {
  private let sessions: DevelopmentSessionRepository
  private let memory: MemoryRepository
  init(sessions: DevelopmentSessionRepository = DevelopmentSessionRepository(), memory: MemoryRepository) {
    self.sessions = sessions; self.memory = memory; try? sessions.bootstrap()
  }

  func start(project: String) throws -> String {
    if try sessions.sessions(project: project).first(where: { $0.endedAt == nil }) != nil {
      return "\(project) 개발 세션이 이미 진행 중입니다."
    }
    let url = try ProjectCommandPolicy.projectURL(project, repository: memory)
    let snapshot = try ProjectInspector.snapshot(at: url)
    try sessions.save(DevelopmentSession(project: project, startingGitState: snapshot))
    return "\(project) 개발 세션을 시작했습니다. Branch: \(snapshot.branch), 변경 파일: \(snapshot.changedFiles.count)개"
  }

  func end(project: String) throws -> String {
    guard var session = try sessions.sessions(project: project).first(where: { $0.endedAt == nil }) else {
      return "진행 중인 \(project) 개발 세션이 없습니다."
    }
    let url = try ProjectCommandPolicy.projectURL(project, repository: memory)
    let ending = try ProjectInspector.snapshot(at: url)
    session.endedAt = .now; session.endingGitState = ending
    let added = Set(ending.changedFiles).subtracting(session.startingGitState.changedFiles)
    session.summary = "\(session.startingBranch)에서 시작해 변경 파일 \(ending.changedFiles.count)개로 마쳤습니다. 세션 중 새 변경: \(added.count)개."
    try sessions.save(session)
    return "\(project) 작업을 마무리했습니다. \(session.summary ?? "")"
  }

  func recap(project: String) throws -> String {
    DevelopmentRecapFormatter.format(try recapResult(project: project))
  }

  func recapResult(project: String) throws -> DevelopmentRecapResult {
    let url = try ProjectCommandPolicy.projectURL(project, repository: memory)
    let snapshot = try ProjectInspector.snapshot(at: url)
    var warnings: [String] = snapshot.clean ? [] : ["현재 미커밋 변경 \(snapshot.changedFiles.count)건이 있습니다."]
    let recentCommits: String?
    do { recentCommits = try ProjectInspector.recentCommits(at: url, count: 5) }
    catch { recentCommits = nil; warnings.append("최근 커밋을 확인할 수 없습니다.") }
    let session: DevelopmentSession?
    do { session = try sessions.sessions(project: project).first }
    catch { session = nil; warnings.append("DevelopmentSession 정보를 확인할 수 없습니다.") }
    let activity = session?.summary ?? session.map { "\($0.startedAt.formatted())에 시작한 세션이 진행 중입니다." }
    return .init(project: project, executionStatus: .succeeded, branch: snapshot.branch,
      projectState: snapshot.clean ? .clean : .dirty, changedFiles: snapshot.changedFiles,
      recentCommits: recentCommits, sessionSummary: activity,
      recentAutonomousTask: recentAutonomousHistory(project: project), warnings: warnings)
  }

  private func recentAutonomousHistory(project: String) -> AutonomousDevelopmentHistory? {
    let decoder = JSONDecoder()
    return (try? memory.records(type: .actionHistory))?.compactMap { record in
      guard record.key.hasPrefix("autonomous:"), let data = record.value.data(using: .utf8),
        let value = try? decoder.decode(AutonomousDevelopmentHistory.self, from: data),
        value.projectId == project.lowercased() else { return nil }
      return value
    }.sorted { $0.timestamp > $1.timestamp }.first
  }

  func record(project: String, action: String) throws {
    guard var session = try sessions.sessions(project: project).first(where: { $0.endedAt == nil }) else { return }
    session.actions.append(action); try sessions.save(session)
  }

  func today() throws -> String {
    let start = Calendar.current.startOfDay(for: .now)
    let values = try sessions.sessions(since: start)
    guard !values.isEmpty else { return "오늘 기록된 개발 세션이 없습니다." }
    return Dictionary(grouping: values, by: \.project).sorted { $0.key < $1.key }.map { project, items in
      "\(project): \(items.count)개 세션 · " + items.map { $0.summary ?? "진행 중" }.joined(separator: " / ")
    }.joined(separator: "\n")
  }
}
