import AVFoundation
import AppKit
import Foundation
import Speech
import SwiftUI

@main
struct AegisDesktopApp: App {
  @StateObject private var agent = AegisAgent()

  var body: some Scene {
    WindowGroup("Aegis") {
      AegisView(agent: agent).frame(minWidth: 520, minHeight: 560)
        .onAppear { agent.start() }
    }
    MenuBarExtra("Aegis", systemImage: "waveform") {
      AegisView(agent: agent).frame(width: 380, height: 440)
    }
    .menuBarExtraStyle(.window)
  }
}

struct AegisView: View {
  @ObservedObject var agent: AegisAgent
  @State private var message = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading) {
          Text("AEGIS").font(.title.bold())
          Text("LOCAL MAC INTELLIGENCE").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Label(agent.listening ? "듣는 중" : agent.busy ? "생각 중" : "준비됨", systemImage: agent.listening ? "waveform" : "circle.fill")
          .foregroundStyle(agent.listening ? .cyan : .green)
      }
      Divider()
      Text(agent.reply).font(.title3).frame(maxWidth: .infinity, alignment: .leading)
      if agent.listening {
        Text(agent.pendingKakaoMessage != nil ? (agent.heardText.isEmpty ? "카카오톡 전송 승인 대기 중…" : "인식: \(agent.heardText)") : agent.commandListening ? (agent.transcript.isEmpty ? "명령을 듣는 중…" : "명령: \(agent.transcript)") : "호출어 ‘에이제스’를 기다리는 중…")
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12).background(.cyan.opacity(0.12)).clipShape(.rect(cornerRadius: 8))
        Text(agent.pendingKakaoMessage != nil ? "‘전송해’, ‘응’, ‘좋아’, ‘취소’처럼 말씀하세요." : agent.commandListening ? "명령을 듣는 중 · 2초간 말이 없으면 자동 전송합니다." : "‘에이제스’라고 부른 뒤 요청을 말씀해 주세요.")
          .font(.caption).foregroundStyle(.secondary)
      }
      if let message = agent.pendingKakaoMessage {
        VStack(alignment: .leading, spacing: 8) {
          Text("카카오톡 전송 확인").font(.headline)
          Text("받는 사람: \(message.recipient)")
          Text("내용: \(message.body)")
          Text("‘전송해’ 또는 ‘취소’라고 말하거나 버튼을 누르세요.").font(.caption).foregroundStyle(.secondary)
          HStack {
            Button("전송") { agent.confirmKakaoMessage() }.buttonStyle(.borderedProminent)
            Button("취소") { agent.cancelKakaoMessage() }
          }
        }
        .padding(12).background(.orange.opacity(0.14)).clipShape(.rect(cornerRadius: 8))
      }
      Spacer()
      HStack {
        TextField("Aegis에게 요청", text: $message)
          .onSubmit { agent.send(message); message = "" }
        Button("전송") { agent.send(message); message = "" }
          .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agent.busy)
        Button(agent.listening ? "음성 대기 중" : "음성 활성화") { agent.startWakeListening() }
          .disabled(agent.busy)
        Button("종료") { NSApplication.shared.terminate(nil) }
      }
      Text(agent.busy ? "생각 중…" : agent.listening ? "말씀하세요" : "Ollama 로컬 연결")
        .font(.caption).foregroundStyle(.secondary)
    }.padding()
  }
}

