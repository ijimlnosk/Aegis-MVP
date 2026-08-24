export type RemoteCommandStatus = "queued" | "planning" | "running" |
  "awaitingApproval" | "verifying" | "completed" | "failed" | "cancelled";
export type RemoteProgressPhase = "queued" | "planning" | "running" | "analyzing" | "coding" |
  "validating" | "repairing" | "gitPlanning" | "committing" | "pushing" |
  "screenAnalyzing" | "serverChecking" | "awaitingApproval" | "completed" | "failed" | "cancelled";

export interface RemoteCommandProgress {
  phase: RemoteProgressPhase;
  message?: string;
  currentStep?: number;
  totalSteps?: number;
  cancellable: boolean;
  startedAt: string;
}

export interface RemoteCommandRequest {
  id: string;
  sessionId: string;
  text: string;
  timestamp: string;
}

export interface RemoteApprovalCard {
  id: string;
  title: string;
  goal: string;
  risk: string;
  scope: string;
  expiresAt: string;
}

// Bounded, typed failure category for status "failed"/"cancelled" -- lets clients
// show why instead of a generic message. "desktopUnavailable" is set by the Gateway
// itself (the Desktop Bridge is unreachable); the rest come from AegisDesktop.
export type RemoteFailureCode = "desktopUnavailable" | "plannerFailed" | "projectUnavailable" |
  "serverAgentUnavailable" | "codingAgentUnavailable" | "validationFailed" | "approvalExpired" |
  "commandCancelled" | "timeout" | "internalError";

export interface RemoteCommandResponse {
  commandId: string;
  status: RemoteCommandStatus;
  messages: string[];
  pendingApproval?: RemoteApprovalCard;
  progress?: RemoteCommandProgress;
  failureCode?: RemoteFailureCode;
}

export interface RemoteDevice {
  id: string;
  name: string;
  credentialHash: string;
  createdAt: string;
  lastSeenAt: string;
  enabled: boolean;
  revokedAt?: string;
}

export type RemoteDeviceView = Omit<RemoteDevice, "credentialHash">;

export interface BridgeCommandResult {
  status: RemoteCommandStatus;
  messages: string[];
  pendingApproval?: Omit<RemoteApprovalCard, "expiresAt">;
  progress?: RemoteCommandProgress;
  failureCode?: string;
}

export interface RemoteAuditEntry {
  commandId: string;
  deviceId: string;
  requestSummary: string;
  outcome: RemoteCommandStatus;
  approval?: "approved" | "rejected" | "expired";
  timestamp: string;
}
