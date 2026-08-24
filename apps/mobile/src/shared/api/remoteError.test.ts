import assert from "node:assert/strict";
import test from "node:test";
import { requiresReRegistration, errorMessage } from "./remoteError";

test("only invalid/revoked/disabled device-credential codes trigger clearing the stored credential", () => {
  assert.equal(requiresReRegistration("deviceCredentialInvalid"), true);
  assert.equal(requiresReRegistration("deviceRevoked"), true);
  assert.equal(requiresReRegistration("deviceDisabled"), true);
  assert.equal(requiresReRegistration("authenticationFailed"), false);
  assert.equal(requiresReRegistration("gatewayServerError"), false);
  assert.equal(requiresReRegistration("gatewayUnavailable"), false);
  assert.equal(requiresReRegistration("desktopUnavailable"), false);
});

test("gatewayUnavailable message points at Tailscale, not at authentication", () => {
  assert.match(errorMessage("gatewayUnavailable"), /Tailscale/);
  assert.doesNotMatch(errorMessage("deviceCredentialInvalid"), /Tailscale/);
});

test("each auth-shaped code has a distinct, non-generic message", () => {
  assert.equal(errorMessage("deviceCredentialInvalid"), "기기 등록이 필요합니다.");
  assert.equal(errorMessage("deviceRevoked"), "이 기기의 원격 연결이 해제되었습니다.");
  assert.notEqual(errorMessage("deviceCredentialInvalid"), errorMessage("gatewayUnavailable"));
});
