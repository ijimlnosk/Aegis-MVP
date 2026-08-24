import type { BridgeCommandResult } from "./models.ts";

export interface AegisCommandBridge {
  health(): Promise<"reachable" | "unavailable" | "unauthorized">;
  available(): Promise<boolean>;
  send(sessionId: string, commandId: string, text: string, signal: AbortSignal): Promise<BridgeCommandResult>;
  resolveApproval(sessionId: string, commandId: string, approvalId: string,
                  decision: "approve" | "reject"): Promise<BridgeCommandResult>;
  cancel(sessionId: string, commandId: string): Promise<void>;
  progress(sessionId: string, commandId: string): Promise<BridgeCommandResult>;
}

export class DesktopHTTPBridge implements AegisCommandBridge {
  private readonly baseURL: URL;
  private readonly token: string;
  constructor(baseURL: URL, token: string) { this.baseURL = baseURL; this.token = token; }

  async available() {
    return await this.health() === "reachable";
  }

  async health(): Promise<"reachable" | "unavailable" | "unauthorized"> {
    try {
      const response = await fetch(new URL("/health", this.baseURL), {
        headers: this.headers(), signal: AbortSignal.timeout(1500),
      });
      if (response.status === 401) return "unauthorized";
      if (!response.ok) return "unavailable";
      const body = await response.json() as { status?: unknown; service?: unknown };
      return body.status === "ok" && body.service === "AegisDesktopBridge" ? "reachable" : "unavailable";
    } catch { return "unavailable"; }
  }

  send(sessionId: string, commandId: string, text: string, signal: AbortSignal) {
    return this.post("/v1/commands", { sessionId, commandId, text }, signal);
  }

  resolveApproval(sessionId: string, commandId: string, approvalId: string,
                  decision: "approve" | "reject") {
    return this.post(`/v1/approvals/${encodeURIComponent(approvalId)}/${decision}`,
      { sessionId, commandId }, AbortSignal.timeout(10_000));
  }

  async cancel(sessionId: string, commandId: string) {
    await this.post(`/v1/commands/${encodeURIComponent(commandId)}/cancel`, { sessionId }, AbortSignal.timeout(10_000));
  }

  progress(sessionId: string, commandId: string) {
    return this.post(`/v1/commands/${encodeURIComponent(commandId)}/status`,
      { sessionId, commandId }, AbortSignal.timeout(3_000));
  }

  private async post(path: string, body: object, signal: AbortSignal): Promise<BridgeCommandResult> {
    const response = await fetch(new URL(path, this.baseURL), {
      method: "POST", headers: this.headers(), body: JSON.stringify(body), signal,
    });
    if (!response.ok) throw new Error(response.status === 503 ? "aegisUnavailable" : "Aegis command bridge request failed");
    return response.json() as Promise<BridgeCommandResult>;
  }

  private headers() { return { "Authorization": `Bearer ${this.token}`, "Content-Type": "application/json" }; }
}
