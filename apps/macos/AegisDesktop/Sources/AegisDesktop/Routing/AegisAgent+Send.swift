import Foundation

extension AegisAgent {
  func send(_ text: String) {
    let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return }
    activeConversationTurnID = conversationEvents.begin(sessionId: conversationSessionID, request: message)
    chat.append(.user, message)
    // Slash commands are excluded so /perf and /status do not skew the timing data they report.
    if let slash = SlashCommandResolver.resolve(message,
      projects: ProjectEntityResolver.knownProjects(repository: memoryStore.repository),
      timings: { [timingStore] in timingStore.recent() }) {
      runSlashCommand(slash, request: message); return
    }
    requestTiming = RequestTimingTracker(source: remoteCommandID == nil ? "desktop" : "remote", request: message)
    if routeImmediate(message) { return }
    // Computed before routing because coding continuation may clear the findings it depends on.
    let followUp = SemanticRouter.followUp(for: message, hasCodingFindings: !codingFindings.isEmpty)?.kind
    if routeValidationFollowUp(followUp, message: message) { return }
    if routeCodingContinuation(followUp, message: message) { return }
    if routeLocalIntent(message) { return }
    planWithBackend(message)
  }

  /// Policy refusals, pending approvals, and confirmations take priority over any new intent.
  private func routeImmediate(_ message: String) -> Bool {
    if CodingAgentProviderPolicy.rejects(message) {
      speak(CodingAgentProviderPolicy.unsupportedMessage); return true
    }
    if let proactiveIntent = ProactiveIntentParser.parse(message) {
      speak(handleProactiveIntent(proactiveIntent)); return true
    }
    if let remotePlan = RemoteControlIntentResolver.plan(for: message) {
      execute(remotePlan, request: message); return true
    }
    if pendingKakaoMessage != nil { interpretKakaoApproval(message); return true }
    if pendingMacAction != nil { interpretMacApproval(message); return true }
    if ProjectDiscoveryConfirmationParser.isConfirmation(message) {
      if let discovery = pendingProjectDiscovery {
        let result = memoryStore.handle(.remember(type: .project, key: discovery.name, value: discovery.path))
        pendingProjectDiscovery = nil
        speak(result)
      } else {
        speak("먼저 \"<프로젝트> 위치 찾아줘\"라고 말씀해 주시면 경로를 찾아드릴게요.")
      }
      return true
    }
    if let continuation = GitWorkflowContinuationResolver.resolve(message,
      repository: memoryStore.repository, context: &gitWorkflowContext) {
      switch continuation {
      case .plan(let plan): execute(plan, request: message)
      case .message(let value): speak(value)
      }
      return true
    }
    return false
  }
}
