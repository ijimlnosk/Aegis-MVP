import assert from "node:assert/strict";
import test from "node:test";
import { splitSegments } from "./segments";

test("fenced blocks become code segments between text", () => {
  assert.deepEqual(splitSegments("결과\n```\nline 1\n  line 2\n```\n끝"), [
    { kind: "text", text: "결과" }, { kind: "code", text: "line 1\n  line 2" }, { kind: "text", text: "끝" }]);
});

test("a truncated reply keeps its open block as code", () => {
  assert.deepEqual(splitSegments("머리\n```\ncut off…"), [{ kind: "text", text: "머리" }, { kind: "code", text: "cut off…" }]);
  assert.deepEqual(splitSegments("plain"), [{ kind: "text", text: "plain" }]);
});