@MainActor
final class AegisAgent: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
  @Published var reply = "Aegis가 준비되었습니다."
  @Published var busy = false
  @Published var listening = false
  @Published var transcript = ""
  @Published var heardText = ""
  @Published var commandListening = false
  @Published var pendingKakaoMessage: KakaoMessage?
  private let speaker = AVSpeechSynthesizer()
  private let speech = SpeechInput()
  private var commandActive = false
  private var wakeTranscript = ""
  private var wakeCheckInFlight = false
  private var lastWakeCheck = Date.distantPast
  private var lastCommandText = ""
  private var lastKakaoApprovalText = ""
  private var started = false
  private var silenceTimer: Timer?
  private let finishWords = ["답변해", "대답해", "응답해"]
  private let speechVolume: Float = 0.45

  override init() {
    super.init()
    speaker.delegate = self
  }

  func start() {
    guard !started else { return }
    started = true
    SpeakerVerifier.start()
    let greeting = "안녕하세요. Aegis가 준비되었습니다. 무엇을 도와드릴까요?"
    reply = greeting
    let utterance = AVSpeechUtterance(string: greeting)
    utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
    utterance.volume = speechVolume
    speaker.speak(utterance)
  }

  func startWakeListening() {
    guard !listening, !busy else { return }
    transcript = ""
    heardText = ""
    listening = true
    commandActive = false
    commandListening = false
    wakeTranscript = ""
    wakeCheckInFlight = false
    lastCommandText = ""
    speech.start(onUpdate: { [weak self] text, isFinal in
      guard let self else { return }
      self.heardText = text
      self.handleSpeech(text)
      if isFinal { self.handleFinalRecognition() }
    }, onError: { [weak self] message in
      self?.listening = false
      self?.reply = message
    })
  }

  private func handleSpeech(_ text: String) {
    let lowered = normalized(text)
    if pendingKakaoMessage != nil {
      waitForKakaoApproval(text)
      return
    }
    guard commandActive else { return checkWakeWord(text) }
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

  private func checkWakeWord(_ text: String) {
    guard !wakeCheckInFlight, Date.now.timeIntervalSince(lastWakeCheck) > 0.7 else { return }
    wakeCheckInFlight = true
    lastWakeCheck = .now
    let recording = speech.lastRecordingURL
    Task {
      let score = await WakeWordVerifier.score(for: recording)
      wakeCheckInFlight = false
      guard !commandActive, let score, score >= 0.78 else { return }
      commandActive = true
      commandListening = true
      wakeTranscript = text
      speech.beginCommandRecording()
      transcript = ""
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

  private func handleFinalRecognition() {
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
    Task {
      let score = await SpeakerVerifier.score(for: recording)
      busy = false
      guard let score, score >= 0.72 else {
        reply = score == nil ? "화자 확인을 할 수 없어 음성 명령을 보내지 않았습니다." : "등록한 목소리로 확인되지 않아 명령을 무시했습니다."
        startWakeListening()
        return
      }
      send(text)
    }
  }

  func send(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    if pendingKakaoMessage != nil {
      interpretKakaoApproval(text)
      return
    }
    busy = true
    Task {
      do {
        let plan = try await AgentPlanner.plan(for: text, memories: LearningMemory.recent())
        busy = false
        execute(plan, request: text)
      } catch {
        busy = false
        speak("로컬 AI 연결에 실패했습니다. 다시 말씀해 주세요.")
      }
    }
  }

  private func execute(_ plan: AgentPlan, request: String) {
    switch plan.action {
    case "kakao_message":
      guard let recipient = plan.recipient?.trimmingCharacters(in: .whitespacesAndNewlines), !recipient.isEmpty,
            let body = plan.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
        speak("받는 사람이나 보낼 내용을 이해하지 못했습니다. 다시 말씀해 주세요.")
        LearningMemory.record(request: request, action: plan.action, result: "정보 부족")
        return
      }
      pendingKakaoMessage = KakaoMessage(recipient: recipient, body: body)
      reply = "카카오톡 전송 내용을 확인해 주세요."
      LearningMemory.record(request: request, action: plan.action, result: "승인 대기")
      startWakeListening()
    case "open_application":
      let application = plan.application?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !application.isEmpty else { speak("열 앱을 이해하지 못했습니다. 다시 말씀해 주세요."); return }
      LearningMemory.record(request: request, action: plan.action, result: application)
      launch(application)
    case "close_application":
      let application = plan.application?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !application.isEmpty else { speak("닫을 앱을 이해하지 못했습니다. 다시 말씀해 주세요."); return }
      close(application, request: request)
    case "get_active_application":
      let result = MacTools.activeApplication()
      LearningMemory.record(request: request, action: plan.action, result: result)
      speak(result)
    default:
      let answer = plan.answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "요청을 이해하지 못했습니다."
      LearningMemory.record(request: request, action: "answer", result: answer)
      speak(answer)
    }
  }

  private func interpretKakaoApproval(_ text: String) {
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
    pendingKakaoMessage = nil
    busy = true
    Task {
      let result = await KakaoTalkAutomation.send(message)
      busy = false
      LearningMemory.record(request: "카카오톡 \(message.recipient)에게 \(message.body)", action: "kakao_message", result: result)
      speak(result)
    }
  }

  func cancelKakaoMessage() {
    pendingKakaoMessage = nil
    reply = "카카오톡 전송을 취소했습니다."
    startWakeListening()
  }

  private func launch(_ application: String) {
    busy = true
    Task {
      let message = await MacApplicationLauncher.open(application)
      busy = false
      speak(message)
    }
  }

  private func close(_ application: String, request: String) {
    busy = true
    Task {
      let result = await MacApplicationLauncher.close(application)
      busy = false
      LearningMemory.record(request: request, action: "close_application", result: result)
      speak(result)
    }
  }

  private func speak(_ text: String) {
    reply = text
    speaker.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
    utterance.volume = speechVolume
    speaker.speak(utterance)
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in startWakeListening() }
  }
}

