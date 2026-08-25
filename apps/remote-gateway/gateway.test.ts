import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { test } from "node:test";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { AegisCommandBridge } from "./bridge.ts";
import { classifyBindHost, loadRemoteConfig } from "./config.ts";
import { RemoteCommandCoordinator } from "./coordinator.ts";
import { createRemoteGateway } from "./server.ts";
import { RemoteDeviceStore } from "./devices.ts";
import type { BridgeCommandResult, RemoteCommandRequest } from "./models.ts";

class FakeBridge implements AegisCommandBridge {
  sends = 0; approvals = 0; cancelled = 0; availableValue = true;
  envelopes: Array<{ sessionId: string; commandId: string }> = [];
  result: BridgeCommandResult = { status: "completed", messages: ["PTFriends 상태입니다."] };
  async available() { return this.availableValue; }
  async health() { return this.availableValue ? "reachable" as const : "unavailable" as const; }
  async send(sessionId: string, commandId: string) {
    this.sends += 1; this.envelopes.push({ sessionId, commandId }); return this.result;
  }
  async resolveApproval() { this.approvals += 1; return { status: "completed" as const, messages: ["완료"] }; }
  async cancel() { this.cancelled += 1; }
  async progress() { return this.result; }
}

const token = "x".repeat(40);
const config = loadRemoteConfig({ AEGIS_REMOTE_ENABLED: "true", AEGIS_REMOTE_HOST: "127.0.0.1",
  AEGIS_REMOTE_TOKEN: token, AEGIS_DESKTOP_BRIDGE_TOKEN: token,
  AEGIS_REMOTE_RATE_LIMIT_PER_MINUTE: "100" });

test("configuration rejects public binding and classifies Tailscale", () => {
  assert.equal(classifyBindHost("100.74.88.48"), "tailscale");
  assert.throws(() => loadRemoteConfig({ AEGIS_REMOTE_ENABLED: "true", AEGIS_REMOTE_HOST: "0.0.0.0",
    AEGIS_REMOTE_TOKEN: token }));
});

test("missing and wrong tokens are rejected without exposing token", async () => {
  await withServer(async url => {
    const missing = await fetch(`${url}/v1/status`);
    const wrong = await fetch(`${url}/v1/status`, { headers: { Authorization: "Bearer wrong" } });
    assert.equal(missing.status, 401); assert.equal(wrong.status, 401);
    assert.equal((await wrong.text()).includes(token), false);
  });
});

test("gateway status distinguishes reachable desktop bridge", async () => {
  await withServer(async url => {
    const response = await get(url, "/v1/status", "phone");
    const status = await response.json() as { gateway?: string; desktopBridge?: string };
    assert.equal(status.gateway, "ready"); assert.equal(status.desktopBridge, "reachable");
  });
});

test("commands are natural-language only and idempotent", async () => {
  const bridge = new FakeBridge();
  await withServer(async url => {
    const raw = await post(url, "/v1/commands", { action: "restartDocker" });
    assert.equal(raw.status, 400);
    const request = command("same");
    assert.equal((await post(url, "/v1/commands", request)).status, 202);
    assert.equal((await post(url, "/v1/commands", request)).status, 202);
    await tick(); assert.equal(bridge.sends, 1);
  }, bridge);
});

test("sessions and command results are isolated by device", async () => {
  await withServer(async url => {
    await post(url, "/v1/commands", command("owned"), "phone-a"); await tick();
    assert.equal((await get(url, "/v1/commands/owned", "phone-a")).status, 200);
    assert.equal((await get(url, "/v1/commands/owned", "phone-b")).status, 404);
    assert.equal((await post(url, "/v1/commands", { ...command("other"), sessionId: "session" }, "phone-b")).status, 403);
  });
});

test("command ids change while conversational session id stays stable", async () => {
  const bridge = new FakeBridge(); const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  await coordinator.submit("phone", command("commit-plan"));
  await coordinator.submit("phone", command("commit-follow-up")); await tick();
  assert.deepEqual(bridge.envelopes, [
    { sessionId: "session", commandId: "commit-plan" },
    { sessionId: "session", commandId: "commit-follow-up" },
  ]);
});

