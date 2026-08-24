import assert from "node:assert/strict";
import test from "node:test";
import { AegisRemoteClient } from "./aegisRemoteClient";
import { RemoteError } from "./remoteError";

const gateway = "https://kims-macbook-pro.tailabbdd3.ts.net";
const device = { deviceId: "00000000-0000-4000-8000-000000000001", deviceName: "Phone", credential: "device-secret" };

function withFetch<T>(handler: typeof fetch, run: () => Promise<T>) {
  const original = globalThis.fetch; globalThis.fetch = handler;
  return run().finally(() => { globalThis.fetch = original; });
}

test("registration uses master token once and returns server credential", async () => {
  let authorization = "";
  await withFetch(async (_input, init) => { authorization = new Headers(init?.headers).get("Authorization") ?? "";
    return Response.json({ device: { id: device.deviceId, name: "iPhone" }, credential: "server-secret" }, { status: 201 }); },
  async () => { const result = await AegisRemoteClient.register(gateway, "master", "iPhone");
    assert.equal(authorization, "Bearer master"); assert.equal(result.credential, "server-secret"); });
});

test("commands use device identity, exact URL, and preserve command/session IDs", async () => {
  let body = ""; let authorization = ""; let url = "";
  await withFetch(async (input, init) => { url = String(input); body = String(init?.body);
    authorization = new Headers(init?.headers).get("Authorization") ?? "";
    return Response.json({ commandId: "command-2", status: "queued", messages: [] }, { status: 202 }); },
  async () => { const client = new AegisRemoteClient(gateway, device);
    await client.send("command-2", "session-1", "그거 고쳐줘");
    assert.equal(authorization, "Device device-secret");
    assert.equal(url, "https://kims-macbook-pro.tailabbdd3.ts.net/v1/commands");
    assert.deepEqual(JSON.parse(body), { id: "command-2", sessionId: "session-1", text: "그거 고쳐줘", timestamp: JSON.parse(body).timestamp }); });
});

test("200 status resolves as connected (no error thrown)", async () => {
  await withFetch(async () => Response.json({ gateway: "ready", desktopBridge: "reachable", pendingApprovals: 0 }, { status: 200 }),
    async () => { const status = await new AegisRemoteClient(gateway, device).status();
      assert.equal(status.desktopBridge, "reachable"); });
});

test("401 deviceCredentialInvalid: Gateway is reachable, not gatewayUnavailable", async () => {
  await withFetch(async () => Response.json({ error: "deviceCredentialInvalid" }, { status: 401 }), async () => {
    await assert.rejects(new AegisRemoteClient(gateway, device).status(),
      (error: unknown) => error instanceof RemoteError && error.code === "deviceCredentialInvalid");
  });
});

test("401 deviceRevoked classifies as deviceRevoked", async () => {
  await withFetch(async () => Response.json({ error: "deviceRevoked" }, { status: 401 }), async () => {
    await assert.rejects(new AegisRemoteClient(gateway, device).status(),
      (error: unknown) => error instanceof RemoteError && error.code === "deviceRevoked");
  });
});

test("401 deviceDisabled classifies as deviceDisabled", async () => {
  await withFetch(async () => Response.json({ error: "deviceDisabled" }, { status: 401 }), async () => {
    await assert.rejects(new AegisRemoteClient(gateway, device).status(),
      (error: unknown) => error instanceof RemoteError && error.code === "deviceDisabled");
  });
});

test("403 classifies as authenticationFailed, not gatewayUnavailable", async () => {
  await withFetch(async () => Response.json({}, { status: 403 }), async () => {
    await assert.rejects(new AegisRemoteClient(gateway, device).status(),
      (error: unknown) => error instanceof RemoteError && error.code === "authenticationFailed");
  });
});

test("500 classifies as gatewayServerError, not gatewayUnavailable", async () => {
  await withFetch(async () => Response.json({}, { status: 500 }), async () => {
    await assert.rejects(new AegisRemoteClient(gateway, device).status(),
      (error: unknown) => error instanceof RemoteError && error.code === "gatewayServerError");
  });
});

test("fetch throwing (real network failure) is the only path to gatewayUnavailable", async () => {
  await withFetch(async () => { throw new TypeError("Network request failed"); }, async () => {
    await assert.rejects(new AegisRemoteClient(gateway, device).status(),
      (error: unknown) => error instanceof RemoteError && error.code === "gatewayUnavailable");
  });
});

test("status() works unauthenticated (no device) so registration stays available after a 401 probe", async () => {
  await withFetch(async () => Response.json({ error: "deviceCredentialInvalid" }, { status: 401 }), async () => {
    const probe = new AegisRemoteClient(gateway);
    await assert.rejects(probe.status(), (error: unknown) => error instanceof RemoteError && error.code === "deviceCredentialInvalid");
  });
  // registration itself must still be reachable right after that 401 probe
  await withFetch(async () => Response.json({ device: { id: device.deviceId, name: "Phone" }, credential: "fresh-secret" }, { status: 201 }),
    async () => { const result = await AegisRemoteClient.register(gateway, "master", "Phone");
      assert.equal(result.credential, "fresh-secret"); });
});

test("successful registration, then a status retry, resolves connected", async () => {
  const result = await withFetch(
    async () => Response.json({ device: { id: device.deviceId, name: "Phone" }, credential: "fresh-secret" }, { status: 201 }),
    () => AegisRemoteClient.register(gateway, "master", "Phone"));
  const registered = { deviceId: result.device.id, deviceName: result.device.name, credential: result.credential };
  await withFetch(async () => Response.json({ gateway: "ready", desktopBridge: "reachable", pendingApprovals: 0 }, { status: 200 }), async () => {
    const status = await new AegisRemoteClient(gateway, registered).status();
    assert.equal(status.desktopBridge, "reachable");
  });
});
