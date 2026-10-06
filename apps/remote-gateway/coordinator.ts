import type { AegisCommandBridge } from "./bridge.ts";
import type { RemoteAuditEntry, RemoteCommandRequest, RemoteCommandResponse, RemoteCommandStatus,
  RemoteFailureCode, RemoteProgressPhase } from "./models.ts";

interface StoredCommand { owner: string; request: RemoteCommandRequest; response: RemoteCommandResponse;
  controller: AbortController; startedAt: string }
interface Session { owner: string; expiresAt: number }

export class RemoteCommandCoordinator {
  private readonly commands = new Map<string, StoredCommand>();
  private readonly sessions = new Map<string, Session>();
  private readonly approvals = new Map<string, { commandId: string; owner: string; resolved: boolean; expiresAt: number }>();
  private readonly audit: RemoteAuditEntry[] = [];
  private readonly bridge: AegisCommandBridge;
  private readonly approvalTtlMs: number;
  private readonly sessionTtlMs: number;
  constructor(bridge: AegisCommandBridge, approvalTtlMs: number, sessionTtlMs: number) {
    this.bridge = bridge; this.approvalTtlMs = approvalTtlMs; this.sessionTtlMs = sessionTtlMs;
  }

  async submit(owner: string, request: RemoteCommandRequest): Promise<RemoteCommandResponse> {
    const duplicate = this.commands.get(request.id);
    if (duplicate) return duplicate.owner === owner ? duplicate.response : forbidden();
    this.claimSession(owner, request.sessionId);
    const startedAt = new Date().toISOString();
    const stored: StoredCommand = { owner, request, controller: new AbortController(), startedAt,
      response: { commandId: request.id, status: "planning", messages: [], progress: {
        phase: "planning", cancellable: true, startedAt } } };
    this.commands.set(request.id, stored);
    void this.run(stored);
    return stored.response;
  }

  get(owner: string, commandId: string) {
    const value = this.commands.get(commandId);
    return value?.owner === owner ? value.response : undefined;
  }

  async refresh(owner: string, commandId: string) {
    const stored = this.commands.get(commandId);
    if (!stored || stored.owner !== owner) return undefined;
    if (stored.response.status === "awaitingApproval" && stored.response.pendingApproval) return stored.response;
    if (["completed", "failed", "cancelled"].includes(stored.response.status)) return stored.response;
    try { const result = await this.bridge.progress(stored.request.sessionId, commandId);
      stored.response = this.normalize(commandId, result, stored.startedAt); } catch { /* keep last known state */ }
    return stored.response;
  }

  async decide(owner: string, sessionId: string, commandId: string, approvalId: string,
               decision: "approve" | "reject") {
    const approval = this.approvals.get(approvalId);
    const stored = this.commands.get(commandId);
    if (!approval || !stored || approval.owner !== owner || approval.commandId !== commandId ||
        stored.request.sessionId !== sessionId) return undefined;
    if (approval.resolved) return { ...stored.response, resolution: "alreadyResolved" };
    if (Date.now() >= approval.expiresAt) {
      approval.resolved = true;
      await this.bridge.resolveApproval(sessionId, commandId, approvalId, "reject").catch(() => undefined);
      stored.response = { commandId, status: "failed", messages: ["승인 시간이 만료되어 실행하지 않았습니다."],
        failureCode: "approvalExpired" };
      this.record(stored, "expired"); return { ...stored.response, resolution: "expired" };
    }
    approval.resolved = true;
    stored.response = { commandId, status: "running", messages: stored.response.messages,
      progress: { phase: "running", message: decision === "approve" ? "승인된 작업을 진행하고 있습니다..." : "거절을 처리하고 있습니다...",
        cancellable: true, startedAt: stored.startedAt } };
    const result = await this.bridge.resolveApproval(sessionId, commandId, approvalId, decision);
    stored.response = this.normalize(commandId, result, stored.startedAt);
    this.record(stored, decision === "approve" ? "approved" : "rejected");
    return stored.response;
  }

  async cancel(owner: string, commandId: string) {
    const stored = this.commands.get(commandId);
    if (!stored || stored.owner !== owner) return false;
    stored.controller.abort(); await this.bridge.cancel(stored.request.sessionId, commandId).catch(() => undefined);
    stored.response = { commandId, status: "cancelled", messages: ["작업을 취소했습니다."],
      progress: { phase: "cancelled", cancellable: false, startedAt: stored.startedAt },
      failureCode: "commandCancelled" };
    this.record(stored); return true;
  }

  status() {
    const values = [...this.commands.values()];
    return { activeSessions: this.sessions.size,
      pendingApprovals: values.filter(value => value.response.status === "awaitingApproval").length,
      lastRemoteActivity: this.audit.at(-1)?.timestamp ?? null };
  }

  diagnostics() { return this.audit.slice(-20); }
  desktopBridgeStatus() { return this.bridge.health(); }
  desktopScreenLocked() { return this.bridge.lastScreenLocked ?? null; }

