import Foundation

enum Ollama {
  private static var transport: OllamaTransport { OllamaTransport() }

  static func endpoint() -> URL? { ScreenAnalysisConfiguration.normalEndpoint()?.chatURL }

  static func endpoint(environment: [String: String]) -> URL? {
    ScreenAnalysisConfiguration.normalEndpoint(environment: environment)?.chatURL
  }

  static func model() -> String { ScreenAnalysisConfiguration.normalModel() }
  static func model(environment: [String: String]) -> String {
    ScreenAnalysisConfiguration.normalModel(environment: environment)
  }

  static func structured(system: String, content: String, schema: [String: Any]) async throws -> AgentPlan {
    let body: [String: Any] = [
      "model": model(), "stream": false, "keep_alive": "30m",
      "think": false, "options": ["num_ctx": 4096, "num_predict": 320, "temperature": 0], "format": schema,
      "messages": [["role": "system", "content": system], ["role": "user", "content": content]],
    ]
    let data = try await transport.chat(body: body)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let message = json["message"] as? [String: Any],
          let raw = message["content"] as? String else { throw OllamaBackendError.malformedResponse }
    return plan(from: raw)
  }

  private static func plan(from raw: String) -> AgentPlan {
    let cleaned = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
    let start = cleaned.firstIndex(of: "{") ?? cleaned.startIndex
    let json = cleaned[start...]
    if let end = json.lastIndex(of: "}"),
       let data = String(json[...end]).data(using: .utf8),
       let plan = try? JSONDecoder().decode(AgentPlan.self, from: data),
       plan.steps.allSatisfy({ $0.action != .unknown }) {
      return plan
    }
    return AgentPlan(step: AgentStep(action: .unknown))
  }

  static func kakaoDecision(_ text: String, message: KakaoMessage) async throws -> String {
    let body: [String: Any] = [
      "model": model(), "stream": false, "keep_alive": "30m",
      "options": ["num_ctx": 2048, "num_predict": 64, "temperature": 0],
      "format": [
        "type": "object",
        "properties": ["decision": ["type": "string", "enum": ["send", "cancel", "unknown"]]],
        "required": ["decision"],
      ],
      "messages": [
        ["role": "system", "content": "당신은 카카오톡 전송 승인 의도 분류기다. 사용자의 발화가 현재 메시지를 보내라는 뜻이면 send, 보내지 말라는 뜻이면 cancel, 불명확하면 unknown만 JSON으로 답한다."],
        ["role": "user", "content": "대기 중인 전송: \(message.recipient)에게 ‘\(message.body)’. 사용자의 다음 발화: ‘\(text)’"],
      ],
    ]
    let data = try await transport.chat(body: body)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let message = json["message"] as? [String: Any],
          let content = message["content"] as? String,
          let jsonData = content.data(using: .utf8),
          let decision = try JSONSerialization.jsonObject(with: jsonData) as? [String: String],
          let value = decision["decision"] else { return "unknown" }
    return value
  }

  static func chat(_ text: String) async throws -> String {
    let body: [String: Any] = [
      "model": model(), "stream": false, "keep_alive": "30m",
      "options": ["num_ctx": 4096, "num_predict": 256, "temperature": 0.3],
      "messages": [["role": "system", "content": "당신은 사용자의 Mac을 돕는 Aegis다. 반드시 자연스러운 한국어로만 답한다. 최종 답변은 간결하고 실행 가능한 형태로 말한다."], ["role": "user", "content": text]],
    ]
    let data = try await transport.chat(body: body)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let message = json?["message"] as? [String: Any]
    let answer = message?["content"] as? String ?? "응답을 생성하지 못했습니다."
    return answer.components(separatedBy: "</think>").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? answer
  }
}
