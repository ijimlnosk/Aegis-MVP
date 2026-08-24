import assert from "node:assert/strict";
import { test } from "node:test";
import { createConnectionController, createDeviceAuthController, createId,
  compatibleStorage, DEVICE_CREDENTIAL_KEY, formatElapsed, friendlyProgressLabel,
  initializeRemoteUI, pollingDelay } from "./mobile-client.js";

test("createId uses randomUUID when available", () => {
  assert.equal(createId({ randomUUID: () => "native-id" }), "native-id");
});

test("createId securely falls back to getRandomValues", () => {
  const id = createId({ getRandomValues(bytes) { bytes.fill(7); return bytes; } });
  assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(id, "07070707-0707-4707-8707-070707070707");
});

test("createId uses a bounded non-security fallback without Web Crypto", () => {
  assert.match(createId({}), /^compat-[a-z0-9]+-[a-z0-9]+$/);
});

test("connection reports empty token without fetching", async () => {
  let calls = 0; const states = [];
  const controller = createConnectionController(async () => { calls += 1; }, value => states.push(value));
  assert.equal((await controller.connect("", () => ({}))).kind, "emptyToken");
  assert.equal(calls, 0); assert.deepEqual(states, ["emptyToken"]);
});

test("connection distinguishes success, 401, and network failure", async () => {
  const states = [];
  const success = createConnectionController(async () => ({ status: 200, ok: true }), value => states.push(value));
  assert.equal((await success.connect("token", () => ({}))).kind, "connected");
  const unauthorized = createConnectionController(async () => ({ status: 401, ok: false }), () => undefined);
  assert.equal((await unauthorized.connect("token", () => ({}))).kind, "unauthorized");
  const failure = createConnectionController(async () => { throw new Error("offline"); }, () => undefined);
  assert.equal((await failure.connect("token", () => ({}))).kind, "networkError");
});

test("duplicate connection attempt is ignored while request is running", async () => {
  let release; const pending = new Promise(resolve => { release = resolve; });
  const controller = createConnectionController(async () => { await pending; return { status: 200, ok: true }; }, () => undefined);
  const first = controller.connect("token", () => ({}));
  assert.equal((await controller.connect("token", () => ({}))).kind, "duplicate");
  release(); assert.equal((await first).kind, "connected");
});

test("insecure HTTP initializes even without crypto subtle or persistent storage", async () => {
  const elements = new Map(["state", "client-error", "connect", "history", "composer", "token", "auth",
    "device-name", "device-status", "current-device", "disconnect", "message"]
    .map(id => [id, fakeElement()]));
  const documentAPI = { getElementById: id => elements.get(id), createElement: () => fakeElement(), body: { scrollHeight: 0 } };
  const unavailableStorage = { getItem() { throw new Error("SecurityError"); }, setItem() { throw new Error("SecurityError"); }, removeItem() {} };
  const result = initializeRemoteUI(documentAPI, {}, async (path) => path === "/v1/devices/register"
    ? response(201, { device: { id: "11111111-1111-4111-8111-111111111111", name: "Phone" }, credential: "c".repeat(43) })
    : response(200, {}), unavailableStorage);
  assert.equal(result.initialized, true); assert.equal(elements.get("connect").disabled, false);
  elements.get("token").value = "master"; await elements.get("connect").listeners.click();
  assert.equal(elements.get("composer").hidden, false);
  assert.match(elements.get("client-error").textContent, /이번 세션에서만/);
});

test("new client remains compatible with gateway HTML loaded before device UI upgrade", async () => {
  const elements = new Map(["state", "client-error", "connect", "history", "composer", "token", "auth", "message"]
    .map(id => [id, fakeElement()]));
  const documentAPI = { getElementById: id => elements.get(id), createElement: () => fakeElement(), body: { scrollHeight: 0 } };
  const result = initializeRemoteUI(documentAPI, {}, async path => path === "/v1/devices/register"
    ? response(201, { device: { id: "11111111-1111-4111-8111-111111111111", name: "Remote Device 1" }, credential: "c".repeat(43) })
    : response(200, {}), fakeStorage());
  assert.equal(result.initialized, true); assert.equal(typeof elements.get("connect").listeners.click, "function");
  elements.get("token").value = "master"; await elements.get("connect").listeners.click();
  assert.equal(elements.get("composer").hidden, false);
});

test("registration stores only device credential and returning device auto authenticates", async () => {
  const storage = fakeStorage(); const states = []; let registrationAuthorization = "";
  const fetchImpl = async (path, options = {}) => {
    if (path === "/v1/devices/register") { registrationAuthorization = options.headers.Authorization;
      return response(201, { device: { id: "11111111-1111-4111-8111-111111111111", name: "Galaxy" }, credential: "c".repeat(43) }); }
    return response(200, {});
  };
  const auth = createDeviceAuthController(fetchImpl, storage, value => states.push(value));
  assert.equal((await auth.register("Galaxy", "master-secret")).kind, "connected");
  const persisted = storage.getItem(DEVICE_CREDENTIAL_KEY);
  assert.equal(persisted.includes("master-secret"), false);
  assert.equal(registrationAuthorization, "Bearer master-secret");
  assert.equal((await createDeviceAuthController(fetchImpl, storage, () => {}).autoConnect()).kind, "connected");
});

