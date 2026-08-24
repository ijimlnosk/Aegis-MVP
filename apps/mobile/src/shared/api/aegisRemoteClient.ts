import type { RemoteCommand } from "@/entities/command/model/types";
import type { DeviceCredential, DeviceRegistration } from "@/entities/device/model/types";
import type { GatewayStatus } from "@/entities/connection/model/types";
import { normalizeGatewayURL } from "@/shared/lib/gatewayURL";
import { RemoteError, errorMessage } from "./remoteError";
import { classifyGatewayStatus } from "./classifyGatewayStatus";

export class AegisRemoteClient {
  constructor(private readonly gatewayURL: string, private readonly device?: DeviceCredential) {}

  static async register(gateway: string, masterToken: string, name: string) {
    const url = normalizeGatewayURL(gateway);
    return request<DeviceRegistration>(url, "/v1/devices/register", {
      method: "POST", headers: masterHeaders(masterToken), body: JSON.stringify({ name: name.trim() || undefined }),
    });
  }

  // Deliberately callable before registration: with no device credential this
  // sends an unauthenticated probe, and a 401 deviceCredentialInvalid response
  // still proves the Gateway itself is reachable (see classifyGatewayStatus).
  status() {
    const headers = this.device ? deviceHeaders(this.device) : { "Content-Type": "application/json" };
    return request<GatewayStatus>(this.gatewayURL, "/v1/status", { headers });
  }
  command(id: string) { return this.authenticated<RemoteCommand>(`/v1/commands/${encodeURIComponent(id)}`); }
  send(id: string, sessionId: string, text: string) {
    return this.authenticated<RemoteCommand>("/v1/commands", { method: "POST",
      body: JSON.stringify({ id, sessionId, text, timestamp: new Date().toISOString() }) });
  }
  approve(commandId: string, sessionId: string, approvalId: string, accepted: boolean) {
    const decision = accepted ? "approve" : "reject";
    return this.authenticated<RemoteCommand>(`/v1/approvals/${encodeURIComponent(approvalId)}/${decision}`,
      { method: "POST", body: JSON.stringify({ commandId, sessionId }) });
  }
  cancel(commandId: string) {
    return this.authenticated<{ status: string }>(`/v1/commands/${encodeURIComponent(commandId)}/cancel`, { method: "POST" });
  }
  revoke() { return this.authenticated<{ status: string }>(`/v1/devices/${this.device?.deviceId}/revoke`, { method: "POST" }); }

  private authenticated<T>(path: string, init: RequestInit = {}) {
    if (!this.device) throw new RemoteError("deviceCredentialInvalid", errorMessage("deviceCredentialInvalid"));
    return request<T>(this.gatewayURL, path, { ...init, headers: { ...deviceHeaders(this.device), ...init.headers } });
  }
}

async function request<T>(gateway: string, path: string, init: RequestInit) {
  let response: Response;
  try { response = await fetch(`${normalizeGatewayURL(gateway)}${path}`, init); }
  catch { throw new RemoteError("gatewayUnavailable", errorMessage("gatewayUnavailable")); }
  const body = await response.json().catch(() => ({})) as T & { error?: string };
  const code = classifyGatewayStatus(response.status, body.error);
  if (code) throw new RemoteError(code, errorMessage(code));
  return body;
}
function deviceHeaders(value: DeviceCredential) { return { Authorization: `Device ${value.credential}`,
  "X-Aegis-Device-ID": value.deviceId, "Content-Type": "application/json" }; }
function masterHeaders(value: string) { return { Authorization: `Bearer ${value}`, "Content-Type": "application/json" }; }
