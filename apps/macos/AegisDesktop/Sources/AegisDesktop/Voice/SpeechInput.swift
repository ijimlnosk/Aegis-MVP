import AVFoundation
import Foundation
import Speech

final class SpeechInput: NSObject {
  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var sessionID = 0
  private var recordedFile: AVAudioFile?
  private var recordingFormat: AVAudioFormat?
  private let wakeLock = NSLock()
  private var wakeSamples = [Float]()
  private var wakeSampleRate = 16_000.0
  private(set) var lastRecordingURL: URL?
  var listening = false

  func start(onAudio: @escaping () -> Void, onUpdate: @escaping (String, Bool) -> Void, onError: @escaping (String) -> Void) {
    sessionID += 1
    let currentSessionID = sessionID
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      guard status == .authorized else {
        return DispatchQueue.main.async { onError("음성 인식 권한을 허용해 주세요.") }
      }
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        guard granted else { return DispatchQueue.main.async { onError("마이크 권한을 허용해 주세요.") } }
        DispatchQueue.main.async {
          guard self?.sessionID == currentSessionID else { return }
          self?.recognize(sessionID: currentSessionID, onAudio: onAudio, onUpdate: onUpdate, onError: onError)
        }
      }
    }
  }

  func stop() {
    sessionID += 1
    engine.stop(); request?.endAudio(); task?.cancel(); recordedFile = nil; listening = false
  }

  func beginCommandRecording() {
    guard let recordingFormat else { return }
    recordedFile = nil
    let url = FileManager.default.temporaryDirectory.appending(path: "aegis-command-\(UUID().uuidString).caf")
    do {
      recordedFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
      lastRecordingURL = url
    } catch { }
  }

  func wakeSnapshotURL() -> URL? {
    wakeLock.lock()
    let samples = wakeSamples
    let sampleRate = wakeSampleRate
    wakeLock.unlock()
    guard !samples.isEmpty,
          let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { source in
      buffer.floatChannelData?[0].update(from: source.baseAddress!, count: samples.count)
    }
    let url = FileManager.default.temporaryDirectory.appending(path: "aegis-wake-snapshot.caf")
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      try file.write(from: buffer)
      return url
    } catch { return nil }
  }

  private func recognize(sessionID: Int, onAudio: @escaping () -> Void, onUpdate: @escaping (String, Bool) -> Void, onError: @escaping (String) -> Void) {
    request = SFSpeechAudioBufferRecognitionRequest()
    request?.shouldReportPartialResults = true
    guard let request, let recognizer, recognizer.isAvailable else { return onError("한국어 음성 인식 엔진을 사용할 수 없습니다.") }
    let input = engine.inputNode
    recordingFormat = input.outputFormat(forBus: 0)
    wakeLock.lock(); wakeSamples = []; wakeSampleRate = recordingFormat?.sampleRate ?? 16_000; wakeLock.unlock()
    beginCommandRecording()
    guard recordedFile != nil else { return onError("음성 확인용 녹음을 시작하지 못했습니다.") }
    input.removeTap(onBus: 0)
    var framesSinceWakeCheck: AVAudioFrameCount = 0
    let wakeCheckFrames = AVAudioFrameCount(recordingFormat?.sampleRate ?? 16_000)
    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
      request.append(buffer)
      try? self?.recordedFile?.write(from: buffer)
      if let channel = buffer.floatChannelData?[0] {
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        self?.wakeLock.lock()
        self?.wakeSamples.append(contentsOf: samples)
        let maximum = Int((self?.wakeSampleRate ?? 16_000) * 2)
        if (self?.wakeSamples.count ?? 0) > maximum { self?.wakeSamples.removeFirst((self?.wakeSamples.count ?? 0) - maximum) }
        self?.wakeLock.unlock()
      }
      framesSinceWakeCheck += buffer.frameLength
      if framesSinceWakeCheck >= wakeCheckFrames {
        framesSinceWakeCheck = 0
        DispatchQueue.main.async { onAudio() }
      }
    }
    engine.prepare()
    do { try engine.start(); listening = true } catch { return onError("마이크를 시작하지 못했습니다: \(error.localizedDescription)") }
    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      guard self.sessionID == sessionID else { return }
      if let result {
        let text = result.bestTranscription.formattedString
        DispatchQueue.main.async { onUpdate(text, result.isFinal) }
        if result.isFinal { self.stop() }
      } else if let error { self.stop(); DispatchQueue.main.async { onError("음성 인식 오류: \(error.localizedDescription)") } }
    }
  }
}
