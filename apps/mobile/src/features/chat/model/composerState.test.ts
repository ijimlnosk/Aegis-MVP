import assert from "node:assert/strict";
import test from "node:test";
import { composerBlockReason } from "./composerState";

test("the composer explains every blocked state and stays open when idle", () => {
  assert.equal(composerBlockReason("connected"), undefined);
  assert.match(composerBlockReason("connected", { commandId: "c", status: "running", messages: [] }) ?? "", /작업 중/);
  assert.match(composerBlockReason("connected", { commandId: "c", status: "awaitingApproval", messages: [],
    pendingApproval: { id: "a", title: "", goal: "", risk: "", scope: "", expiresAt: "" } }) ?? "", /승인 카드/);
  assert.match(composerBlockReason("desktopUnavailable") ?? "", /Mac/);
  assert.match(composerBlockReason("reconnecting") ?? "", /연결하는 중/);
});
