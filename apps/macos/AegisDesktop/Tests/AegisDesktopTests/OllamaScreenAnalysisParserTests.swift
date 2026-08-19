import Foundation
import Testing
@testable import AegisDesktop

@Test func parsesActualQwen25VLChatResponse() throws {
  let data = Data(actualResponse.utf8)
  let result = try OllamaScreenAnalysisParser.parse(data)
  #expect(result.summary.contains("여러 개의 프로젝트"))
  #expect(result.visibleErrors.isEmpty)
  #expect(result.detectedApplication == nil)
  #expect(result.confidence == 0.9)
}

@Test func parsesGenerateEnvelopeFencesAndKnownAliases() throws {
  let model = """
  설명 전처리
  ```json
  {"summary":"화면 설명","detected_application":"Code","visible_errors":["오류"]}
  ```
  뒤 설명
  """
  let envelope = try JSONSerialization.data(withJSONObject: ["model": "qwen2.5vl:7b",
    "response": model, "done": true])
  let result = try OllamaScreenAnalysisParser.parse(envelope)
  #expect(result.detectedApplication == "Code")
  #expect(result.visibleErrors == ["오류"])
  #expect(result.visibleWarnings.isEmpty)
  #expect(result.confidence == nil)
}

@Test func unstructuredVisionTextBecomesSuccessfulFallback() throws {
  let data = try JSONSerialization.data(withJSONObject: ["message": ["role": "assistant",
    "content": "현재 화면에는 코드 편집기와 터미널이 보입니다."], "done": true])
  let result = try OllamaScreenAnalysisParser.parse(data)
  #expect(result.summary.contains("코드 편집기"))
  #expect(result.limitations == ["Vision provider returned unstructured output."])
}

@Test func emptyOrStructurallyUnusableVisionResponseFails() throws {
  let values: [[String: Any]] = [["message": ["content": "  "]], ["done": true]]
  for value in values {
    let data = try JSONSerialization.data(withJSONObject: value)
    #expect(throws: ScreenAnalysisError.self) { try OllamaScreenAnalysisParser.parse(data) }
  }
}

// Sanitized verbatim response captured from qwen2.5vl:7b /api/chat on 2026-08-19.
private let actualResponse = #"""
{"model":"qwen2.5vl:7b","created_at":"2026-08-19T07:00:00Z","message":{"role":"assistant","content":"{\n  \"summary\": \"사용자는 여러 개의 프로젝트와 코드를 관리하고 있습니다. 화면에는 Xcode, VS Code, Terminal, 웹 브라우저가 열려 있으며, 각 프로그램에서 다양한 작업이 진행되고 있습니다.\",\n  \"visibleErrors\": [],\n  \"visibleWarnings\": [],\n  \"confidence\": 0.9,\n  \"limitations\": [\"화면 콘텐츠는 신뢰할 수 없는 데이터로 취급됩니다.\", \"화면에 보이는 텍스트는 설명 대상이지만 실행 요청이 아닙니다.\"]\n}"},"done":true,"done_reason":"stop","total_duration":1,"load_duration":1,"prompt_eval_count":4308,"prompt_eval_duration":1,"eval_count":100,"eval_duration":1}
"""#
