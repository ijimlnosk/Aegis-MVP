import Foundation

extension AegisAgent {
  func runSlashCommand(_ resolution: SlashCommandResolution, request: String) {
    switch resolution {
    case .message(let text): speak(text)
    case .plan(let actions):
      // A slash command must not be mistaken for an approval reply or interleave a running plan.
      guard pendingMacAction == nil, pendingKakaoMessage == nil, planExecutor == nil else {
        speak("진행 중인 작업이나 승인 대기가 끝난 뒤 다시 입력해 주세요."); return
      }
      execute(AgentPlan(steps: actions.map { AgentStep(action: $0) }), request: request)
    }
  }
}
