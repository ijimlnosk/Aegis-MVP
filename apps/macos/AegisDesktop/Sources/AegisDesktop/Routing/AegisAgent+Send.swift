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
    let semanticFollowUp = SemanticRouter.followUp(for: message,
      hasCodingFindings: !codingFindings.isEmpty)
    if semanticFollowUp?.kind == .detailedLint {
      busy = true
      Task {
        let latest = await codingCoordinator.lastResult
        let saved = conversationEvents.latestValidationResponse(
          sessionId: conversationSessionID, excluding: activeConversationTurnID)
        let project = ProjectEntityResolver.resolve(in: message, repository: memoryStore.repository)
          ?? latest.flatMap {
            ProjectEntityResolver.resolve(name: $0.project, repository: memoryStore.repository)
          } ?? saved.flatMap {
            ProjectEntityResolver.resolve(in: $0, repository: memoryStore.repository)
          }
        busy = false
        guard let project else {
          speak("어느 프로젝트의 lint 경고를 조사할지 프로젝트명을 말씀해 주세요.")
          return
        }
        execute(CodingResultFollowUpResolver.detailedLintPlan(request: message,
          project: project.name), request: message)
      }
      return
    }
    if semanticFollowUp?.kind == .fixValidation {
      busy = true
      Task {
        let latest = await codingCoordinator.lastResult
        let saved = conversationEvents.latestValidationResponse(
          sessionId: conversationSessionID, excluding: activeConversationTurnID)
        let project = ProjectEntityResolver.resolve(in: message, repository: memoryStore.repository)
          ?? latest.flatMap {
          ProjectEntityResolver.resolve(name: $0.project, repository: memoryStore.repository)
        } ?? saved.flatMap {
          ProjectEntityResolver.resolve(in: $0, repository: memoryStore.repository)
        }
        busy = false
        guard let project else {
          speak("어느 프로젝트의 검증 문제를 수정할지 프로젝트명을 말씀해 주세요.")
          return
        }
        execute(CodingResultFollowUpResolver.fixPlan(request: message, project: project.name),
          request: message)
      }
      return
    }
    if semanticFollowUp?.kind == .explainValidation {
      busy = true
      Task {
        let result = await codingCoordinator.lastResult
        busy = false
        if let result {
          speak(CodingTaskFormatter.validationExplanation(result))
        } else if let saved = conversationEvents.latestValidationResponse(
          sessionId: conversationSessionID, excluding: activeConversationTurnID) {
          if let project = ProjectEntityResolver.resolve(in: saved, repository: memoryStore.repository),
            let root = try? ProjectCommandPolicy.projectURL(project.name,
              repository: memoryStore.repository) {
            let report = ProjectValidationService.run(project: project.name, root: root,
              repository: memoryStore.repository)
            speak(CodingTaskFormatter.validationExplanation(project: project.name,
              checks: report.checks))
          } else {
            speak("최근 저장 기록 기준입니다.\n\n\(saved)")
          }
        } else {
          speak("최근 코드 수정 검증 결과가 없습니다.")
        }
      }
      return
    }
    let explicitCodingProject = ProjectEntityResolver.resolve(in: message,
      repository: memoryStore.repository)
    if let project = explicitCodingProject,
      !codingFindings.isEmpty, !codingFindings.contains(where: { $0.projectId == project.name.lowercased() }) {
      codingFindings.removeAll(); activeCodingContinuation = nil
    }
    if semanticFollowUp?.kind == .codingContinuation,
      let continuation = CodingContinuationIntentResolver.resolve(message,
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
        if let candidate = SemanticRouter.candidate(for: message,
          repository: memoryStore.repository, gitContext: gitWorkflowContext) {
          let decision: SemanticRouteDecision
          do {
            decision = try await SemanticRouter.classify(message, candidate: candidate,
              gitContext: gitWorkflowContext)
          } catch {
            busy = false
            speak(SemanticRouter.failureMessage(for: candidate), role: .error)
            return
          }
          busy = false
          switch decision {
          case .developer(let project, let developer):
            switch DeveloperSemanticResolver.resolve(developer, request: message, project: project,
              repository: memoryStore.repository) {
            case .plan(let plan): execute(plan, request: message)
            case .message(let value): speak(value)
            }
          case .gitWorkflow(let git):
            if let continuation = GitWorkflowSemanticResolver.resolve(git, request: message,
              repository: memoryStore.repository, context: &gitWorkflowContext) {
              switch continuation {
              case .plan(let plan): execute(plan, request: message)
              case .message(let value): speak(value)
              }
            } else {
              speak("커밋 후속 요청을 이해하지 못했습니다. 요청을 더 구체적으로 말씀해 주세요.")
            }
          }
          return
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
        let plan = try await AgentPlanner.plan(for: message, memory: memory,
          metrics: requestTiming?.planner)
        busy = false
        execute(plan, request: message)
      } catch {
        busy = false
        speak(error.localizedDescription, role: .error)
      }
    }
  }
}
