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

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading) {
          Text("AEGIS").font(.title.bold())
          Text("TEXT CHAT · LOCAL MAC INTELLIGENCE").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Label(agent.busy ? "처리 중" : "준비됨", systemImage: "circle.fill")
          .foregroundStyle(agent.busy ? .orange : .green)
        Button("종료") { NSApplication.shared.terminate(nil) }
      }
      .padding()
      Divider()
      ChatView(store: agent.chat, busy: agent.busy, submit: agent.send,
        cancel: agent.cancelCurrentOperation,
        approve: agent.approveChatAction, reject: agent.rejectChatAction)
    }
  }
}

@MainActor
final class AegisAgent: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
  let voiceInputEnabled = false
  let chat = ChatStore()
  let memoryStore = MemoryStore()
  let skillStore = SkillStore()
  let screenInspector = ScreenInspector()
  let visibleWindows = VisibleWindowService()
  let accessibility = AccessibilityService()
  let uiCoordinator = UIInteractionCoordinator()
  let codingCoordinator = CodingTaskCoordinator()
  let codingProviders = CodingAgentProviderPool()
  let autonomousDevelopment = AutonomousDevelopmentCoordinator()
  let desktopBridge = DesktopBridgeServer()
  lazy var developmentSessions = DevelopmentSessionCoordinator(memory: memoryStore.repository)
  lazy var proactiveCoordinator = ProactiveCoordinator(memory: memoryStore.repository)
  lazy var contextObserver = ContextObserver { [weak self] in
    guard let self else { return }
    let notices = await self.proactiveCoordinator.observe()
    self.surface(notices)
  }
  @Published var reply = "Aegis가 준비되었습니다."
  @Published var busy = false
  @Published var listening = false
  @Published var transcript = ""
  @Published var heardText = ""
  @Published var commandListening = false
  @Published var pendingKakaoMessage: KakaoMessage?
  @Published var pendingMacAction: PendingMacAction?
  @Published var sampleStatus = ""
  @Published var activitySteps = ["호출어 대기 중"]
  @Published var hasWakeCandidate = false
  private let speaker = AVSpeechSynthesizer()
  private let speech = SpeechInput()
  private let sampleRecorder = WakeSampleRecorder()
  private var commandActive = false
  private var wakeTranscript = ""
  private var wakeCheckInFlight = false
  private var wakeCandidateURL: URL?
  private var lastWakeCheck = Date.distantPast
  private var lastCommandText = ""
  private var lastKakaoApprovalText = ""
  private var pendingKakaoApprovalID: UUID?
  var planExecutor: AgentPlanExecutor?
  var recentUIWindowTarget: ResolvedWindowTarget?
  var activeSkill: LearnedSkill?
  var pendingSkillProposal: PendingSkillProposal?
  var ignoredSkillPatterns: Set<SkillPattern> = []
  private var executingStepID: UUID?
  var screenAnalysisTask: Task<Void, Never>?
  var codingTask: Task<Void, Never>?
  var codingFindings: [CodingFindingContext] = []
  var activeCodingContinuation: CodingFindingContext?
  var pendingProjectDiscovery: (name: String, path: String)?
  var activeCodingTaskProposal: CodingTaskProposal?
  var codingTaskProposalLifecycle: CodingTaskProposalLifecycle?
  var activeDevelopmentCandidate: DevelopmentTaskCandidate?
  var gitWorkflowContext = GitWorkflowContext()
  var conversationSessionID = "desktop"
  var developerValidationResults: [String: [ProjectValidationCheck: ProjectValidationResult]] = [:]
  private var started = false
  private var terminationObserver: NSObjectProtocol?
  private var silenceTimer: Timer?
  private var speechRecoveryTimer: Timer?
  private let finishWords = ["답변해", "대답해", "응답해"]
  private let speechVolume: Float = 0.45

  override init() {
    super.init()
    speaker.delegate = self
  }

  func start() {
    guard !started else { return }
    started = true
    LearningStore.bootstrap()
    restoreProactivePreferences()
    contextObserver.start()
    desktopBridge.start()
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in Task { @MainActor in self?.stop() } }
  }

  func stop() {
    contextObserver.stop()
    desktopBridge.stop()
    if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    terminationObserver = nil
    codingFindings.removeAll(); activeCodingContinuation = nil
    activeCodingTaskProposal = nil; codingTaskProposalLifecycle = nil
  }

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

  private func startCommandListening() {
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

  private func saveWakeCandidate(from source: URL?) -> URL? {
    guard let source else { return nil }
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "Aegis/wake-false-candidates")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let destination = folder.appending(path: "\(UUID().uuidString).caf")
    do { try FileManager.default.copyItem(at: source, to: destination); return destination } catch { return nil }
  }

  private func handleSpeech(_ text: String) {
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

  private func checkWakeWord(_ text: String, recording: URL?) {
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
      send(text)
    }
  }

  func send(_ text: String) {
    let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return }
    chat.append(.user, message)
    if CodingAgentProviderPolicy.rejects(message) {
      speak(CodingAgentProviderPolicy.unsupportedMessage); return
    }
    if let proactiveIntent = ProactiveIntentParser.parse(message) {
      speak(handleProactiveIntent(proactiveIntent)); return
    }
    if let remotePlan = RemoteControlIntentResolver.plan(for: message) {
      execute(remotePlan, request: message); return
    }
    if pendingKakaoMessage != nil { interpretKakaoApproval(message); return }
    if pendingMacAction != nil { interpretMacApproval(message); return }
    if ProjectDiscoveryConfirmationParser.isConfirmation(message) {
      if let discovery = pendingProjectDiscovery {
        let result = memoryStore.handle(.remember(type: .project, key: discovery.name, value: discovery.path))
        pendingProjectDiscovery = nil
        speak(result)
      } else {
        speak("먼저 \"<프로젝트> 위치 찾아줘\"라고 말씀해 주시면 경로를 찾아드릴게요.")
      }
      return
    }
    if let continuation = GitWorkflowContinuationResolver.resolve(message,
      repository: memoryStore.repository, context: &gitWorkflowContext) {
      switch continuation {
      case .plan(let plan): execute(plan, request: message)
      case .message(let value): speak(value)
      }
      return
    }
    let explicitCodingProject = ProjectEntityResolver.resolve(in: message,
      repository: memoryStore.repository)
    if let project = explicitCodingProject,
      !codingFindings.isEmpty, !codingFindings.contains(where: { $0.projectId == project.name.lowercased() }) {
      codingFindings.removeAll(); activeCodingContinuation = nil
    }
    if let continuation = CodingContinuationIntentResolver.resolve(message,
      findings: codingFindings, explicitProject: explicitCodingProject) {
      switch continuation {
      case .write(let intent):
        activeCodingContinuation = intent.finding
        execute(intent.plan, request: message); return
      case .explain(let finding):
        speak(CodingFindingFormatter.explain(finding)); return
      case .inspectMore(let finding):
        activeCodingContinuation = finding
        execute(AgentPlan(step: AgentStep(action: .analyzeProjectWithCodingAgent,
          content: message, project: finding.projectName, codingMode: .readOnlyAnalysis)),
          request: message); return
      case .findAnother(let finding):
        activeCodingContinuation = nil
        execute(AgentPlan(step: AgentStep(action: .analyzeProjectWithCodingAgent,
          content: message, project: finding.projectName, codingMode: .readOnlyAnalysis)),
          request: message); return
      case .clarify:
        speak("최근 개선점이 여러 프로젝트에 있습니다. 어느 프로젝트의 문제인지 말해 주세요."); return
      case .forget:
        codingFindings.removeAll(); activeCodingContinuation = nil
        speak("이전 코딩 개선점을 이어서 사용하지 않겠습니다."); return
      }
    }
    if let readOnlyCoding = CodingIntentResolver.explicitReadOnlyPlan(for: message,
      repository: memoryStore.repository, recentWindow: recentUIWindowTarget) {
      execute(readOnlyCoding, request: message)
      return
    }
    if let autonomous = AutonomousDevelopmentIntentResolver.plan(for: message,
      repository: memoryStore.repository, active: activeDevelopmentCandidate,
      recentWindow: recentUIWindowTarget) {
      execute(autonomous, request: message); return
    }
    if let skillIntent = SkillIntentParser.parse(message) {
      do { speak(try skillStore.handle(skillIntent)) }
      catch { speak(error.localizedDescription, role: .error) }
      return
    }
    if let memoryIntent = MemoryIntentParser.parse(message) {
      let result = memoryStore.handle(memoryIntent)
      speak(result, role: result.hasPrefix("메모리 저장소 오류") ? .error : .assistant)
      return
    }
    if let uiPlan = UIIntentResolver.plan(for: message, repository: memoryStore.repository) {
      execute(uiPlan, request: message)
      return
    }
    if let screenPlan = ScreenIntentResolver.plan(for: message, repository: memoryStore.repository) {
      execute(screenPlan, request: message)
      return
    }
    if let codingPlan = CodingIntentResolver.plan(for: message,
      repository: memoryStore.repository, recentWindow: recentUIWindowTarget) {
      execute(codingPlan, request: message)
      return
    }
    if let gitPlan = GitWorkflowIntentResolver.plan(for: message,
      repository: memoryStore.repository, context: gitWorkflowContext) {
      execute(gitPlan, request: message)
      return
    }
    if let skill = matchedSkill(message) {
      execute(AgentPlan(steps: skill.steps), request: message, skill: skill)
      return
    }
    busy = true
    recordActivity("AI 백엔드 행동 계획 생성")
    Task {
      do {
        if DeveloperSemanticResolver.shouldClassify(message, repository: memoryStore.repository),
          let project = ProjectEntityResolver.resolve(in: message, repository: memoryStore.repository) {
          let decision: DeveloperSemanticDecision
          do {
            decision = try await DeveloperSemanticResolver.classify(message, project: project)
          } catch {
            busy = false
            speak("개발 요청을 분류하지 못했습니다. 코드 조사인지 실제 수정인지 다시 말씀해 주세요.",
              role: .error)
            return
          }
          busy = false
          switch DeveloperSemanticResolver.resolve(decision, request: message, project: project,
            repository: memoryStore.repository) {
          case .plan(let plan): execute(plan, request: message)
          case .message(let value): speak(value)
          }
          return
        }
        if GitWorkflowSemanticResolver.shouldClassify(message, context: gitWorkflowContext) {
          let decision: GitFollowUpDecision
          do {
            decision = try await GitWorkflowSemanticResolver.classify(message,
              context: gitWorkflowContext)
          } catch {
            busy = false
            speak("커밋 후속 요청을 분류하지 못했습니다. 계획을 다시 만들지, 실행할지 말씀해 주세요.",
              role: .error)
            return
          }
          if let continuation = GitWorkflowSemanticResolver.resolve(decision, request: message,
            repository: memoryStore.repository, context: &gitWorkflowContext) {
            busy = false
            switch continuation {
            case .plan(let plan): execute(plan, request: message)
            case .message(let value): speak(value)
            }
            return
          }
        }
        if let developerPlan = DeveloperIntentResolver.plan(for: message,
          repository: memoryStore.repository) {
          busy = false; execute(developerPlan, request: message); return
        }
        if let projectPlan = ProjectIntentResolver.plan(for: message,
          repository: memoryStore.repository) {
          busy = false; execute(projectPlan, request: message); return
        }
        let memory = MemoryRetriever.relevant(to: message, repository: memoryStore.repository)
        let plan = try await AgentPlanner.plan(for: message, memory: memory)
        busy = false
        execute(plan, request: message)
      } catch {
        busy = false
        speak(error.localizedDescription, role: .error)
      }
    }
  }

  private func execute(_ plan: AgentPlan, request: String, skill: LearnedSkill? = nil) {
    do {
      planExecutor = try AgentPlanExecutor(plan: plan, request: request, isLearnedSkill: skill != nil)
      activeSkill = skill
      busy = true
      advancePlan()
    } catch {
      busy = false
      speak(error.localizedDescription, role: .error)
    }
  }

  private func advancePlan() {
    guard var executor = planExecutor else { return }
    let decision = executor.next()
    planExecutor = executor
    switch decision {
    case .execute(let step, let index, let total):
      executingStepID = step.id
      chat.append(.system, "\(index)/\(total) \(step.action.rawValue) 실행 중…")
      execute(step, request: executor.state.request)
    case .approval(let step, let index, let total):
      executingStepID = step.id
      if step.action == .executeCodingTask { codingTaskProposalLifecycle = .awaitingApproval }
      if step.action == .createCommit { gitWorkflowContext.state = .awaitingCommitApproval }
      if step.action == .pushCurrentBranch { gitWorkflowContext.state = .awaitingPushApproval }
      if step.action.isDockerMutation {
        validateThenRequestDockerApproval(step, request: executor.state.request,
          progress: "\(index)/\(total)")
      } else {
        requestStepApproval(step, request: executor.state.request, progress: "\(index)/\(total)")
      }
    case .skipped(let step, let index, let total):
      chat.append(.system, "\(index)/\(total) \(step.action.rawValue) 건너뜀 · 이전 필수 단계 실패")
      advancePlan()
    case .preflightApproval(let id, let steps):
      prepareUIWorkflowPreflight(id: id, steps: steps, request: executor.state.request)
    case .finished(let summary):
      if let answer = PlanExecutionFormatter.format(summary,
        plan: executor.state.plan, request: executor.state.request), !answer.isEmpty {
        speak(answer, role: summary.status == .succeeded ? .assistant : .error)
      }
      finishSkillExecution(executor)
      planExecutor = nil; executingStepID = nil; busy = false
    }
  }

  private func execute(_ step: AgentStep, request: String) {
    let action = step.action.rawValue
    recordActivity("AI 선택: \(action)")
    switch step.action {
    case .kakaoMessage:
      guard let recipient = step.recipient?.trimmingCharacters(in: .whitespacesAndNewlines), !recipient.isEmpty,
            let body = step.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
        failCurrentStep("받는 사람이나 보낼 내용을 이해하지 못했습니다.")
        return
      }
      sendKakao(KakaoMessage(recipient: recipient, body: body), request: request)
    case .openApplication:
      let application = step.application?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !application.isEmpty else { failCurrentStep("열 앱을 이해하지 못했습니다."); return }
      if let project = step.project { openRememberedProject(project, request: request) }
      else { launch(application, request: request) }
    case .openProject:
      let project = step.project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let application = step.application?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !project.isEmpty, !application.isEmpty else {
        failCurrentStep("프로젝트와 코드 에디터가 필요합니다."); return
      }
      openProject(project, application: application, request: request)
    case .closeApplication:
      let application = step.application?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !application.isEmpty else { failCurrentStep("닫을 앱을 이해하지 못했습니다."); return }
      close(application, request: request)
    case .browserSearch:
      let browser = step.browser?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let site = step.site?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let query = step.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !site.isEmpty else {
        failCurrentStep("브라우저 검색 내용을 이해하지 못했습니다.")
        return
      }
      let selectedBrowser = browser.isEmpty ? "Safari" : browser
      search(browser: selectedBrowser, site: site, query: query, request: request)
    case .getActiveApplication:
      let result = MacTools.activeApplication()
      finishReadTool(result, action: action, request: request)
    case .getSystemStatus:
      finishReadTool(MacToolbox.systemStatus(), action: action, request: request)
    case .getAIBackendStatus:
      runAIBackendDiagnostics(request: request)
    case .getRemoteControlStatus:
      Task {
        let result = await RemoteControlDiagnostics.report(bridge: .load(),
          desktopBridgeStatus: desktopBridge.status)
        finishReadTool(result, action: action, request: request)
      }
    case .listRunningApplications:
      finishReadTool(MacToolbox.runningApplications(), action: action, request: request)
    case .getClipboard:
      finishReadTool(MacToolbox.clipboardText(), action: action, request: request)
    case .getServerStatus:
      runServerTool(.status, request: request)
    case .getDockerContainers:
      runServerTool(.containers, request: request)
    case .getDockerLogs:
      let container = step.container?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !container.isEmpty else { failCurrentStep("확인할 컨테이너 이름이 필요합니다."); return }
      runServerTool(.logs, request: request, arguments: ["container": container, "lines": step.lines ?? 100])
    case .getServerProjectStatus:
      let project = step.project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !project.isEmpty else { failCurrentStep("확인할 서버 프로젝트가 필요합니다."); return }
      runServerTool(.projectStatus, request: request, arguments: ["project": project])
    case .getRememberedProjectStatus:
      let project = step.project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !project.isEmpty else { failCurrentStep("확인할 프로젝트가 필요합니다."); return }
      runRememberedProjectStatus(project, request: request)
    case .getProjectGitStatus, .getProjectBranch, .getProjectDiffSummary,
         .getProjectRecentCommits, .getProjectChangedFiles, .getProjectPackageScripts,
         .getProjectHealth, .assessProjectDeploymentReadiness, .runProjectTypecheck, .runProjectTests, .runProjectLint,
         .runProjectBuild, .startDevelopmentSession, .endDevelopmentSession,
         .getDevelopmentRecap, .getTodayDevelopmentSummary:
      runDeveloperTool(step, request: request)
    case .getCodingAgentStatus, .getCodingAgentRecentDiagnostics,
      .analyzeProjectWithCodingAgent, .proposeCodingTask,
         .executeCodingTask, .reviewCodingTaskResult, .verifyCodingTask, .rollbackCodingTask:
      runCodingTool(step, request: request)
    case .discoverDevelopmentTask, .rankDevelopmentCandidates, .proposeDevelopmentTask,
         .executeDevelopmentTask, .verifyDevelopmentTask, .repairDevelopmentTask,
         .getAutonomousDevelopmentStatus:
      runAutonomousDevelopmentTool(step, request: request)
    case .inspectGitDiff, .proposeCommitPlan, .createCommit, .getRemoteStatus,
         .proposePush, .pushCurrentBranch, .getCIStatus, .getPullRequestStatus,
         .getGitWorkflowStatus:
      runGitWorkflowTool(step, request: request)
    case .captureScreen, .inspectScreen, .inspectActiveWindow,
         .inspectScreenWithProjectContext, .getScreenAwarenessStatus,
         .listVisibleWindows, .inspectWindow:
      runScreenTool(step, request: request)
    case .getUIControlStatus, .getVSCodeQuickOpenStatus, .activateApplication, .focusWindow, .closeWindow,
         .listUIElements, .inspectUIElement, .pressUIElement, .focusUIElement,
         .setUIText, .appendUIText, .pressKeyboardShortcut, .scrollUI, .selectMenuItem:
      runUITool(step, request: request)
    case .startDockerContainer, .stopDockerContainer, .restartDockerContainer:
      let container = step.container?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !container.isEmpty else { failCurrentStep("변경할 컨테이너 이름이 필요합니다."); return }
      runValidatedDockerMutation(step, container: container, request: request)
    case .setClipboard:
      let content = step.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !content.isEmpty else { failCurrentStep("클립보드에 저장할 내용을 이해하지 못했습니다."); return }
      finishReadTool(MacToolbox.setClipboard(content), action: action, request: request, target: "clipboard")
    case .findProjectPath:
      let name = step.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !name.isEmpty else { failCurrentStep("찾을 프로젝트 이름을 이해하지 못했습니다."); return }
      if let path = ProjectDiscovery.find(named: name) {
        pendingProjectDiscovery = (name: name, path: path)
        finishReadTool("\"\(name)\" 위치를 찾았습니다: \(path)\n등록하려면 \"등록해\"라고 말씀해 주세요.",
          action: action, request: request, target: name)
      } else {
        finishReadTool("\"\(name)\"를 찾지 못했습니다. 홈 디렉터리 바로 아래나 ~/Developer, ~/Projects, ~/Documents 안에 있는지 확인해 주세요.",
          action: action, request: request, target: name)
      }
    default:
      failCurrentStep("지원하지 않는 실행 단계입니다.")
    }
  }

  func finishReadTool(_ result: String, action: String, request: String, target: String = "",
                      succeeded explicitSuccess: Bool? = nil) {
    // Reaching this point means the underlying call returned without throwing --
    // any real failure already went through the separate catch -> failCurrentStep
    // path. The result text is informational (git status, server state, UI
    // status, ...) and must never retroactively flip a successful read to
    // "failed" just because it mentions a word like "필요합니다" or "오류".
    let succeeded = explicitSuccess ?? true
    LearningMemory.record(request: request, action: action, result: result)
    memoryStore.recordAction(request: request, action: action, target: target,
      result: result, succeeded: succeeded)
    speak(result)
    completeCurrentStep(succeeded: succeeded, result: result)
  }

  func runServerTool(_ tool: ServerTool, request: String, arguments: [String: Any] = [:], approved: Bool = false) {
    guard tool.requiresApproval == approved else {
      speak("승인 상태가 올바르지 않아 서버 작업을 실행하지 않았습니다.")
      return
    }
    busy = true
    recordActivity("sol-server · \(tool.rawValue)")
    Task {
      do {
        let result = try await ServerAgentClient.call(tool, arguments: arguments)
        busy = false
        let target = arguments["container"] as? String ?? arguments["project"] as? String ?? "sol-server"
        finishReadTool(result, action: tool.rawValue, request: request, target: target)
      } catch {
        let target = arguments["container"] as? String ?? arguments["project"] as? String ?? "sol-server"
        memoryStore.recordAction(request: request, action: tool.rawValue, target: target,
          result: error.localizedDescription, succeeded: false)
        speak(error.localizedDescription, role: .error)
        completeCurrentStep(succeeded: false)
      }
    }
  }

  private func runRememberedProjectStatus(_ project: String, request: String) {
    busy = true
    Task {
      do {
        let result = try MemoryProjectTool.status(project: project, repository: memoryStore.repository)
        busy = false
        finishReadTool(result, action: AgentAction.getRememberedProjectStatus.rawValue,
          request: request, target: project)
      } catch {
        memoryStore.recordAction(request: request, action: AgentAction.getRememberedProjectStatus.rawValue,
          target: project, result: error.localizedDescription, succeeded: false)
        speak(error.localizedDescription, role: .error)
        completeCurrentStep(succeeded: false)
      }
    }
  }

  func requestStepApproval(_ step: AgentStep, request: String, progress: String) {
    let title: String
    let detail: String
    var arguments: [String: String] = [:]
    switch step.action {
    case .kakaoMessage:
      title = "\(step.recipient ?? "")에게 카카오톡 전송"
      detail = step.body ?? ""
    case .openApplication:
      title = step.project.map { "\($0) 프로젝트 열기" } ?? "\(step.application ?? "") 실행"
      detail = "앱 또는 프로젝트를 열고 화면 앞으로 가져옵니다."
    case .openProject:
      title = "\(step.project ?? "") 프로젝트 열기"
      detail = "허용된 \(step.application ?? "코드 에디터")에서 등록된 프로젝트를 엽니다."
    case .closeApplication:
      title = "\(step.application ?? "") 종료"; detail = "저장하지 않은 작업이 영향을 받을 수 있습니다."
    case .browserSearch:
      title = "브라우저 검색"; detail = "\(step.browser ?? "Safari")에서 \(step.site ?? "") · \(step.query ?? "")"
    case .setClipboard:
      title = "클립보드 변경"; detail = String((step.content ?? "").prefix(300))
    case .setUIText, .appendUIText:
      title = "UI 텍스트 입력"
      detail = "\(step.uiLabel ?? "입력 필드")에 '\(String((step.content ?? "").prefix(300)))'을 입력합니다."
    case .pressUIElement, .selectMenuItem:
      title = "UI 요소 실행"; detail = "\(step.uiLabel ?? "지정한 요소")을 실행합니다."
    case .closeWindow:
      title = "창 닫기"
      detail = "\(step.project ?? step.application ?? "현재") 창만 닫습니다. 앱은 종료하지 않습니다."
    case .runProjectTypecheck, .runProjectTests, .runProjectLint, .runProjectBuild:
      title = "\(step.project ?? "") 프로젝트 검증"
      detail = "등록된 package.json의 \(step.action.rawValue.replacingOccurrences(of: "run_project_", with: "")) 스크립트를 실행합니다."
    case .executeCodingTask:
      title = "\(step.project ?? "") 코딩 작업"
      detail = activeCodingTaskProposal.map(CodingFindingProposalFormatter.format)
        ?? CodingFindingProposalFormatter.format(project: step.project ?? "",
          request: step.content ?? request, finding: activeCodingContinuation)
    case .executeDevelopmentTask, .repairDevelopmentTask:
      title = "\(step.project ?? "") 자율 개발 작업"
      detail = activeDevelopmentCandidate.map {
        AutonomousDevelopmentFormatter.proposal($0, executable: true)
      } ?? "승인된 작은 개발 작업을 Codex로 수행하고 Git 변경 및 검증 결과를 확인합니다."
    case .rollbackCodingTask:
      title = "\(step.project ?? "") 코딩 작업 롤백"
      detail = "해당 작업에 독립적으로 귀속되고 이후 변경이 없는 tracked 파일만 되돌립니다."
    case .createCommit:
      title = "\(step.project ?? "") 커밋 생성"
      detail = gitWorkflowContext.plan.map(GitWorkflowFormatter.plan)
        ?? "승인된 파일만 정확히 stage하고 로컬 커밋을 생성합니다. push는 수행하지 않습니다."
    case .pushCurrentBranch:
      title = "\(step.project ?? "") 현재 브랜치 push"
      detail = gitWorkflowContext.pushProposal.map(GitWorkflowFormatter.push)
        ?? "현재 브랜치를 일반 push합니다. force push는 지원하지 않습니다."
    case .startDockerContainer, .stopDockerContainer, .restartDockerContainer:
      let operation = step.action.rawValue.replacingOccurrences(of: "_docker_container", with: "")
      title = "\(step.container ?? "") 컨테이너 \(serverActionLabel(operation))"
      detail = "sol-server에서 Docker \(operation) 작업을 실행합니다."
    default:
      failCurrentStep("승인이 필요하지 않은 단계입니다."); return
    }
    arguments["progress"] = progress
    if let project = step.project { arguments["project"] = project }
    if step.action == .createCommit, let id = gitWorkflowContext.activeCommitPlanId {
      arguments["gitCommitPlanId"] = id.uuidString
    }
    requestApproval(id: step.id, kind: step.action.rawValue, title: "\(progress) \(title)",
      detail: detail, request: request, arguments: arguments)
  }

  private func prepareUIWorkflowPreflight(id: UUID, steps: [AgentStep], request: String) {
    busy = true
    Task {
      do {
        let windows = try await visibleWindows.list()
        guard let targetStep = planExecutor?.state.plan.steps.first(where: {
          $0.action.isUIAction && $0.action != .getUIControlStatus
        }) else { throw UIInteractionError.targetNotFound("승인할 UI") }
        if targetStep.application == nil, recentUIWindowTarget == nil {
          throw UIInteractionError.targetNotFound("승인할 정확한 창")
        }
        let window = try UIWindowTargetResolver.resolve(step: targetStep, windows: windows,
          workflow: nil, recent: recentUIWindowTarget)
        let approved = try ApprovedUITarget(window: window,
          semanticTarget: steps.map { $0.action.rawValue }.joined(separator: ","))
        let resolved = try ResolvedWindowTarget(window)
        planExecutor?.setPreflightTarget(approved, resolvedWindow: resolved)
        busy = false
        let detail = steps.map { approvalDescription($0) }.joined(separator: "\n")
        requestApproval(id: id, kind: "ui_workflow_preflight", title: "UI 작업 사전 승인",
          detail: detail, request: request, arguments: [:])
      } catch {
        busy = false; speak(error.localizedDescription, role: .error)
        if planExecutor?.rejectPreflight(id) == true { advancePlan() }
      }
    }
  }

  private func approvalDescription(_ step: AgentStep) -> String {
    switch step.action {
    case .closeWindow: "- \(step.project ?? step.application ?? "현재") 창 닫기"
    case .setUIText, .appendUIText:
      "- \(step.uiLabel ?? "UI 필드")에 '\(String((step.content ?? "").prefix(300)))' 입력"
    case .pressUIElement, .selectMenuItem: "- \(step.uiLabel ?? "UI 요소") 실행"
    default: "- \(step.action.rawValue)"
    }
  }

  func completeCurrentStep(succeeded: Bool, result: String? = nil) {
    guard let id = executingStepID, var executor = planExecutor else { return }
    let position = executor.state.index + 1
    let total = executor.state.plan.steps.count
    guard executor.complete(id, succeeded: succeeded, result: result) else { return }
    planExecutor = executor
    chat.append(.system, "\(position)/\(total) \(succeeded ? "완료" : "실패")")
    advancePlan()
  }

  func failCurrentStep(_ message: String) {
    speak(message, role: .error)
    completeCurrentStep(succeeded: false, result: message)
  }

  private func requestApproval(id: UUID = UUID(), kind: String, title: String, detail: String,
                               request: String, arguments: [String: String]) {
    let action = PendingMacAction(id: id, kind: kind, title: title, detail: detail,
      request: request, arguments: arguments)
    pendingMacAction = action
    chat.appendApproval(id: action.id, content: "\(title)\n\(detail)")
    LearningMemory.record(request: request, action: kind, result: "승인 대기")
    startWakeListening()
  }

  private func interpretMacApproval(_ text: String) {
    let compact = text.replacingOccurrences(of: " ", with: "")
    if ["취소", "그만", "하지마"].contains(where: compact.contains) { cancelMacAction(); return }
    if ["실행", "진행", "승인", "응", "좋아", "그래"].contains(where: compact.contains) { confirmMacAction(); return }
    reply = "실행할지 취소할지 다시 말씀해 주세요."
    startWakeListening()
  }

  func confirmMacAction() {
    guard let action = pendingMacAction else { return }
    if action.kind == AgentAction.createCommit.rawValue,
      action.arguments["gitCommitPlanId"] != gitWorkflowContext.activeCommitPlanId?.uuidString {
      pendingMacAction = nil; failCurrentStep(GitWorkflowError.noActiveCommitPlan.localizedDescription); return
    }
    chat.resolveApproval(id: action.id, state: .approved)
    chat.append(.system, "작업을 승인했습니다. 실행 결과를 기다리는 중입니다.")
    pendingMacAction = nil
    if action.kind == "ui_workflow_preflight" {
      guard planExecutor?.approvePreflight(action.id) == true else {
        failCurrentStep("승인할 UI 실행 계획을 찾지 못했습니다."); return
      }
      advancePlan(); return
    }
    guard planExecutor?.approve(action.id) == true else {
      failCurrentStep("승인할 실행 단계를 찾지 못했습니다.")
      return
    }
    if action.kind == AgentAction.executeCodingTask.rawValue {
      codingTaskProposalLifecycle = .approved
    }
    if action.kind == AgentAction.createCommit.rawValue { gitWorkflowContext.state = .committing }
    if action.kind == AgentAction.pushCurrentBranch.rawValue { gitWorkflowContext.state = .pushing }
    advancePlan()
  }

  func cancelMacAction() {
    guard let action = pendingMacAction else { return }
    let kind = action.kind
    chat.resolveApproval(id: action.id, state: .rejected)
    pendingMacAction = nil
    LearningMemory.record(request: "사용자 취소", action: kind, result: "취소")
    chat.append(.system, "작업을 거절했습니다. Server Agent나 Mac 도구를 호출하지 않았습니다.")
    if kind == "ui_workflow_preflight" {
      if planExecutor?.rejectPreflight(action.id) == true { advancePlan() }
    } else if planExecutor?.reject(action.id) == true {
      if kind == AgentAction.executeCodingTask.rawValue {
        codingTaskProposalLifecycle = .rejected
        activeCodingTaskProposal = nil; activeCodingContinuation = nil
      }
      if kind == AgentAction.executeDevelopmentTask.rawValue {
        Task { await autonomousDevelopment.reject() }
      }
      if kind == AgentAction.createCommit.rawValue { gitWorkflowContext.state = .cancelled }
      if kind == AgentAction.pushCurrentBranch.rawValue { gitWorkflowContext.state = .committed }
      advancePlan()
    }
  }

  func approveChatAction(_ id: UUID) {
    if pendingSkillProposal?.candidate.id == id { saveSkillProposal(); return }
    if pendingMacAction?.id == id { confirmMacAction(); return }
    if pendingKakaoApprovalID == id { confirmKakaoMessage() }
  }

  func rejectChatAction(_ id: UUID) {
    if pendingSkillProposal?.candidate.id == id { rejectSkillProposal(); return }
    if pendingMacAction?.id == id { cancelMacAction(); return }
    if pendingKakaoApprovalID == id { cancelKakaoMessage() }
  }

  private func serverActionLabel(_ operation: String) -> String {
    ["start": "시작", "stop": "중지", "restart": "재시작"][operation] ?? "변경"
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

  private func sendKakao(_ message: KakaoMessage, request: String) {
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

  private func launch(_ application: String, request: String) {
    busy = true
    recordActivity("\(application) 실행")
    Task {
      let message = await MacApplicationLauncher.open(application)
      busy = false
      LearningMemory.record(request: request, action: "open_application", result: message)
      memoryStore.recordAction(request: request, action: "open_application", target: application,
        result: message, succeeded: resultSucceeded(message))
      speak(message)
      completeCurrentStep(succeeded: resultSucceeded(message))
    }
  }

  private func close(_ application: String, request: String) {
    busy = true
    recordActivity("\(application) 종료")
    Task {
      let result = await MacApplicationLauncher.close(application)
      busy = false
      LearningMemory.record(request: request, action: "close_application", result: result)
      memoryStore.recordAction(request: request, action: "close_application", target: application,
        result: result, succeeded: resultSucceeded(result))
      speak(result)
      completeCurrentStep(succeeded: resultSucceeded(result))
    }
  }

  private func search(browser: String, site: String, query: String, request: String) {
    busy = true
    recordActivity("\(browser)에서 \(site) 검색")
    Task {
      let result = await BrowserTools.search(browser: browser, site: site, query: query)
      busy = false
      LearningMemory.record(request: request, action: "browser_search", result: result)
      memoryStore.recordAction(request: request, action: "browser_search", target: "\(browser):\(site)",
        result: result, succeeded: resultSucceeded(result))
      speak(result)
      completeCurrentStep(succeeded: resultSucceeded(result))
    }
  }

  private func openRememberedProject(_ project: String, request: String) {
    do {
      guard let memory = try memoryStore.repository.find(type: .project, key: project) else {
        throw MemoryProjectError.unknownProject(project)
      }
      let url = URL(fileURLWithPath: memory.value).standardizedFileURL
      guard memory.value.hasPrefix("/"), FileManager.default.fileExists(atPath: url.path) else {
        throw MemoryProjectError.invalidPath(memory.value)
      }
      let succeeded = NSWorkspace.shared.open(url)
      let result = succeeded ? "\(project) 프로젝트를 열었습니다." : "\(project) 프로젝트를 열지 못했습니다."
      memoryStore.recordAction(request: request, action: "open_application", target: project,
        result: result, succeeded: succeeded)
      speak(result)
      completeCurrentStep(succeeded: succeeded)
    } catch { failCurrentStep(error.localizedDescription) }
  }

  private func openProject(_ project: String, application: String, request: String) {
    switch ProjectOpeningService.resolve(project: project, application: application,
      repository: memoryStore.repository) {
    case .failure(let error): failCurrentStep(error.localizedDescription)
    case .success(let resolved):
      busy = true
      Task {
        let result = await ProjectOpeningService.open(resolved)
        busy = false
        switch result {
        case .success(let message):
          memoryStore.recordAction(request: request, action: AgentAction.openProject.rawValue,
            target: resolved.project, result: message, succeeded: true)
          speak(message); completeCurrentStep(succeeded: true)
        case .failure(let error):
          memoryStore.recordAction(request: request, action: AgentAction.openProject.rawValue,
            target: resolved.project, result: error.localizedDescription, succeeded: false)
          failCurrentStep(error.localizedDescription)
        }
      }
    }
  }

  func speak(_ text: String, role: ChatRole = .assistant) {
    reply = text
    chat.append(role, text)
  }

  private func resultSucceeded(_ result: String) -> Bool {
    !["실패", "못했습니다", "오류", "필요합니다", "찾지 못"].contains(where: result.contains)
  }

  func recordActivity(_ text: String) {
    activitySteps.append("\(Date.now.formatted(date: .omitted, time: .shortened)) · \(text)")
    if activitySteps.count > 20 { activitySteps.removeFirst(activitySteps.count - 20) }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in
      speechRecoveryTimer?.invalidate()
      startWakeListening()
    }
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
      if let bundleID = LearningStore.applicationBundleID(for: application) {
        process.arguments = ["-b", bundleID]
      } else if let path = installedApplicationPath(named: application) {
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
      let bundleID = LearningStore.applicationBundleID(for: application)
        ?? installedApplicationPath(named: application).flatMap { Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier }
      guard let bundleID,
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
