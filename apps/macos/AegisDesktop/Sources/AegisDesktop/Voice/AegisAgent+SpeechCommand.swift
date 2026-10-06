import AVFoundation
import AppKit
import Foundation

extension AegisAgent {
  func handleSpeech(_ text: String) {
    let lowered = normalized(text)
    if pendingKakaoMessage != nil {
      waitForKakaoApproval(text)
      return
    }
    guard commandActive else { return checkWakeWord(text, recording: speech.wakeSnapshotURL()) }
    transcript = text.hasPrefix(wakeTranscript)
      ? String(text.dropFirst(wakeTranscript.count)).trimmingCharacters(in: .whitespacesAndNewlines)
      : text
    let currentCommand = normalized(transcript)
    guard currentCommand != lastCommandText else { return }
    lastCommandText = currentCommand
    if finishWords.contains(where: lowered.contains) {
      submitSpeech()
      return
    }
    resetSilenceTimer()
  }

  func checkWakeWord(_ text: String, recording: URL?) {
    guard !wakeCheckInFlight, Date.now.timeIntervalSince(lastWakeCheck) > 0.7 else { return }
    wakeCheckInFlight = true
    lastWakeCheck = .now
    Task {
      let score = await WakeWordVerifier.score(for: recording)
      wakeCheckInFlight = false
      let detected = score.map { $0 >= 0.60 } ?? false
      LearningStore.recordWakeCheck(score: score, detected: detected)
      guard !commandActive, detected else { return }
      wakeCandidateURL = saveWakeCandidate(from: recording)
      hasWakeCandidate = wakeCandidateURL != nil
      NSSound.beep()
      startCommandListening()
    }
  }

  private func stopListeningForConfirmation() {
    silenceTimer?.invalidate()
    speech.stop()
    listening = false
    commandActive = false
    commandListening = false
    transcript = ""
    lastCommandText = ""
    lastKakaoApprovalText = ""
  }

  private func waitForKakaoApproval(_ text: String) {
    guard text != lastKakaoApprovalText else { return }
    lastKakaoApprovalText = text
    silenceTimer?.invalidate()
    silenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.finishKakaoApproval() }
    }
  }

  private func finishKakaoApproval() {
    let text = heardText
    guard !text.isEmpty else { return }
    stopListeningForConfirmation()
    interpretKakaoApproval(text)
  }

  private func normalized(_ text: String) -> String {
    text.lowercased().components(separatedBy: .whitespacesAndNewlines).joined()
  }

  func handleFinalRecognition() {
    guard listening, !commandActive else { return }
    if pendingKakaoMessage != nil { return }
    listening = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.startWakeListening() }
  }

  private func resetSilenceTimer() {
    silenceTimer?.invalidate()
    silenceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.submitSpeech() }
    }
  }

  private func submitSpeech() {
    let text = finishWords.reduce(transcript) { value, word in
      value.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
    }.trimmingCharacters(in: .whitespacesAndNewlines)
    silenceTimer?.invalidate(); speech.stop(); listening = false; commandActive = false; commandListening = false; transcript = ""; lastCommandText = ""
    guard !text.isEmpty else { return startWakeListening() }
    let recording = speech.lastRecordingURL
    busy = true
    recordActivity("등록 화자 확인")
    Task {
      let score = await SpeakerVerifier.score(for: recording)
      busy = false
      guard let score, score >= 0.72 else {
        reply = score == nil ? "화자 확인을 할 수 없어 음성 명령을 보내지 않았습니다." : "등록한 목소리로 확인되지 않아 명령을 무시했습니다."
        startWakeListening()
        return
      }
      recordActivity("음성 요청 분석")
      sendFromDesktop(text)
    }
  }
}
