import type { RunToolApprovalItem } from "@openai/agents";

export type SessionStatus =
  | "idle"
  | "connecting"
  | "connected"
  | "listening"
  | "error";

export interface ActivityItem {
  id: string;
  message: string;
  time: string;
}

export interface ApprovalView {
  title: string;
  detail: string;
  item: RunToolApprovalItem;
}
