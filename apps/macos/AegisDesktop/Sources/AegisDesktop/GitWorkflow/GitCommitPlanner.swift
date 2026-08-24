import Foundation

enum GitCommitPlanner {
  static func create(project: String, root: URL, snapshot: GitWorkingTreeSnapshot,
                     request: String, allowedFiles: Set<String>? = nil) throws -> GitCommitPlan {
    guard snapshot.isDirty else { throw GitWorkflowError.clean }
    var buckets: [String: [String]] = [:], unassigned: [String] = [], warnings: [String] = []
    if snapshot.entries.contains(where: { $0.indexStatus != " " && $0.indexStatus != "?" }) {
      warnings.append("이미 stage된 변경사항이 있습니다.")
    }
    for path in snapshot.changedFiles where (allowedFiles?.contains(path) ?? true)
      && !excluded(path, request: request) {
      if generatedBuildArtifact(path) { unassigned.append(path); warnings.append("빌드 산출물은 자동 커밋에서 제외: \(path)"); continue }
      if GitCommitPolicy.sensitive(path) { unassigned.append(path); warnings.append("민감 파일 검토 필요: \(path)"); continue }
      if GitCommitPolicy.largeOrBinary(path, root: root) { unassigned.append(path); warnings.append("대용량/바이너리 검토 필요: \(path)"); continue }
      guard let key = semanticKey(path) else { unassigned.append(path); continue }
      buckets[key, default: []].append(path)
    }
    let groups = buckets.sorted { $0.key < $1.key }.map { key, files in
      let descriptor = description(key)
      return GitCommitGroup(title: descriptor.title, rationale: descriptor.rationale, files: files,
        proposedMessage: descriptor.message, confidence: descriptor.confidence)
    }
    let plan = GitCommitPlan(projectId: project, branch: snapshot.branch, baseSnapshot: snapshot,
      groups: groups, unassignedFiles: unassigned, warnings: Array(Set(warnings)).sorted())
    try GitCommitPolicy.validate(plan); return plan
  }

  private static func semanticKey(_ path: String) -> String? {
    let lower = path.lowercased()
    if lower.contains("meallog") { return "meal-log" }
    if lower.contains("workoutsession") { return "workout-session" }
    if lower.hasPrefix("android/") { return "android" }
    if lower.hasPrefix("docs/") || lower.hasSuffix(".md") { return "docs" }
    if lower.contains("sample/") || lower.hasSuffix(".ds_store") { return nil }
    let parts = path.split(separator: "/")
    // Bucket by containing directory (not a fixed 2-segment prefix) so a deep monorepo tree
    // splits into one commit group per feature folder instead of one giant group per top-level app.
    return parts.count >= 2 ? parts.dropLast().joined(separator: "/") : nil
  }

  private static func generatedBuildArtifact(_ path: String) -> Bool {
    let lower = path.lowercased()
    return lower.hasPrefix(".build/") || lower.contains("/.build/")
      || lower.hasSuffix("/.lock") || lower == ".lock"
  }

  private static func description(_ key: String) -> (title: String, rationale: String, message: String, confidence: Double) {
    switch key {
    case "meal-log": ("식단 요청 로그 정리", "식단 기록 로깅 구현과 테스트가 함께 변경되었습니다.", "fix: 식단 요청 로그에서 민감정보 제거", 0.95)
    case "workout-session": ("운동 세션 UI 정리", "운동 세션 화면과 스타일 변경입니다.", "refactor: 운동 세션 스테퍼 UI 정리", 0.9)
    case "android": ("Android 빌드 설정", "Android 프로젝트 설정 변경입니다.", "chore: Android 빌드 설정 조정", 0.85)
    case "docs": ("문서 정리", "문서 파일만 포함된 변경입니다.", "docs: 프로젝트 문서 정리", 0.9)
    default: (shortTitle(key), "같은 디렉터리(\(key))의 변경입니다.", "chore: \(shortTitle(key)) 변경 정리", 0.7)
    }
  }

  private static func shortTitle(_ key: String) -> String {
    key.split(separator: "/").suffix(2).joined(separator: "/")
  }

  private static func excluded(_ path: String, request: String) -> Bool {
    let compact = request.lowercased()
    guard ["빼", "제외", "건드리지 마"].contains(where: compact.contains) else { return false }
    return compact.contains(path.lowercased()) || compact.contains(URL(fileURLWithPath: path).lastPathComponent.lowercased())
  }
}
