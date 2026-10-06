import Foundation

enum PlannerDomain: String, CaseIterable, Codable {
  case project, coding, git, server, mac, browser, screen, ui, message

  var actions: [AgentAction] {
    switch self {
    case .project:
      [.openProject, .getRememberedProjectStatus, .findProjectPath, .getProjectGitStatus, .getProjectBranch,
       .getProjectDiffSummary, .getProjectRecentCommits, .getProjectChangedFiles, .getProjectPackageScripts,
       .getProjectHealth, .assessProjectDeploymentReadiness, .runProjectTypecheck, .runProjectTests,
       .runProjectLint, .runProjectBuild, .startDevelopmentSession, .endDevelopmentSession,
       .getDevelopmentRecap, .getTodayDevelopmentSummary]
    case .coding:
      [.getCodingAgentRecentDiagnostics, .analyzeProjectWithCodingAgent, .proposeCodingTask, .executeCodingTask,
       .reviewCodingTaskResult, .verifyCodingTask, .rollbackCodingTask, .discoverDevelopmentTask,
       .rankDevelopmentCandidates, .proposeDevelopmentTask, .executeDevelopmentTask, .verifyDevelopmentTask,
       .repairDevelopmentTask, .getAutonomousDevelopmentStatus]
    case .git:
      [.inspectGitDiff, .proposeCommitPlan, .createCommit, .getRemoteStatus, .proposePush, .pushCurrentBranch,
       .getCIStatus, .getPullRequestStatus, .getGitWorkflowStatus]
    case .server:
      [.getServerStatus, .getDockerContainers, .getDockerLogs, .getServerProjectStatus,
       .startDockerContainer, .stopDockerContainer, .restartDockerContainer]
    case .mac:
      [.openApplication, .closeApplication, .getActiveApplication, .getSystemStatus,
       .listRunningApplications, .getClipboard, .setClipboard]
    case .browser: [.browserSearch]
    case .screen:
      [.captureScreen, .inspectScreen, .inspectActiveWindow, .inspectScreenWithProjectContext,
       .getScreenAwarenessStatus, .listVisibleWindows, .inspectWindow]
    case .ui:
      [.getUIControlStatus, .getVSCodeQuickOpenStatus, .activateApplication, .focusWindow, .closeWindow,
       .listUIElements, .inspectUIElement, .pressUIElement, .focusUIElement, .setUIText, .appendUIText,
       .pressKeyboardShortcut, .scrollUI, .selectMenuItem]
    case .message: [.kakaoMessage]
    }
  }

  /// Deliberately broad: a false match only costs prompt size, a miss can hide the right action.
  var keywords: [String] {
    switch self {
    case .project:
      ["프로젝트", "project", "상태", "status", "브랜치", "branch", "커밋", "commit", "변경", "diff", "테스트",
       "test", "lint", "린트", "빌드", "build", "typecheck", "타입", "배포", "deploy", "검증", "개발", "작업",
       "스크립트", "script", "열어", "시작", "git", "깃"]
    case .coding:
      ["코드", "코딩", "code", "수정", "고쳐", "고치", "리뷰", "review", "분석", "개선", "버그", "bug", "리팩",
       "codex", "구현", "기능", "롤백", "되돌", "에러", "오류", "경고"]
    case .git:
      ["커밋", "commit", "push", "푸시", "푸쉬", "pr", "풀리퀘", "pull request", "ci", "원격", "remote",
       "git", "깃", "diff", "변경"]
    case .server:
      ["서버", "server", "docker", "도커", "컨테이너", "container", "로그", "log"]
    case .mac:
      ["앱", "app", "실행", "종료", "꺼", "닫", "열어", "켜", "클립보드", "clipboard", "복사", "붙여",
       "시스템", "배터리", "cpu", "메모리", "디스크", "mac", "맥"]
    case .browser:
      ["검색", "search", "찾아", "유튜브", "youtube", "구글", "google", "브라우저", "browser", "사파리", "safari",
       "크롬", "chrome", "파이어폭스", "firefox", "사이트", "웹", "열어"]
    case .screen:
      ["화면", "screen", "창", "window", "윈도우", "스크린"]
    case .ui:
      ["클릭", "click", "눌러", "입력", "타이핑", "스크롤", "scroll", "단축키", "shortcut", "메뉴", "menu",
       "포커스", "focus", "quick open", "팔레트", "palette", "버튼", "button", "탭", "선택", "창"]
    case .message:
      ["카톡", "카카오", "kakao", "메시지", "message", "보내"]
    }
  }
}

struct PlannerActionScope: Equatable {
  let domains: [PlannerDomain]

  static let full = PlannerActionScope(domains: PlannerDomain.allCases)

  /// Falls back to every domain when nothing matches, which is the pre-scoping behavior.
  static func select(for request: String, mentionsProject: Bool) -> Self {
    let text = request.lowercased()
    let matched = PlannerDomain.allCases.filter { domain in
      (domain == .project && mentionsProject) || domain.keywords.contains(where: text.contains)
    }
    return matched.isEmpty ? .full : Self(domains: matched)
  }

  var isFull: Bool { Set(domains) == Set(PlannerDomain.allCases) }

  /// Actions outside every domain (status diagnostics, answer) stay available to all scopes.
  var actions: [AgentAction] {
    let scoped = Set(PlannerDomain.allCases.flatMap(\.actions))
    let allowed = Set(domains.flatMap(\.actions))
    return AgentAction.plannable.filter { allowed.contains($0) || !scoped.contains($0) }
  }
}
