import assert from "node:assert/strict";
import test from "node:test";
import { createProjectRegistry } from "./registry.ts";

test("registry returns only configured projects", () => {
  const registry = createProjectRegistry({ PTFRIENDS_PROJECT_ROOT: "/projects/ptfriends" });
  assert.deepEqual(registry.getProjects().map(({ id }) => id), ["ptfriends"]);
});

test("registry resolves a configured project by id", () => {
  const registry = createProjectRegistry({ SOOLSOOL_PROJECT_ROOT: "/projects/soolsool" });
  assert.equal(registry.getProject("soolsool").name, "SoolSool");
});

test("registry rejects unknown and unconfigured projects", () => {
  const registry = createProjectRegistry({});
  assert.throws(() => registry.getProject("unknown"), /프로젝트 설정/);
  assert.throws(() => registry.getProject("ptfriends"), /프로젝트 설정/);
});
