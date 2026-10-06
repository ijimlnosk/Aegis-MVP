import Foundation

extension AegisAgent {
  func interpretKakaoApproval(_ text: String) {
    guard let message = pendingKakaoMessage else { return }
    let compact = text.replacingOccurrences(of: " ", with: "")
    if ["취소", "그만", "하지마", "보내지마"].contains(where: compact.contains) { cancelKakaoMessage(); return }
    if ["전송", "보내", "전달", "응", "좋아", "그래"].contains(where: compact.contains) { confirmKakaoMessage(); return }
    busy = true
    Task {
      let decision = try? await Ollama.kakaoDecision(text, message: message)
      busy = false
      if decision == "send" { confirmKakaoMessage(); return }
      if decision == "cancel" { cancelKakaoMessage(); return }
      reply = "‘\(text)’가 전송인지 취소인지 확실하지 않습니다. 자연스럽게 다시 말씀해 주세요."
      startWakeListening()
    }
  }

  func confirmKakaoMessage() {
    guard let message = pendingKakaoMessage else { return }
    if let id = pendingKakaoApprovalID { chat.resolveApproval(id: id, state: .approved) }
    pendingKakaoApprovalID = nil
    chat.append(.system, "카카오톡 전송을 승인했습니다. 결과를 기다리는 중입니다.")
    pendingKakaoMessage = nil
    busy = true
    Task {
      let result = await KakaoTalkAutomation.send(message)
      busy = false
      let request = "카카오톡 \(message.recipient)에게 \(message.body)"
      LearningMemory.record(request: request, action: "kakao_message", result: result)
      memoryStore.recordAction(request: request, action: "kakao_message", target: message.recipient,
        result: result, succeeded: resultSucceeded(result))
      speak(result)
    }
  }

  func sendKakao(_ message: KakaoMessage, request: String) {
    Task {
      let result = await KakaoTalkAutomation.send(message)
      LearningMemory.record(request: request, action: "kakao_message", result: result)
      memoryStore.recordAction(request: request, action: "kakao_message", target: message.recipient,
        result: result, succeeded: resultSucceeded(result))
      speak(result)
      completeCurrentStep(succeeded: resultSucceeded(result))
    }
  }

  func cancelKakaoMessage() {
    if let id = pendingKakaoApprovalID { chat.resolveApproval(id: id, state: .rejected) }
    pendingKakaoApprovalID = nil
    pendingKakaoMessage = nil
    chat.append(.system, "카카오톡 전송을 거절했습니다. 메시지를 보내지 않았습니다.")
  }
}
