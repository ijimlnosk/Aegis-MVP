export type ChatRole = "user" | "assistant" | "system" | "error";
export interface RemoteChatMessage {
  id: string;
  role: ChatRole;
  content: string;
  createdAt: string;
  commandId?: string;
  status?: string;
}
