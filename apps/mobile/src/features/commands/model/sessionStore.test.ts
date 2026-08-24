import assert from "node:assert/strict";
import test from "node:test";
import { useRemoteSession } from "./sessionStore";

test("conversation session stays stable while command messages change", () => {
  const before = useRemoteSession.getState().sessionId;
  useRemoteSession.getState().addMessage({ id: "m1", role: "user", content: "상태", createdAt: new Date().toISOString(), commandId: "c1" });
  assert.equal(useRemoteSession.getState().sessionId, before);
  useRemoteSession.getState().newConversation();
  assert.notEqual(useRemoteSession.getState().sessionId, before);
});
