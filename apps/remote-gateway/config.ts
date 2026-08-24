import { readFileSync } from "node:fs";
import { join } from "node:path";

export interface RemoteGatewayConfig {
  enabled: boolean;
  host: string;
  port: number;
  token: string;
  maxCommandChars: number;
  approvalTtlSeconds: number;
  sessionTtlSeconds: number;
  requestsPerMinute: number;
  desktopURL: URL;
  desktopToken: string;
  deviceStorePath: string;
  registrationRequestsPerMinute: number;
}

type Environment = Record<string, string | undefined>;

export function loadRemoteConfig(env: Environment = process.env): RemoteGatewayConfig {
  const enabled = env.AEGIS_REMOTE_ENABLED === "true";
  const host = env.AEGIS_REMOTE_HOST?.trim() || "127.0.0.1";
  if (enabled && !isPrivateBindHost(host)) throw new Error("AEGIS_REMOTE_HOST는 loopback 또는 private/Tailscale 주소여야 합니다.");
  const token = env.AEGIS_REMOTE_TOKEN ?? "";
  if (enabled && token.length < 32) throw new Error("AEGIS_REMOTE_TOKEN은 32자 이상의 강한 토큰이어야 합니다.");
  const desktopToken = env.AEGIS_DESKTOP_BRIDGE_TOKEN ?? loadDesktopBridgeToken();
  if (enabled && desktopToken.length < 32) throw new Error("AEGIS_DESKTOP_BRIDGE_TOKEN은 32자 이상이어야 합니다.");
  return {
    enabled, host, token,
    port: integer(env.AEGIS_REMOTE_PORT, 8790, 1024, 65535, "AEGIS_REMOTE_PORT"),
    maxCommandChars: integer(env.AEGIS_REMOTE_MAX_COMMAND_CHARS, 4000, 1, 20_000, "AEGIS_REMOTE_MAX_COMMAND_CHARS"),
    approvalTtlSeconds: integer(env.AEGIS_REMOTE_APPROVAL_TTL_SECONDS, 300, 30, 3600, "AEGIS_REMOTE_APPROVAL_TTL_SECONDS"),
    sessionTtlSeconds: integer(env.AEGIS_REMOTE_SESSION_TTL_SECONDS, 3600, 60, 86_400, "AEGIS_REMOTE_SESSION_TTL_SECONDS"),
    requestsPerMinute: integer(env.AEGIS_REMOTE_RATE_LIMIT_PER_MINUTE, 30, 1, 300, "AEGIS_REMOTE_RATE_LIMIT_PER_MINUTE"),
    registrationRequestsPerMinute: integer(env.AEGIS_REMOTE_REGISTRATION_RATE_LIMIT_PER_MINUTE,
      5, 1, 30, "AEGIS_REMOTE_REGISTRATION_RATE_LIMIT_PER_MINUTE"),
    deviceStorePath: env.AEGIS_REMOTE_DEVICE_STORE_PATH?.trim() || defaultDeviceStorePath(),
    desktopURL: localBridgeURL(env.AEGIS_DESKTOP_COMMAND_URL ?? "http://127.0.0.1:8791"), desktopToken,
  };
}

function defaultDeviceStorePath() {
  const home = process.env.HOME;
  return home ? join(home, "Library", "Application Support", "Aegis", "remote-devices.json") : "remote-devices.json";
}

function loadDesktopBridgeToken() {
  try {
    const home = process.env.HOME;
    if (!home) return "";
    return readFileSync(join(home, "Library", "Application Support", "Aegis", "desktop-bridge.token"), "utf8").trim();
  } catch { return ""; }
}

export function classifyBindHost(host: string): "loopback" | "tailscale" | "private" | "unsafe" {
  if (["127.0.0.1", "::1", "localhost"].includes(host)) return "loopback";
  const parts = host.split(".").map(Number);
  if (parts.length !== 4 || parts.some(Number.isNaN)) return "unsafe";
  if (parts[0] === 100 && parts[1] >= 64 && parts[1] <= 127) return "tailscale";
  if (parts[0] === 10 || (parts[0] === 192 && parts[1] === 168) ||
      (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31)) return "private";
  return "unsafe";
}

export const isPrivateBindHost = (host: string) => classifyBindHost(host) !== "unsafe";

function integer(value: string | undefined, fallback: number, min: number, max: number, name: string) {
  const result = Number(value ?? fallback);
  if (!Number.isInteger(result) || result < min || result > max) throw new Error(`${name} 설정이 올바르지 않습니다.`);
  return result;
}

function localBridgeURL(raw: string) {
  const url = new URL(raw);
  if (url.protocol !== "http:" || !["127.0.0.1", "::1", "localhost"].includes(url.hostname)) {
    throw new Error("AEGIS_DESKTOP_COMMAND_URL은 loopback HTTP 주소여야 합니다.");
  }
  return url;
}
