import assert from "node:assert/strict";
import test from "node:test";
import { connectionDiagnostics } from "./diagnostics";

test("connected reports every layer healthy", () => {
  const value = connectionDiagnostics("connected");
  assert.equal(value.gateway, "reachable"); assert.equal(value.authentication, "connected");
  assert.equal(value.desktopBridge, "reachable");
});

test("desktopUnavailable distinguishes desktop bridge from gateway/auth", () => {
  const value = connectionDiagnostics("desktopUnavailable");
  assert.equal(value.gateway, "reachable"); assert.equal(value.authentication, "connected");
  assert.equal(value.desktopBridge, "unavailable");
});

test("gatewayUnavailable marks every layer unreachable/unknown, not just auth", () => {
  const value = connectionDiagnostics("gatewayUnavailable");
  assert.equal(value.gateway, "연결 안 됨"); assert.equal(value.desktopBridge, "확인 불가");
});
