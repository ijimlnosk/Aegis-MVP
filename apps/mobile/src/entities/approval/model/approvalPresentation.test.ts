import assert from "node:assert/strict";
import test from "node:test";
import { presentApproval, remainingText } from "./approvalPresentation";

test("outward actions get a specific verb and are marked irreversible", () => {
  assert.deepEqual([presentApproval("kakao_message").confirmLabel, presentApproval("kakao_message").irreversible], ["보내기", true]);
  assert.equal(presentApproval("push_current_branch").confirmLabel, "Push");
  assert.equal(presentApproval("create_commit").irreversible, false);
});

test("families and unknown kinds fall back to readable text", () => {
  assert.equal(presentApproval("run_project_lint").confirmLabel, "실행");
  assert.equal(presentApproval("set_ui_text").confirmLabel, "진행");
  assert.equal(presentApproval("something_new").confirmLabel, "승인");
});

test("remaining time counts down and disappears once expired", () => {
  const now = Date.parse("2026-10-06T00:00:00Z");
  assert.equal(remainingText("2026-10-06T00:04:32Z", now), "4분 32초 남음");
  assert.equal(remainingText("2026-10-06T00:00:09Z", now), "9초 남음");
  assert.equal(remainingText("2026-10-06T00:00:00Z", now), undefined);
  assert.equal(remainingText("not a date", now), undefined);
});
