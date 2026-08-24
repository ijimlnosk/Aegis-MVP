import assert from "node:assert/strict";
import test from "node:test";
import { elapsedText, pollDelay, progressLabel, reconnectDelay } from "./progress";

test("maps backend progress without exposing internal enum text", () => {
  assert.equal(progressLabel("coding"), "Codex가 코드를 수정하고 있습니다...");
  assert.equal(progressLabel("validating"), "변경사항을 검증하고 있습니다...");
  assert.equal(progressLabel("awaitingApproval"), "승인을 기다리고 있습니다.");
});

test("an unrecognized (newer-backend) phase falls back to the running presentation, not failure", () => {
  assert.equal(progressLabel("brandNewPhaseThisBuildDoesNotKnow"), "작업을 진행하고 있습니다...");
});

test("formats elapsed time and backs polling off", () => {
  assert.equal(elapsedText(78), "1분 18초");
  assert.equal(pollDelay(1, false), 1_000);
  assert.equal(pollDelay(35, false), 3_000);
  assert.equal(pollDelay(1, true), 3_000);
});

test("reconnect backoff grows then stays bounded -- never a tight retry loop", () => {
  assert.equal(reconnectDelay(1), 3_000);
  assert.equal(reconnectDelay(2), 5_000);
  assert.equal(reconnectDelay(3), 10_000);
  assert.equal(reconnectDelay(4), 15_000);
  assert.equal(reconnectDelay(50), 15_000);
});
