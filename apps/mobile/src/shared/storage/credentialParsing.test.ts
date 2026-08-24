import assert from "node:assert/strict";
import test from "node:test";
import { parseDeviceCredential, parseRecoverableCommand } from "./credentialParsing";

test("accepts a well-formed device credential and rejects malformed/partial payloads", () => {
  const value = { deviceId: "d1", deviceName: "Phone", credential: "secret" };
  assert.deepEqual(parseDeviceCredential(JSON.stringify(value)), value);
  assert.equal(parseDeviceCredential(JSON.stringify({ deviceId: "d1" })), undefined);
  assert.equal(parseDeviceCredential("not-json"), undefined);
});

test("accepts a well-formed recoverable command and rejects malformed/partial payloads", () => {
  const value = { commandId: "c1", sessionId: "s1", startedAt: "2026-08-23T00:00:00.000Z" };
  assert.deepEqual(parseRecoverableCommand(JSON.stringify(value)), value);
  assert.equal(parseRecoverableCommand(JSON.stringify({ commandId: "c1" })), undefined);
  assert.equal(parseRecoverableCommand("not-json"), undefined);
});