enum MacApplicationLauncher {
  private static let actions = ["켜줘", "켜 줘", "실행해", "실행 해", "열어줘", "열어 줘", "열어"]

  static func requestedApplication(from text: String) -> String? {
    guard let action = actions.compactMap({ text.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
    let requested = String(text[..<action.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "을를은는이가"))
    guard !requested.isEmpty else { return nil }
    let compact = requested.lowercased().components(separatedBy: .whitespaces).joined()
    if compact.contains("리그오브레전드") || compact == "롤" { return "League of Legends" }
    if compact == "파인더" { return "Finder" }
    if compact == "사파리" { return "Safari" }
    if compact == "크롬" || compact == "구글크롬" { return "Google Chrome" }
    if compact == "파이어폭스" { return "Firefox" }
    if compact == "카카오톡" { return "KakaoTalk" }
    if compact == "비주얼스튜디오코드" || compact == "vscode" { return "Visual Studio Code" }
    if compact == "메모" { return "Notes" }
    if compact == "메시지" { return "Messages" }
    if compact == "캘린더" { return "Calendar" }
    if compact == "터미널" { return "Terminal" }
    return requested
  }

  static func open(_ application: String) async -> String {
    await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      if let path = installedApplicationPath(named: application) {
        process.arguments = [path]
      } else {
        process.arguments = ["-a", application]
      }
      do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "\(application)을 실행했습니다." : "\(application)을(를) 찾지 못했습니다. 설치된 앱 이름을 확인해 주세요."
      } catch {
        return "\(application)을(를) 실행하지 못했습니다: \(error.localizedDescription)"
      }
    }.value
  }

  static func close(_ application: String) async -> String {
    await Task.detached {
      guard let path = installedApplicationPath(named: application),
            let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier,
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        return "\(application)은(는) 현재 실행 중이지 않습니다."
      }
      return running.terminate() ? "\(application)을 종료했습니다." : "\(application)을 종료하지 못했습니다. 저장하지 않은 작업이 있는지 확인해 주세요."
    }.value
  }

  private static func installedApplicationPath(named application: String) -> String? {
    let fileManager = FileManager.default
    let directories = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
    let target = application.lowercased().components(separatedBy: .whitespaces).joined()
    let candidates: [URL] = directories.flatMap { directory -> [URL] in
      guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
      var applications: [URL] = []
      while let url = enumerator.nextObject() as? URL {
        guard url.pathExtension == "app" else { continue }
        applications.append(url)
        enumerator.skipDescendants()
      }
      return applications
    }
    let named = candidates.map { url in
      (url, url.deletingPathExtension().lastPathComponent.lowercased().components(separatedBy: .whitespaces).joined())
    }
    if let exact = named.first(where: { $0.1 == target }) { return exact.0.path }
    return named.first(where: { $0.1.contains(target) || target.contains($0.1) })?.0.path
  }
}

final class SpeechInput: NSObject {
  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var sessionID = 0
  private var recordedFile: AVAudioFile?
  private var recordingFormat: AVAudioFormat?
  private(set) var lastRecordingURL: URL?
  var listening = false