test("approval is owned, resumes once, and duplicate is already resolved", async () => {
  const bridge = new FakeBridge();
  bridge.result = { status: "awaitingApproval", messages: ["승인이 필요합니다."], pendingApproval: {
    id: "approval-1", title: "코드 수정", goal: "작은 문제 수정", risk: "workspaceWrite", scope: "PTFriends" } };
  await withServer(async url => {
    await post(url, "/v1/commands", command("write")); await tick();
    const pending = await get(url, "/v1/commands/write", "phone");
    assert.equal((await pending.json() as { pendingApproval?: { id: string } }).pendingApproval?.id, "approval-1");
    assert.equal((await post(url, "/v1/approvals/approval-1/approve", { sessionId: "session", commandId: "write" }, "other")).status, 404);
    const approved = await post(url, "/v1/approvals/approval-1/approve", { sessionId: "session", commandId: "write" });
    assert.equal(approved.status, 200); assert.equal(bridge.approvals, 1);
    const duplicate = await post(url, "/v1/approvals/approval-1/approve", { sessionId: "session", commandId: "write" });
    assert.equal((await duplicate.json() as { resolution?: string }).resolution, "alreadyResolved");
    assert.equal(bridge.approvals, 1);
  }, bridge);
});

test("expired approval rejects desktop pause instead of leaving it active", async () => {
  const bridge = new FakeBridge(); bridge.result = { status: "awaitingApproval", messages: [],
    pendingApproval: { id: "expired", title: "커밋", goal: "exact plan", risk: "localMutation", scope: "PTFriends" } };
  const coordinator = new RemoteCommandCoordinator(bridge, -1, 3_600_000);
  await coordinator.submit("phone", command("commit")); await tick();
  const result = await coordinator.decide("phone", "session", "commit", "expired", "approve");
  assert.equal(result?.status, "failed"); assert.equal((result as { resolution?: string })?.resolution, "expired");
  assert.equal(bridge.approvals, 1);
});

test("offline desktop returns typed failure and cancellation is not success", async () => {
  const bridge = new FakeBridge(); bridge.availableValue = false;
  const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  await coordinator.submit("phone", command("offline")); await tick();
  const result = coordinator.get("phone", "offline");
  assert.equal(result?.status, "failed"); assert.equal(result?.progress?.phase, "failed");
  assert.deepEqual(result?.messages, ["AegisDesktop에 연결할 수 없습니다."]);
  assert.equal(result?.failureCode, "desktopUnavailable");
});

test("a typed Desktop Bridge failure code is preserved for the client", async () => {
  const bridge = new FakeBridge();
  bridge.result = { status: "failed", messages: ["오류: sol-server에 연결할 수 없습니다."], failureCode: "serverAgentUnavailable" };
  const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  await coordinator.submit("phone", command("server-down")); await tick();
  const result = coordinator.get("phone", "server-down");
  assert.equal(result?.status, "failed"); assert.equal(result?.failureCode, "serverAgentUnavailable");
});

test("cancellation carries the commandCancelled failure code", async () => {
  const bridge = new FakeBridge();
  const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  await coordinator.submit("phone", command("cancel-me")); await tick();
  const cancelled = await coordinator.cancel("phone", "cancel-me");
  assert.equal(cancelled, true);
  assert.equal(coordinator.get("phone", "cancel-me")?.failureCode, "commandCancelled");
});

test("an unrecognized failureCode from the Desktop Bridge is dropped, not forwarded blindly", async () => {
  const bridge = new FakeBridge();
  bridge.result = { status: "failed", messages: ["오류: 알 수 없는 문제"], failureCode: "somethingNewAndUnhandled" };
  const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  await coordinator.submit("phone", command("unknown-code")); await tick();
  assert.equal(coordinator.get("phone", "unknown-code")?.failureCode, undefined);
});

test("an unrecognized status from the Desktop Bridge is treated as failed, not left stuck", async () => {
  const bridge = new FakeBridge();
  bridge.result = { status: "succeeded" as never, messages: ["일부 새로운 상태"] };
  const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  await coordinator.submit("phone", command("enum-drift")); await tick();
  assert.equal(coordinator.get("phone", "enum-drift")?.status, "failed");
});

