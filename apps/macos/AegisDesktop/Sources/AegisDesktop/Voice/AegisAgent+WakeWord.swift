import AVFoundation
import AppKit
import Foundation

extension AegisAgent {
  func startWakeListening() {
    guard voiceInputEnabled else { return }
    guard !listening, !busy else { return }
    transcript = ""
    heardText = ""
    listening = true
    commandActive = false
    commandListening = false
    wakeTranscript = ""
    wakeCheckInFlight = false
    lastCommandText = ""
    recordActivity("호출어 대기")
    speech.start(onAudio: { [weak self] in
      guard let self else { return }
      self.checkWakeWord(self.heardText, recording: self.speech.wakeSnapshotURL())
    }, onUpdate: { [weak self] text, isFinal in
      guard let self else { return }
      self.heardText = text
      self.handleSpeech(text)
      if isFinal { self.handleFinalRecognition() }
    }, onError: { [weak self] message in
      self?.listening = false
      self?.reply = message
    })
  }

  func startCommandListening() {
    speech.stop()
    transcript = ""
    heardText = ""
    listening = true
    commandActive = true
    commandListening = true
    lastCommandText = ""
    recordActivity("호출어 감지 · 명령 입력 대기")
    speech.start(onAudio: {}, onUpdate: { [weak self] text, isFinal in
      guard let self else { return }
      self.heardText = text
      self.handleSpeech(text)
      if isFinal { self.handleFinalRecognition() }
    }, onError: { [weak self] message in
      self?.listening = false
      self?.reply = message
    })
  }

  func collectWakeSample(label: String) {
    guard voiceInputEnabled else {
      sampleStatus = "음성 입력이 꺼져 있습니다."
      return
    }
    guard !busy else { return }
    speech.stop()
    listening = false
    sampleStatus = label == "wake" ? "2.5초 동안 ‘에이제스’라고 말하세요." : "2.5초 동안 일반 문장을 말하세요."
    sampleRecorder.capture(label: label) { [weak self] url in
      DispatchQueue.main.async {
        guard let self else { return }
        guard let url else { self.sampleStatus = "녹음에 실패했습니다."; return }
        LearningStore.addWakeSample(path: url.path, label: label)
        self.sampleStatus = label == "wake" ? "호출어 샘플을 저장했습니다." : "일반 음성 샘플을 저장했습니다."
      }
    }
  }

  func reportFalseWake() {
    guard let wakeCandidateURL else { return }
    LearningStore.addWakeSample(path: wakeCandidateURL.path, label: "non_wake")
    self.wakeCandidateURL = nil
    hasWakeCandidate = false
    sampleStatus = "오감지 샘플을 일반 음성으로 저장했습니다."
    speech.stop()
    listening = false
    commandActive = false
    commandListening = false
    recordActivity("오감지 샘플 저장")
    startWakeListening()
  }

  func saveWakeCandidate(from source: URL?) -> URL? {
    guard let source else { return nil }
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "Aegis/wake-false-candidates")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let destination = folder.appending(path: "\(UUID().uuidString).caf")
    do { try FileManager.default.copyItem(at: source, to: destination); return destination } catch { return nil }
  }
}