test("invalid or locally deleted credential returns to registration", async () => {
  const storage = fakeStorage(); storage.setItem(DEVICE_CREDENTIAL_KEY,
    JSON.stringify({ id: "11111111-1111-4111-8111-111111111111", name: "Phone", credential: "c".repeat(43) }));
  const auth = createDeviceAuthController(async () => response(401, {}), storage, () => {});
  assert.equal((await auth.autoConnect()).kind, "credentialInvalid");
  assert.equal(storage.getItem(DEVICE_CREDENTIAL_KEY), null);
});

test("device revoke deletes browser credential even if gateway is unavailable", async () => {
  const storage = fakeStorage(); storage.setItem(DEVICE_CREDENTIAL_KEY,
    JSON.stringify({ id: "11111111-1111-4111-8111-111111111111", name: "Phone", credential: "c".repeat(43) }));
  const auth = createDeviceAuthController(async () => { throw new Error("offline"); }, storage, () => {});
  await assert.rejects(auth.revokeCurrent()); assert.equal(storage.getItem(DEVICE_CREDENTIAL_KEY), null);
});

test("manual master-token compatibility remains usable when registration and storage fail", async () => {
  const storage = compatibleStorage({ getItem() { throw new Error("denied"); },
    setItem() { throw new Error("denied"); }, removeItem() {} });
  const calls = [];
  const auth = createDeviceAuthController(async path => { calls.push(path);
    return path === "/v1/devices/register" ? response(404, {}) : response(200, {}); }, storage, () => {});
  const result = await auth.register("Phone", "master-only-memory");
  assert.equal(result.kind, "connected"); assert.equal(result.sessionOnly, true);
  assert.equal(auth.headers().Authorization, "Bearer master-only-memory");
  assert.equal(storage.getItem(DEVICE_CREDENTIAL_KEY), null);
});

test("friendly progress states never expose raw enum names", () => {
  const expected = { queued: "작업을 준비", planning: "계획", running: "작업을 진행", analyzing: "코드를 분석",
    coding: "Codex", validating: "검증", repairing: "검증 오류", gitPlanning: "커밋 계획",
    committing: "커밋을 생성", pushing: "원격 저장소", screenAnalyzing: "화면",
    serverChecking: "서버 상태", awaitingApproval: "승인", cancelled: "취소" };
  for (const [phase, text] of Object.entries(expected)) assert.match(friendlyProgressLabel(phase), new RegExp(text));
});

test("elapsed time and active polling backoff are local and bounded", () => {
  assert.equal(formatElapsed(8), "8초 경과"); assert.equal(formatElapsed(78), "1분 18초 경과");
  assert.equal(pollingDelay(1), 1000); assert.equal(pollingDelay(15), 2000);
  assert.equal(pollingDelay(40), 3000); assert.equal(pollingDelay(1, true), 3000);
});

test("progress card appears before command submission resolves and blocks duplicate submit", async () => {
  const elements = allElements(); const documentAPI = fakeDocument(elements); const storage = fakeStorage();
  storage.setItem(DEVICE_CREDENTIAL_KEY, JSON.stringify({ id: "11111111-1111-4111-8111-111111111111",
    name: "Phone", credential: "c".repeat(43) }));
  let release; const pending = new Promise(resolve => { release = resolve; });
  initializeRemoteUI(documentAPI, {}, async path => {
    if (path === "/v1/status") return response(200, {});
    if (path === "/v1/commands") { await pending; return response(202, {}); }
    return response(200, { status: "completed", messages: ["완료"] });
  }, storage);
  await Promise.resolve(); elements.get("message").value = "긴 작업";
  const first = elements.get("composer").listeners.submit({ preventDefault() {} });
  assert.equal(elements.get("history").children.some(value => value.className === "card progress-card"), true);
  assert.equal(elements.get("send").disabled, true);
  elements.get("message").value = "중복"; await elements.get("composer").listeners.submit({ preventDefault() {} });
  assert.equal(elements.get("state").textContent, "현재 작업이 진행 중입니다."); release(); await first;
});

function fakeElement() {
  const listeners = {};
  return { textContent: "", value: "", hidden: false, disabled: false, listeners, children: [], style: {},
    addEventListener(name, callback) { listeners[name] = callback; }, append(...values) { this.children.push(...values); }, remove() {} };
}
function allElements() { return new Map(["state", "client-error", "connect", "history", "composer", "token", "auth",
  "device-name", "device-status", "current-device", "disconnect", "message", "send"].map(id => [id, fakeElement()])); }
function fakeDocument(elements) { return { getElementById: id => elements.get(id), createElement: () => fakeElement(), body: { scrollHeight: 0 } }; }
function fakeStorage() { const values = new Map(); return { getItem: key => values.get(key) ?? null,
  setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) }; }
function response(status, body) { return { status, ok: status >= 200 && status < 300, async json() { return body; } }; }