test("an unrecognized progress phase falls back to running, not to failure", async () => {
  const bridge = new FakeBridge();
  bridge.result = { status: "running", messages: [], progress: { phase: "brandNewPhase" as never,
    cancellable: true, startedAt: new Date().toISOString() } };
  const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  await coordinator.submit("phone", command("phase-drift")); await tick();
  const refreshed = await coordinator.refresh("phone", "phase-drift");
  assert.equal(refreshed?.progress?.phase, "running");
});

test("informational status text (dirty tree, warnings) does not flip a completed command to failed", async () => {
  const bridge = new FakeBridge();
  bridge.result = { status: "completed",
    messages: ["PTFriends 개발 상태", "Working tree: 변경 3개", "참고:", "- 커밋이 필요합니다."] };
  const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  await coordinator.submit("phone", command("dirty-tree-recap")); await tick();
  const result = coordinator.get("phone", "dirty-tree-recap");
  assert.equal(result?.status, "completed");
  assert.equal(result?.messages.join("\n").includes("커밋이 필요합니다"), true);
});

test("provider transcript metadata is removed from remote normal output", async () => {
  const bridge = new FakeBridge();
  bridge.result = { status: "completed", messages: [
    "OpenAI Codex v0.148.0\nsession id: secret\nexec /bin/zsh -lc pwd\n개선점 1개를 찾았습니다.",
  ] };
  const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  await coordinator.submit("phone", command("filtered")); await tick();
  const output = coordinator.get("phone", "filtered")?.messages.join("\n") ?? "";
  assert.equal(output, "개선점 1개를 찾았습니다.");
  assert.equal(output.includes("session id"), false);
});

test("desktop progress is normalized without prompts or provider transcripts", async () => {
  const bridge = new FakeBridge(); bridge.result = { status: "running", messages: [], progress: {
    phase: "coding", message: "Codex가 코드를 수정하고 있습니다...", currentStep: 3,
    totalSteps: 5, cancellable: true, startedAt: new Date().toISOString() } };
  const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  const initial = await coordinator.submit("phone", command("progress"));
  assert.equal(initial.status, "planning"); assert.equal(initial.progress?.phase, "planning");
  await tick(); const refreshed = await coordinator.refresh("phone", "progress");
  assert.equal(refreshed?.progress?.phase, "coding"); assert.equal(refreshed?.progress?.currentStep, 3);
});

test("valid bootstrap registers random hashed device credential", async () => {
  const devices = new RemoteDeviceStore();
  await withServer(async url => {
    const first = await register(url, "Galaxy Fold"); const issued = await first.json() as Registration;
    const second = await register(url, "iPhone"); const other = await second.json() as Registration;
    assert.equal(first.status, 201); assert.equal(issued.credential.length >= 43, true);
    assert.notEqual(issued.credential, other.credential);
    const stored = devices.storedRecordsForTesting()[0];
    assert.equal(stored.name, "Galaxy Fold"); assert.equal(stored.credentialHash.includes(issued.credential), false);
    assert.match(stored.credentialHash, /^scrypt:/);
    assert.equal(JSON.stringify(stored).includes(token), false);
    assert.equal((await deviceGet(url, "/v1/status", issued)).status, 200);
  }, new FakeBridge(), devices);
});

test("invalid registration token and revoked or disabled devices are rejected", async () => {
  const devices = new RemoteDeviceStore();
  await withServer(async url => {
    assert.equal((await fetch(`${url}/v1/devices/register`, { method: "POST",
      headers: { Authorization: "Bearer wrong", "Content-Type": "application/json" }, body: "{}" })).status, 401);
    const issued = await (await register(url, "Phone")).json() as Registration;
    devices.disable(issued.device.id);
    assert.equal((await deviceGet(url, "/v1/status", issued)).status, 401);
    const active = await (await register(url, "Tablet")).json() as Registration;
    assert.equal((await devicePost(url, `/v1/devices/${active.device.id}/revoke`, {}, active)).status, 200);
    assert.equal((await deviceGet(url, "/v1/status", active)).status, 401);
  }, new FakeBridge(), devices);
});