  private async run(stored: StoredCommand) {
    try {
      if (!await this.bridge.available()) throw new Error("aegisUnavailable");
      stored.response = { commandId: stored.request.id, status: "running", messages: [],
        progress: { phase: "running", cancellable: true, startedAt: stored.startedAt } };
      const result = await this.bridge.send(stored.request.sessionId, stored.request.id,
        stored.request.text, stored.controller.signal);
      stored.response = this.normalize(stored.request.id, result, stored.startedAt);
      const pending = stored.response.pendingApproval;
      if (pending) this.approvals.set(pending.id, { commandId: stored.request.id, owner: stored.owner,
        resolved: false, expiresAt: Date.parse(pending.expiresAt) });
      if (["completed", "failed", "cancelled"].includes(stored.response.status)) this.record(stored);
    } catch (error) {
      const cancelled = stored.controller.signal.aborted;
      const desktopUnreachable = error instanceof Error && error.message === "aegisUnavailable";
      stored.response = { commandId: stored.request.id, status: cancelled ? "cancelled" : "failed",
        messages: [cancelled ? "작업을 취소했습니다." :
          desktopUnreachable ? "AegisDesktop에 연결할 수 없습니다." : "원격 명령 처리에 실패했습니다."],
        progress: { phase: cancelled ? "cancelled" : "failed", cancellable: false, startedAt: stored.startedAt },
        failureCode: cancelled ? "commandCancelled" : desktopUnreachable ? "desktopUnavailable" : "internalError" };
      this.record(stored);
    }
  }

  private normalize(commandId: string, result: Awaited<ReturnType<AegisCommandBridge["send"]>>,
                    startedAt: string) {
    const messages = result.messages.map(sanitizeMessage).filter(Boolean).slice(-20);
    const status = normalizeStatus(result.status);
    const phase = normalizePhase(result.progress?.phase ?? (status === "verifying" ? "validating" : status));
    const progress = result.progress ? { ...result.progress, phase } :
      { phase, cancellable: !["completed", "failed", "cancelled"].includes(status), startedAt };
    const failureCode = normalizeFailureCode(result.failureCode);
    if (!result.pendingApproval) return { commandId, status, messages, progress, failureCode };
    const expiresAt = new Date(Date.now() + this.approvalTtlMs).toISOString();
    return { commandId, status: "awaitingApproval" as const, messages,
      progress: { ...progress, phase: "awaitingApproval" as const, cancellable: false },
      pendingApproval: { ...result.pendingApproval, expiresAt } };
  }

  private claimSession(owner: string, id: string) {
    const current = this.sessions.get(id);
    if (current && current.expiresAt > Date.now() && current.owner !== owner) throw new Error("sessionForbidden");
    this.sessions.set(id, { owner, expiresAt: Date.now() + this.sessionTtlMs });
  }

  private record(stored: StoredCommand, approval?: RemoteAuditEntry["approval"]) {
    this.audit.push({ commandId: stored.request.id, deviceId: stored.owner,
      requestSummary: stored.request.text.replace(/\s+/g, " ").slice(0, 160),
      outcome: stored.response.status as RemoteCommandStatus, approval, timestamp: new Date().toISOString() });
    if (this.audit.length > 200) this.audit.shift();
  }
}

function sanitizeMessage(value: string) {
  const forbidden = /(?:session id:|workdir:|sandbox:|approval:|OpenAI Codex v|Reading additional input|^exec\b|\/bin\/(?:zsh|bash|sh)\s+-lc)/i;
  return value.split("\n").filter(line => !forbidden.test(line)).join("\n").trim().slice(0, 8_000);
}

function forbidden(): RemoteCommandResponse {
  return { commandId: "forbidden", status: "failed", messages: ["다른 장치의 명령에는 접근할 수 없습니다."] };
}

const KNOWN_STATUSES: readonly string[] = ["queued", "planning", "running", "awaitingApproval",
  "verifying", "completed", "failed", "cancelled"];
const KNOWN_PHASES: readonly string[] = ["queued", "planning", "running", "analyzing", "coding",
  "validating", "repairing", "gitPlanning", "committing", "pushing", "screenAnalyzing",
  "serverChecking", "awaitingApproval", "completed", "failed", "cancelled"];
const KNOWN_FAILURE_CODES: readonly string[] = ["desktopUnavailable", "plannerFailed", "projectUnavailable",
  "serverAgentUnavailable", "codingAgentUnavailable", "validationFailed", "approvalExpired",
  "commandCancelled", "timeout", "internalError"];

// Defends against a Desktop Bridge/Gateway enum drift (e.g. a newer AegisDesktop build
// adding a status this Gateway doesn't know yet): an unrecognized status is treated as
// failed rather than left to poll forever in an unhandled non-terminal state.
function normalizeStatus(value: string): RemoteCommandStatus {
  return KNOWN_STATUSES.includes(value) ? value as RemoteCommandStatus : "failed";
}
// An unrecognized progress phase is presentational-only -- fall back to "running"
// rather than misreading it as a terminal/failure state.
function normalizePhase(value: string): RemoteProgressPhase {
  return KNOWN_PHASES.includes(value) ? value as RemoteProgressPhase : "running";
}
function normalizeFailureCode(value?: string): RemoteFailureCode | undefined {
  return value !== undefined && KNOWN_FAILURE_CODES.includes(value) ? value as RemoteFailureCode : undefined;
}
