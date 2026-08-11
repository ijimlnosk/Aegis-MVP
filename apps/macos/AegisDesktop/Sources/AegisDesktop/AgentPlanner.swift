import Foundation

struct AgentPlan: Codable {
  let action: String
  let recipient: String?
  let body: String?
  let application: String?
  let answer: String?
}

enum AgentPlanner {
  static func plan(for request: String, memories: [AgentTrace]) async throws -> AgentPlan {
    let examples = memories.map { "요청: \($0.request) | 행동: \($0.action) | 결과: \($0.result)" }.joined(separator: "\n")
    let system = """
    당신은 Aegis의 행동 계획 AI다. 사용자의 자연스러운 한국어 요청을 분석해 JSON만 답한다.
    action은 kakao_message, open_application, close_application, get_active_application, answer 중 하나다.
    카카오톡 메시지는 recipient와 body를 채운다. 표현 방식에 관계없이 전송 의도를 이해한다.
    사용자가 카카오톡·채팅방·상대방에게 메시지를 보내거나 전송해 달라고 하면 설명하지 말고 반드시 kakao_message를 선택한다.
    앱 실행은 application을 채운다. 그 외에는 answer에 자연스러운 한국어 답을 넣는다.
    앱을 닫거나 종료해 달라는 요청은 close_application을 선택하고 application을 채운다.
    현재 어떤 앱을 쓰는지, 활성 앱이 무엇인지 묻는 요청은 get_active_application을 선택한다.
    실행 방법을 설명하지 말고 사용자의 의도를 우선한다. 모르는 값은 빈 문자열로 둔다.
    """
    let schema: [String: Any] = [
      "type": "object",
      "properties": [
        "action": ["type": "string", "enum": ["kakao_message", "open_application", "close_application", "get_active_application", "answer"]],
        "recipient": ["type": "string"], "body": ["type": "string"],
        "application": ["type": "string"], "answer": ["type": "string"],
      ],
      "required": ["action"],
    ]
    let content = "최근 실행 기록:\n\(examples.isEmpty ? "없음" : examples)\n\n현재 요청: \(request)"
    let first = try await Ollama.structured(system: system, content: content, schema: schema)
    guard !needsRetry(first) else {
      return try await Ollama.structured(
        system: system + "\n첫 판단이 불완전했다. 이번에는 누락 없이 도구 실행 계획만 JSON으로 다시 답한다.",
        content: content, schema: schema)
    }
    return first
  }

  private static func needsRetry(_ plan: AgentPlan) -> Bool {
    if plan.action == "kakao_message" { return plan.recipient?.isEmpty != false || plan.body?.isEmpty != false }
    if ["open_application", "close_application"].contains(plan.action) { return plan.application?.isEmpty != false }
    if plan.action == "get_active_application" { return false }
    return plan.action != "answer" || plan.answer?.isEmpty != false
  }
}
