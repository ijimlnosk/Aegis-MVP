import Foundation

enum GitCommitPolicy {
  static let maximumFiles = 50
  static let maximumFileBytes: UInt64 = 10 * 1_024 * 1_024
  static let sensitiveNames = [".env", ".pem", ".key", "credential", "secret", "private_key", "id_rsa"]

  static func sensitive(_ path: String) -> Bool {
    let lower = path.lowercased(), name = URL(fileURLWithPath: lower).lastPathComponent
    return name == ".env" || name.hasPrefix(".env.") || sensitiveNames.contains(where: lower.contains)
  }

  static func largeOrBinary(_ path: String, root: URL) -> Bool {
    let url = root.appending(path: path)
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
    let binary = ["zip", "tar", "gz", "7z", "mov", "mp4", "sqlite", "db", "dmp"]
      .contains(url.pathExtension.lowercased())
    return size > maximumFileBytes || binary
  }

  static func validate(_ plan: GitCommitPlan) throws {
    let files = plan.groups.flatMap(\.files)
    guard !plan.groups.isEmpty else { throw GitWorkflowError.invalidPlan }
    guard files.count == Set(files).count else { throw GitWorkflowError.duplicateFile }
    let snapshot = Set(plan.baseSnapshot.changedFiles)
    guard files.allSatisfy(snapshot.contains) else { throw GitWorkflowError.invalidPlan }
    guard plan.groups.allSatisfy({ $0.files.count <= maximumFiles }) else { throw GitWorkflowError.invalidPlan }
    guard !files.contains(where: sensitive) else { throw GitWorkflowError.sensitiveFile }
  }

  static func validMessage(_ message: String) -> Bool {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    return (3...120).contains(trimmed.count) && !trimmed.contains("\n")
  }
}

enum GitWorkflowError: LocalizedError {
  case clean, invalidPlan, duplicateFile, sensitiveFile, existingStaged, stalePlan
  case validationFailed(ProjectValidationReport), stagingMismatch, commitFailed(String)
  case protectedBranch, remoteAhead, diverged
  case noUpstream, authenticationRequired, remoteUnavailable, permissionDenied, noAttributedFiles
  case partialCommit(String)
  case noActiveCommitPlan, expiredCommitPlan, cancelledCommitPlan, alreadyCommitted

  var errorDescription: String? {
    switch self {
    case .clean: "커밋할 변경사항이 없습니다."
    case .invalidPlan, .duplicateFile: "커밋 계획의 파일 구성이 올바르지 않습니다."
    case .sensitiveFile: "민감한 파일이 포함되어 자동 커밋을 중단했습니다."
    case .existingStaged: "이미 stage된 변경사항이 있어 자동 커밋을 중단했습니다."
    case .stalePlan: "커밋 계획 이후 변경사항이 달라졌습니다. 새 계획을 만들까요?"
    case .validationFailed(let report): GitValidationFormatter.format(report, failedCommit: true)
    case .stagingMismatch: "stage된 파일이 승인된 커밋 그룹과 달라 커밋을 중단했습니다."
    case .commitFailed(let detail): "커밋 생성에 실패했습니다: \(detail)"
    case .protectedBranch: "보호된 브랜치에는 직접 push할 수 없습니다. 기능 브랜치와 PR을 사용해 주세요."
    case .remoteAhead: "원격 브랜치가 로컬보다 앞서 있어 push하지 않았습니다."
    case .diverged: "로컬과 원격 브랜치가 갈라져 있어 push하지 않았습니다."
    case .noUpstream: "현재 브랜치의 upstream을 확인하지 못했습니다."
    case .authenticationRequired: "Git 원격 저장소 인증이 필요합니다."
    case .remoteUnavailable: "Git 원격 저장소에 연결할 수 없습니다."
    case .permissionDenied: "Git 원격 저장소에 push할 권한이 없습니다."
    case .noAttributedFiles: "방금 Aegis 작업에 귀속된 파일을 확정할 수 없습니다."
    case .partialCommit(let detail): detail
    case .noActiveCommitPlan: "진행할 커밋 계획이 없습니다."
    case .expiredCommitPlan: "커밋 계획이 만료되었습니다. 새 계획을 만들어 주세요."
    case .cancelledCommitPlan: "취소된 커밋 계획은 다시 실행할 수 없습니다."
    case .alreadyCommitted: "이 커밋 계획은 이미 처리되었습니다."
    }
  }
}