  func start(onUpdate: @escaping (String, Bool) -> Void, onError: @escaping (String) -> Void) {
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
          self?.recognize(sessionID: currentSessionID, onUpdate: onUpdate, onError: onError)
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

  private func recognize(sessionID: Int, onUpdate: @escaping (String, Bool) -> Void, onError: @escaping (String) -> Void) {
    request = SFSpeechAudioBufferRecognitionRequest()
    request?.shouldReportPartialResults = true
    guard let request, let recognizer, recognizer.isAvailable else { return onError("한국어 음성 인식 엔진을 사용할 수 없습니다.") }
    let input = engine.inputNode
    recordingFormat = input.outputFormat(forBus: 0)
    beginCommandRecording()
    guard recordedFile != nil else { return onError("음성 확인용 녹음을 시작하지 못했습니다.") }
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
      request.append(buffer)
      try? self?.recordedFile?.write(from: buffer)
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

enum SpeakerVerifier {
  private static let workspace = "/Users/kimjinsol/Aegis-MVP"
  private static var service: Process?

  static func start() {
    guard service == nil else { return }
    let root = URL(fileURLWithPath: workspace)
    let process = Process()
    process.executableURL = root.appending(path: ".aegis/f5-tts/bin/python")
    process.arguments = [root.appending(path: "scripts/speaker_server.py").path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      service = process
    } catch { }
  }

  static func score(for recording: URL?) async -> Double? {
    guard let recording else { return nil }
    start()
    for _ in 0..<60 {
      if let score = await requestScore(for: recording) { return score }
      try? await Task.sleep(for: .milliseconds(250))
    }
    return nil
  }

  private static func requestScore(for recording: URL) async -> Double? {
    guard let url = URL(string: "http://127.0.0.1:4319/verify") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 2
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["audio": recording.path])
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
      return (try JSONSerialization.jsonObject(with: data) as? [String: Double])?["score"]
    } catch { return nil }
  }
}

enum WakeWordVerifier {
  static func score(for recording: URL?) async -> Double? {
    guard let recording, let url = URL(string: "http://127.0.0.1:4319/wake") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 2
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["audio": recording.path])
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
      return (try JSONSerialization.jsonObject(with: data) as? [String: Double])?["score"]
    } catch { return nil }
  }
}

enum Ollama {
  static func structured(system: String, content: String, schema: [String: Any]) async throws -> AgentPlan {
    let url = URL(string: "http://127.0.0.1:11434/api/chat")!
    let body: [String: Any] = [
      "model": "qwen3:8b", "stream": false, "keep_alive": "30m",
      "think": false, "options": ["num_ctx": 4096, "num_predict": 320, "temperature": 0], "format": schema,
      "messages": [["role": "system", "content": system], ["role": "user", "content": content]],
    ]
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 180
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let message = json["message"] as? [String: Any],
          let raw = message["content"] as? String else { throw URLError(.cannotParseResponse) }
    return plan(from: raw)
  }

  private static func plan(from raw: String) -> AgentPlan {
    let cleaned = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
    let start = cleaned.firstIndex(of: "{") ?? cleaned.startIndex
    let json = cleaned[start...]
    if let end = json.lastIndex(of: "}"),
       let data = String(json[...end]).data(using: .utf8),
       let plan = try? JSONDecoder().decode(AgentPlan.self, from: data),
       ["kakao_message", "open_application", "close_application", "get_active_application", "answer"].contains(plan.action) {
      return plan
    }
    return AgentPlan(action: "unknown", recipient: nil, body: nil, application: nil, answer: nil)
  }

  static func kakaoDecision(_ text: String, message: KakaoMessage) async throws -> String {
    let url = URL(string: "http://127.0.0.1:11434/api/chat")!
    let body: [String: Any] = [
      "model": "qwen3:8b", "stream": false, "keep_alive": "30m",
      "options": ["num_ctx": 2048, "num_predict": 512, "temperature": 0],
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
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 180
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let message = json["message"] as? [String: Any],
          let content = message["content"] as? String,
          let jsonData = content.data(using: .utf8),
          let decision = try JSONSerialization.jsonObject(with: jsonData) as? [String: String],
          let value = decision["decision"] else { return "unknown" }
    return value
  }

  static func chat(_ text: String) async throws -> String {
    let url = URL(string: "http://127.0.0.1:11434/api/chat")!
    let body: [String: Any] = [
      "model": "qwen3:8b", "stream": false, "keep_alive": "30m",
      "options": ["num_ctx": 4096, "num_predict": 512, "temperature": 0.3],
      "messages": [["role": "system", "content": "당신은 사용자의 Mac을 돕는 Aegis다. 반드시 자연스러운 한국어로만 답한다. 최종 답변은 간결하고 실행 가능한 형태로 말한다."], ["role": "user", "content": text]],
    ]
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 180
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let message = json?["message"] as? [String: Any]
    let answer = message?["content"] as? String ?? "응답을 생성하지 못했습니다."
    return answer.components(separatedBy: "</think>").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? answer
  }
}
