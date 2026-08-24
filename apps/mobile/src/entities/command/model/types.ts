export type CommandStatus = "queued" | "planning" | "running" | "awaitingApproval" |
  "verifying" | "completed" | "failed" | "cancelled";
export type ProgressPhase = "queued" | "planning" | "running" | "analyzing" | "coding" |
  "validating" | "repairing" | "gitPlanning" | "committing" | "pushing" |
  "screenAnalyzing" | "serverChecking" | "awaitingApproval" | "completed" | "failed" | "cancelled";
// Bounded, typed failure category for status "failed"/"cancelled" -- see failureMessages.ts.
export type CommandFailureCode = "desktopUnavailable" | "plannerFailed" | "projectUnavailable" |
  "serverAgentUnavailable" | "codingAgentUnavailable" | "validationFailed" | "approvalExpired" |
  "commandCancelled" | "timeout" | "internalError";

export interface CommandProgress {
  phase: ProgressPhase;
  message?: string;
  currentStep?: number;
  totalSteps?: number;
  cancellable: boolean;
  startedAt: string;
}

export interface RemoteCommand {
  commandId: string;
  status: CommandStatus;
  messages: string[];
  progress?: CommandProgress;
  pendingApproval?: import("../../approval/model/types").RemoteApproval;
  failureCode?: CommandFailureCode;
}
