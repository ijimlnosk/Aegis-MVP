import AVFoundation
import AppKit
import Foundation

@MainActor
final class AegisAgent: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
  let voiceInputEnabled = false
  let chat = ChatStore()
  let memoryStore = MemoryStore()
  let conversationEvents = ConversationEventStore()
  let skillStore = SkillStore()
  let screenInspector = ScreenInspector()
  let visibleWindows = VisibleWindowService()
  let accessibility = AccessibilityService()
  let uiCoordinator = UIInteractionCoordinator()
  let codingCoordinator = CodingTaskCoordinator()
  let codingProviders = CodingAgentProviderPool()
  let autonomousDevelopment = AutonomousDevelopmentCoordinator()
  let desktopBridge = DesktopBridgeServer()
  let keepAwake = RemoteKeepAwake()
  /// Set on bridge-session agents so diagnostics report the listening server, not this unstarted one.
  var desktopBridgeStatus: (() -> String)?
  lazy var developmentSessions = DevelopmentSessionCoordinator(memory: memoryStore.repository)
  lazy var proactiveCoordinator = ProactiveCoordinator(memory: memoryStore.repository)
  lazy var contextObserver = ContextObserver { [weak self] in
    guard let self else { return }
    let notices = await self.proactiveCoordinator.observe()
    self.surface(notices)
  }
  @Published var reply = "Aegis가 준비되었습니다."
  @Published var busy = false { didSet { scheduleTimingFinish() } }
  @Published var listening = false
  @Published var transcript = ""
  @Published var heardText = ""
  @Published var commandListening = false
  @Published var pendingKakaoMessage: KakaoMessage? { didSet { scheduleTimingFinish() } }
  @Published var pendingMacAction: PendingMacAction? { didSet { scheduleTimingFinish() } }
  var requestTiming: RequestTimingTracker?
  var timingStore = RequestTimingStore.standard
  @Published var sampleStatus = ""
  @Published var activitySteps = ["호출어 대기 중"]
  @Published var hasWakeCandidate = false
  private let speaker = AVSpeechSynthesizer()
  let speech = SpeechInput()
  let sampleRecorder = WakeSampleRecorder()
  var commandActive = false
  var wakeTranscript = ""
  var wakeCheckInFlight = false
  var wakeCandidateURL: URL?
  var lastWakeCheck = Date.distantPast
  var lastCommandText = ""
  var lastKakaoApprovalText = ""
  var pendingKakaoApprovalID: UUID?
  var planExecutor: AgentPlanExecutor?
  var recentUIWindowTarget: ResolvedWindowTarget?
  var activeSkill: LearnedSkill?
  var pendingSkillProposal: PendingSkillProposal?
  var ignoredSkillPatterns: Set<SkillPattern> = []
  var executingStepID: UUID?
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
  var activeConversationTurnID: UUID?
  var remoteSessionID: String?
  var remoteCommandID: String?
  var remoteRequestText: String?
  /// When the current phone command began; long ones get a push when they finish.
  var remoteCommandStartedAt: Date?
  let pushNotifier = PushNotifier()
  var developerValidationResults: [String: [ProjectValidationCheck: ProjectValidationResult]] = [:]
  private var started = false
  private var terminationObserver: NSObjectProtocol?
  var silenceTimer: Timer?
  private var speechRecoveryTimer: Timer?
  let finishWords = ["답변해", "대답해", "응답해"]
  private let speechVolume: Float = 0.45
  var hasActiveBackgroundWork: Bool { busy || desktopBridge.hasActiveCommands }

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
    desktopBridge.sharedAgent = self
    desktopBridge.start()
    keepAwake.start()
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in Task { @MainActor in self?.stop() } }
  }

  func stop() {
    contextObserver.stop()
    desktopBridge.stop()
    keepAwake.stop()
    if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    terminationObserver = nil
    codingFindings.removeAll(); activeCodingContinuation = nil
    activeCodingTaskProposal = nil; codingTaskProposalLifecycle = nil
  }

  /// Entry point for the Mac window and voice; clears remote tags left by a phone command.
  func sendFromDesktop(_ text: String) {
    remoteSessionID = nil; remoteCommandID = nil; remoteRequestText = nil; remoteCommandStartedAt = nil
    send(text)
  }

  func speak(_ text: String, role: ChatRole = .assistant) {
    reply = text
    chat.append(role, text)
    scheduleTimingFinish()
    if let turn = activeConversationTurnID {
      conversationEvents.appendResponse(text, turnId: turn)
      conversationEvents.setStatus(role == .error ? "failed" : "responded", turnId: turn)
    }
  }

  func resultSucceeded(_ result: String) -> Bool {
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
