import Foundation

struct AgentPlan: Codable {
  let action: String
  let recipient: String?
  let body: String?
  let application: String?
  let browser: String?
  let site: String?
  let query: String?
  let content: String?
  let answer: String?
}

enum AgentPlanner {
  static func plan(for request: String, memories: [AgentTrace]) async throws -> AgentPlan {
    let examples = memories.map { "요청: \($0.request) | 행동: \($0.action) | 결과: \($0.result)" }.joined(separator: "\n")
    let system = """
    당신은 Aegis의 행동 계획 AI다. 사용자의 자연스러운 한국어 요청을 분석해 JSON만 답한다.
    현재 사용할 수 있는 기능은 앱 실행·종료, 활성 앱 확인, 실행 중인 앱 목록, Mac 시스템 상태, 브라우저 검색, 클립보드 읽기·저장, 카카오톡 메시지 전송이다.
    사용자가 Aegis의 기능, 능력, 할 수 있는 일을 물으면 action=answer를 선택하고 현재 기능과 승인 원칙을 answer에 자연스럽게 설명한다.
    action은 kakao_message, open_application, close_application, browser_search, get_active_application, get_system_status, list_running_applications, get_clipboard, set_clipboard, answer 중 하나다.
    카카오톡 메시지는 recipient와 body를 채운다. 표현 방식에 관계없이 전송 의도를 이해한다.
    사용자가 카카오톡·채팅방·상대방에게 메시지를 보내거나 전송해 달라고 하면 설명하지 말고 반드시 kakao_message를 선택한다.
    앱 실행은 application을 채운다. 그 외에는 answer에 자연스러운 한국어 답을 넣는다.
    앱을 닫거나 종료해 달라는 요청은 close_application을 선택하고 application을 채운다.
    브라우저를 열어 웹사이트에서 검색해 달라는 요청은 browser_search를 선택한다.
    browser는 브라우저 앱 이름만, site는 검색할 서비스 이름만, query는 사용자가 찾고 싶은 주제만 넣는다.
    절대로 browser나 site 이름을 query에 복사하지 않는다. 사용자가 말한 주제를 요약하거나 바꾸지 말고 원문 의미를 보존한다.
    사용자가 “유튜브를 검색해줘”, “네이버를 검색해줘”처럼 서비스 이름 자체를 검색해 달라고 하면 일반 웹 검색 의도다. site=Google, query에 서비스 이름을 넣는다.
    사용자가 “유튜브에서 아이유를 검색해줘”처럼 ‘서비스에서/서비스에’ 뒤에 주제를 말하면 해당 서비스 내부 검색 의도다.
    사용자가 “유튜브를 열어줘”처럼 검색이 아니라 열기를 요청하면 site=YouTube, query=""으로 한다.
    예시: “파이어폭스에서 유튜브를 검색해줘” → browser=Firefox, site=Google, query="유튜브".
    예시: “파이어폭스에서 유튜브에 아이유 콘서트 검색해줘” → browser=Firefox, site=YouTube, query="아이유 콘서트".
    예시: “파이어폭스로 맥북 M4 비교 검색해줘” → browser=Firefox, site=Google, query="맥북 M4 비교".
    예시: “OOO을 검색해줘” → browser="", site=Google, query="OOO".
    검색할 주제가 문장에 없고 사이트만 열라는 의도라면 query는 빈 문자열이다. 그 외에 query를 추측해서 채우지 않는다.
    “Firefox에서 YouTube 검색”, “브라우저 켜서 유튜브 검색”처럼 앱 열기와 검색이 함께 있으면 open_application이 아니라 반드시 browser_search를 선택한다.
    현재 어떤 앱을 쓰는지, 활성 앱이 무엇인지 묻는 요청은 get_active_application을 선택한다.
    Mac 상태나 운영체제, 메모리, 가동 시간을 물으면 get_system_status를 선택한다.
    실행 중인 앱 전체를 물으면 list_running_applications를 선택한다.
    클립보드 내용을 읽어 달라면 get_clipboard를 선택한다. 클립보드에 텍스트를 복사하거나 저장해 달라면 set_clipboard를 선택하고 content를 채운다.
    실행 방법을 설명하지 말고 사용자의 의도를 우선한다. 모르는 값은 빈 문자열로 둔다.
    """
    let schema: [String: Any] = [
      "type": "object",
      "properties": [
        "action": ["type": "string", "enum": ["kakao_message", "open_application", "close_application", "browser_search", "get_active_application", "get_system_status", "list_running_applications", "get_clipboard", "set_clipboard", "answer"]],
        "recipient": ["type": "string", "description": "카카오톡 받는 사람 또는 채팅방 이름"],
        "body": ["type": "string", "description": "카카오톡으로 보낼 원문 메시지"],
        "application": ["type": "string", "description": "열거나 닫을 macOS 앱 이름"],
        "browser": ["type": "string", "description": "browser_search에서만 쓸 브라우저 앱 이름. 언급이 없으면 빈 문자열"],
        "site": ["type": "string", "description": "browser_search에서만 쓸 검색 서비스. 유튜브면 YouTube, 일반 웹 검색은 Google"],
        "query": ["type": "string", "description": "browser_search에서 사용자가 실제로 찾으려는 주제만. 앱/사이트 이름을 넣지 말 것"],
        "content": ["type": "string", "description": "set_clipboard에서 저장할 원문 텍스트"],
        "answer": ["type": "string", "description": "도구 실행이 필요 없는 자연스러운 한국어 답"],
      ],
      "required": ["action"],
    ]
    let content = "최근 실행 기록:\n\(examples.isEmpty ? "없음" : examples)\n\n현재 요청: \(request)"
    let first = try await Ollama.structured(system: system, content: content, schema: schema)
    let candidate = needsRetry(first)
      ? try await Ollama.structured(
          system: system + "\n첫 판단이 불완전했다. 이번에는 누락 없이 도구 실행 계획만 JSON으로 다시 답한다.",
          content: content, schema: schema)
      : first
    let reviewed = try await Ollama.structured(
      system: system + "\n당신은 계획 검토자다. 제안된 계획이 사용자의 모든 요청을 수행하는지 검토하고, 부족하면 올바른 JSON 계획으로 교체한다.",
      content: content + "\n\n제안된 계획: \(String(data: try JSONEncoder().encode(candidate), encoding: .utf8) ?? "")",
      schema: schema)
    return bestPlan(first, candidate, reviewed)
  }

  private static func needsRetry(_ plan: AgentPlan) -> Bool {
    if plan.action == "kakao_message" { return plan.recipient?.isEmpty != false || plan.body?.isEmpty != false }
    if ["open_application", "close_application"].contains(plan.action) { return plan.application?.isEmpty != false }
    if plan.action == "browser_search" { return plan.browser?.isEmpty != false || plan.site?.isEmpty != false }
    if plan.action == "get_active_application" { return false }
    if ["get_system_status", "list_running_applications", "get_clipboard"].contains(plan.action) { return false }
    if plan.action == "set_clipboard" { return plan.content?.isEmpty != false }
    return plan.action != "answer" || plan.answer?.isEmpty != false
  }

  private static func bestPlan(_ first: AgentPlan, _ candidate: AgentPlan, _ reviewed: AgentPlan) -> AgentPlan {
    if !needsRetry(reviewed) { return reviewed }
    if !needsRetry(candidate) { return candidate }
    return first
  }
}
