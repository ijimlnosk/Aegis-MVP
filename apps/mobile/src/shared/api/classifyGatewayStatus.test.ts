import assert from "node:assert/strict";
import test from "node:test";
import { classifyGatewayStatus } from "./classifyGatewayStatus";

test("2xx never becomes an error code", () => {
  assert.equal(classifyGatewayStatus(200), undefined);
  assert.equal(classifyGatewayStatus(202), undefined);
});

test("401 without a recognized body defaults to deviceCredentialInvalid", () => {
  assert.equal(classifyGatewayStatus(401), "deviceCredentialInvalid");
  assert.equal(classifyGatewayStatus(401, "deviceCredentialInvalid"), "deviceCredentialInvalid");
});

test("401 with a device-specific body wins over the generic 401 mapping", () => {
  assert.equal(classifyGatewayStatus(401, "deviceRevoked"), "deviceRevoked");
  assert.equal(classifyGatewayStatus(401, "deviceDisabled"), "deviceDisabled");
});

test("403 is authenticationFailed, not gatewayUnavailable", () => {
  assert.equal(classifyGatewayStatus(403), "authenticationFailed");
});

test("5xx is gatewayServerError, not gatewayUnavailable", () => {
  assert.equal(classifyGatewayStatus(500), "gatewayServerError");
  assert.equal(classifyGatewayStatus(503), "gatewayServerError");
});

test("an unexpected 4xx never becomes gatewayUnavailable (a response was actually received)", () => {
  assert.notEqual(classifyGatewayStatus(404), "gatewayUnavailable");
  assert.notEqual(classifyGatewayStatus(409), "gatewayUnavailable");
});
