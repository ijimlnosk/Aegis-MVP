import assert from "node:assert/strict";
import test from "node:test";
import { collapseMessage } from "./collapse";

test("short messages are left whole", () => {
  assert.deepEqual(collapseMessage("완료했습니다."), { preview: "완료했습니다.", truncated: false });
});

test("long messages are cut by line count or length", () => {
  const many = Array.from({ length: 20 }, (_, index) => `line ${index}`).join("\n");
  const byLines = collapseMessage(many, 3);
  assert.equal(byLines.truncated, true);
  assert.equal(byLines.preview, "line 0\nline 1\nline 2…");
  assert.equal(collapseMessage("가".repeat(800), 12, 10).preview, `${"가".repeat(10)}…`);
});
