import assert from "node:assert/strict";
import test from "node:test";
import { gatewayDiagnostics } from "./gatewayDiagnostics";

test("no diagnostics while idle or still checking", () => {
  assert.equal(gatewayDiagnostics("idle", true), undefined);
  assert.equal(gatewayDiagnostics("checking", true), undefined);
});

test("deviceCredentialInvalid reports the Gateway reachable and auth needing registration", () => {
  const value = gatewayDiagnostics("deviceCredentialInvalid", true);
  assert.equal(value?.gateway, "연결됨");
  assert.equal(value?.https, "정상");
  assert.equal(value?.authentication, "기기 등록 필요");
});

test("gatewayUnavailable reports the Gateway as unreachable, not an auth problem", () => {
  const value = gatewayDiagnostics("gatewayUnavailable", true);
  assert.equal(value?.gateway, "연결 안 됨");
});

test("diagnostics never surface any raw value that looks like a token", () => {
  const values = Object.values(gatewayDiagnostics("connected", true) ?? {});
  for (const value of values) assert.equal(/[a-f0-9]{20,}/i.test(value), false);
});
