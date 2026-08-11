import assert from "node:assert/strict";
import test from "node:test";
import { getProjectRoot } from "./projectRoot.ts";

test("project root requires an explicit allowlisted path", () => {
  const previous = process.env.JARVIS_PROJECT_ROOT;
  delete process.env.JARVIS_PROJECT_ROOT;
  assert.throws(() => getProjectRoot(), /JARVIS_PROJECT_ROOT/);
  if (previous) process.env.JARVIS_PROJECT_ROOT = previous;
});