test("registered device ownership keeps sessions approvals and idempotency scoped", async () => {
  const bridge = new FakeBridge(); const devices = new RemoteDeviceStore();
  await withServer(async url => {
    const phone = await (await register(url, "Phone")).json() as Registration;
    const tablet = await (await register(url, "Tablet")).json() as Registration;
    const request = command("device-command");
    await devicePost(url, "/v1/commands", request, phone); await devicePost(url, "/v1/commands", request, phone); await tick();
    assert.equal(bridge.sends, 1);
    assert.equal((await deviceGet(url, "/v1/commands/device-command", phone)).status, 200);
    assert.equal((await deviceGet(url, "/v1/commands/device-command", tablet)).status, 404);
  }, bridge, devices);
});

test("registration has a stricter independent rate limit", async () => {
  const limited = { ...config, registrationRequestsPerMinute: 1 };
  const server = createRemoteGateway(limited, new RemoteCommandCoordinator(new FakeBridge(), 300_000, 3_600_000),
    new RemoteDeviceStore()).listen(0, "127.0.0.1"); await once(server, "listening");
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  try { assert.equal((await register(url, "one")).status, 201); assert.equal((await register(url, "two")).status, 429); }
  finally { server.close(); await once(server, "close"); }
});

test("registered credential survives gateway store restart and master rotation", () => {
  const directory = mkdtempSync(join(tmpdir(), "aegis-devices-"));
  try {
    const path = join(directory, "devices.json");
    const issued = new RemoteDeviceStore(path).register("Persistent Phone");
    const restarted = new RemoteDeviceStore(path);
    assert.equal(restarted.authenticate(issued.device.id, issued.credential)?.name, "Persistent Phone");
    assert.equal(restarted.storedRecordsForTesting()[0].credentialHash.includes(issued.credential), false);
  } finally { rmSync(directory, { recursive: true }); }
});

test("frequent authentication does not persist lastSeenAt on every request", () => {
  const directory = mkdtempSync(join(tmpdir(), "aegis-devices-"));
  try {
    const path = join(directory, "devices.json");
    const store = new RemoteDeviceStore(path);
    const issued = store.register("Polling Phone");
    const registeredAt = store.storedRecordsForTesting()[0].lastSeenAt;

    store.authenticate(issued.device.id, issued.credential);
    store.authenticate(issued.device.id, issued.credential);

    assert.equal(store.storedRecordsForTesting()[0].lastSeenAt, registeredAt);
    assert.equal(new RemoteDeviceStore(path).storedRecordsForTesting()[0].lastSeenAt, registeredAt);
  } finally { rmSync(directory, { recursive: true }); }
});

function command(id: string): RemoteCommandRequest {
  return { id, sessionId: "session", text: "PTFriends 어디까지 했지?", timestamp: new Date().toISOString() };
}
async function tick() { await new Promise(resolve => setTimeout(resolve, 10)); }

interface Registration { device: { id: string; name: string }; credential: string }
function register(url: string, name: string) { return fetch(`${url}/v1/devices/register`, { method: "POST",
  headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify({ name }) }); }
function deviceGet(url: string, path: string, value: Registration) { return fetch(url + path,
  { headers: { Authorization: `Device ${value.credential}`, "X-Aegis-Device-ID": value.device.id } }); }
function devicePost(url: string, path: string, body: object, value: Registration) { return fetch(url + path, { method: "POST",
  headers: { Authorization: `Device ${value.credential}`, "X-Aegis-Device-ID": value.device.id,
    "Content-Type": "application/json" }, body: JSON.stringify(body) }); }

async function withServer(run: (url: string) => Promise<void>, bridge = new FakeBridge(),
                          devices = new RemoteDeviceStore()) {
  const coordinator = new RemoteCommandCoordinator(bridge, 300_000, 3_600_000);
  const server = createRemoteGateway(config, coordinator, devices).listen(0, "127.0.0.1"); await once(server, "listening");
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  try { await run(url); } finally { server.close(); await once(server, "close"); }
}
function post(url: string, path: string, body: object, device = "phone") {
  return fetch(url + path, { method: "POST", headers: { Authorization: `Bearer ${token}`,
    "X-Aegis-Device-ID": device, "Content-Type": "application/json" }, body: JSON.stringify(body) });
}
function get(url: string, path: string, device: string) {
  return fetch(url + path, { headers: { Authorization: `Bearer ${token}`, "X-Aegis-Device-ID": device } });
}
