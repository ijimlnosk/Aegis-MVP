import Foundation

// Sub-categorizes an ALREADY-confirmed command failure for display purposes only.
// This never decides success/failure itself (DesktopBridgeSession does that via the
// reliable "오류: " prefix check) -- it only picks a stable, bounded code so the
// Remote app can show a real reason instead of a generic string.
enum DesktopFailureClassifier {
  static func code(for messages: [String]) -> String {
    let text = messages.joined(separator: "\n")
    if text.contains("프로젝트") && (text.contains("찾을 수 없") || text.contains("등록되지 않")) { return "projectUnavailable" }
    if text.contains("sol-server") || text.contains("Server Agent") || text.contains("서버 작업") { return "serverAgentUnavailable" }
    if text.contains("Codex") || text.contains("coding_agent") || text.contains("코딩 에이전트") { return "codingAgentUnavailable" }
    if text.contains("검증") || text.contains("typecheck") || text.contains("lint") || text.contains("테스트") { return "validationFailed" }
    if text.contains("계획") || text.contains("planner") || text.contains("이해하지 못") { return "plannerFailed" }
    return "internalError"
  }
}
