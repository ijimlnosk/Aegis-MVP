import { createHash, timingSafeEqual } from "node:crypto";
import type { IncomingMessage } from "node:http";
import type { RemoteDeviceStore } from "./devices.ts";

export interface RemoteIdentity { deviceId: string; fingerprint: string }

export function authenticateMaster(request: IncomingMessage, token: string): RemoteIdentity | undefined {
  const header = request.headers.authorization;
  if (!header?.startsWith("Bearer ")) return undefined;
  const supplied = Buffer.from(header.slice(7));
  const expected = Buffer.from(token);
  if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return undefined;
  const requestedId = String(request.headers["x-aegis-device-id"] ?? "default");
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(requestedId)) return undefined;
  return { deviceId: requestedId, fingerprint: createHash("sha256").update(token).digest("hex").slice(0, 16) };
}

export function authenticate(request: IncomingMessage, token: string,
                             devices: RemoteDeviceStore): RemoteIdentity | undefined {
  return authenticateRequest(request, token, devices).identity;
}

export function authenticateRequest(request: IncomingMessage, token: string,
                                    devices: RemoteDeviceStore): { identity?: RemoteIdentity; error?: string } {
  const header = request.headers.authorization;
  const requestedId = String(request.headers["x-aegis-device-id"] ?? "");
  if (header?.startsWith("Device ") && /^[0-9a-f-]{36}$/.test(requestedId)) {
    const result = devices.authenticateResult(requestedId, header.slice(7));
    return result.device ? { identity: { deviceId: result.device.id, fingerprint: "registered" } }
      : { error: result.error };
  }
  const identity = authenticateMaster(request, token);
  return identity ? { identity } : { error: "deviceCredentialInvalid" };
}
