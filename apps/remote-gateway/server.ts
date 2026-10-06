import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { authenticateMaster, authenticateRequest } from "./auth.ts";
import { DesktopHTTPBridge } from "./bridge.ts";
import { classifyBindHost, loadRemoteConfig, type RemoteGatewayConfig } from "./config.ts";
import { RemoteCommandCoordinator } from "./coordinator.ts";
import { mobileHTML } from "./mobile.ts";
import { readFileSync } from "node:fs";
import { RateLimiter } from "./rateLimit.ts";
import { RemoteDeviceStore } from "./devices.ts";
import type { RemoteCommandRequest } from "./models.ts";

export function createRemoteGateway(config: RemoteGatewayConfig,
                                    coordinator = new RemoteCommandCoordinator(new DesktopHTTPBridge(config.desktopURL, config.desktopToken),
                                      config.approvalTtlSeconds * 1000, config.sessionTtlSeconds * 1000),
                                    devices = new RemoteDeviceStore(config.deviceStorePath)) {
  const limiter = new RateLimiter(config.requestsPerMinute);
  const registrationLimiter = new RateLimiter(config.registrationRequestsPerMinute);
  return createServer(async (request, response) => {
    if (request.method === "GET" && request.url === "/") return html(response, mobileHTML);
    if (request.method === "GET" && request.url === "/mobile-client.js") {
      return javascript(response, readFileSync(new URL("./mobile-client.js", import.meta.url), "utf8"));
    }
    const url = new URL(request.url ?? "/", "http://gateway");
    if (request.method === "POST" && url.pathname === "/v1/devices/register") {
      const source = request.socket.remoteAddress ?? "unknown";
      if (!registrationLimiter.accept(source)) return json(response, 429, { error: "registrationRateLimited" });
      if (!authenticateMaster(request, config.token)) return json(response, 401, { error: "registrationTokenInvalid" });
      try {
        const body = await readJSON(request, 1000) as { name?: unknown };
        if (body.name !== undefined && typeof body.name !== "string") return json(response, 400, { error: "invalidDeviceName" });
        return json(response, 201, devices.register(body.name));
      } catch { return json(response, 400, { error: "invalidRequest" }); }
    }
    const authentication = authenticateRequest(request, config.token, devices);
    if (!authentication.identity) return json(response, 401,
      { error: authentication.error ?? "deviceCredentialInvalid" });
    const identity = authentication.identity;
    const owner = `${identity.fingerprint}:${identity.deviceId}`;
    if (!limiter.accept(owner)) return json(response, 429, { error: "rateLimited" });
    try {
      if (request.method === "GET" && url.pathname === "/v1/status") {
        const desktopBridge = await coordinator.desktopBridgeStatus();
        return json(response, 200, { enabled: config.enabled, reachable: true,
          gateway: "ready", desktopBridge, screenLocked: coordinator.desktopScreenLocked(), bind: classifyBindHost(config.host), port: config.port,
          ...coordinator.status() });
      }
      if (request.method === "GET" && url.pathname === "/v1/devices") {
        return json(response, 200, { devices: devices.list() });
      }
      const deviceMatch = url.pathname.match(/^\/v1\/devices\/([^/]+)\/revoke$/);
      if (request.method === "POST" && deviceMatch) {
        const target = decodeURIComponent(deviceMatch[1]);
        if (target !== identity.deviceId) return json(response, 403, { error: "deviceOwnershipRequired" });
        return devices.revoke(target) ? json(response, 200, { status: "revoked" })
          : json(response, 401, { error: "deviceCredentialInvalid" });
      }
      const commandMatch = url.pathname.match(/^\/v1\/commands\/([^/]+)$/);
      if (request.method === "GET" && commandMatch) {
        const result = await coordinator.refresh(owner, decodeURIComponent(commandMatch[1]));
        return result ? json(response, 200, result) : json(response, 404, { error: "notFound" });
      }
      if (request.method === "POST" && url.pathname === "/v1/commands") {
        const body = await readJSON(request, config.maxCommandChars + 1000) as Partial<RemoteCommandRequest> & { action?: unknown };
        if (body.action !== undefined || !validCommand(body, config.maxCommandChars)) return json(response, 400, { error: "invalidNaturalLanguageCommand" });
        const result = await coordinator.submit(owner, body);
        return json(response, 202, result);
      }
      const approvalMatch = url.pathname.match(/^\/v1\/approvals\/([^/]+)\/(approve|reject)$/);
      if (request.method === "POST" && approvalMatch) {
        const body = await readJSON(request, 2000) as { sessionId?: unknown; commandId?: unknown };
        if (typeof body.sessionId !== "string" || typeof body.commandId !== "string") return json(response, 400, { error: "invalidApproval" });
        const result = await coordinator.decide(owner, body.sessionId, body.commandId,
          decodeURIComponent(approvalMatch[1]), approvalMatch[2] as "approve" | "reject");
        return result ? json(response, 200, result) : json(response, 404, { error: "notFound" });
      }
      const cancelMatch = url.pathname.match(/^\/v1\/commands\/([^/]+)\/cancel$/);
      if (request.method === "POST" && cancelMatch) {
        const ok = await coordinator.cancel(owner, decodeURIComponent(cancelMatch[1]));
        return json(response, ok ? 200 : 404, { status: ok ? "cancelled" : "notFound" });
      }
      return json(response, 404, { error: "notFound" });
    } catch (error) {
      const message = error instanceof Error && error.message === "sessionForbidden" ? "sessionForbidden" : "invalidRequest";
      return json(response, message === "sessionForbidden" ? 403 : 400, { error: message });
    }
  });
}

function validCommand(value: Partial<RemoteCommandRequest>, max: number): value is RemoteCommandRequest {
  return typeof value.id === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value.id) &&
    typeof value.sessionId === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value.sessionId) &&
    typeof value.text === "string" && value.text.trim().length > 0 && value.text.length <= max &&
    typeof value.timestamp === "string" && Number.isFinite(Date.parse(value.timestamp));
}

async function readJSON(request: IncomingMessage, maxBytes: number) {
  const chunks: Buffer[] = []; let size = 0;
  for await (const chunk of request) { const buffer = Buffer.from(chunk); size += buffer.length;
    if (size > maxBytes) throw new Error("tooLarge"); chunks.push(buffer); }
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

function json(response: ServerResponse, status: number, value: object) {
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff", "Content-Security-Policy": "default-src 'none'" });
  response.end(JSON.stringify(value));
}
function html(response: ServerResponse, value: string) {
  response.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'self'; style-src 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'" });
  response.end(value);
}
function javascript(response: ServerResponse, value: string) {
  response.writeHead(200, { "Content-Type": "text/javascript; charset=utf-8", "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff" }); response.end(value);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const config = loadRemoteConfig();
  if (!config.enabled) console.log("Aegis Remote Gateway disabled (AEGIS_REMOTE_ENABLED=false)");
  else createRemoteGateway(config).listen(config.port, config.host,
    () => console.log(`Aegis Remote Gateway listening on ${config.host}:${config.port} (${classifyBindHost(config.host)})`));
}
