import assert from "node:assert/strict";
import test from "node:test";
import { DEFAULT_QUICK_REQUESTS, parseRecentRequests, quickRequests, rememberRequest } from "./recentRequests";

test("recent requests move to the front without duplicates and skip slash commands", () => {
  const first = rememberRequest([], "PTFriends 상태 보여줘");
  const second = rememberRequest(first, "lint 고쳐줘");
  assert.deepEqual(rememberRequest(second, " PTFriends 상태 보여줘 "), ["PTFriends 상태 보여줘", "lint 고쳐줘"]);
  assert.deepEqual(rememberRequest(second, "/perf"), second);
});

test("recent requests are capped and fall back to defaults when empty", () => {
  const many = Array.from({ length: 10 }, (_, index) => `요청 ${index}`).reduce(rememberRequest, [] as string[]);
  assert.equal(many.length, 6);
  assert.equal(many[0], "요청 9");
  assert.deepEqual(quickRequests([]), DEFAULT_QUICK_REQUESTS);
  assert.deepEqual(quickRequests(["lint 고쳐줘"]), ["/help", "lint 고쳐줘"]);
});

test("stored recent requests tolerate corrupt data", () => {
  assert.deepEqual(parseRecentRequests('["a", 1, "b"]'), ["a", "b"]);
  assert.deepEqual(parseRecentRequests("{"), []);
  assert.deepEqual(parseRecentRequests(undefined), []);
});
