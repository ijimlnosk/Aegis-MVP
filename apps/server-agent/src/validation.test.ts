import assert from "node:assert/strict";
import test from "node:test";
import { validateContainerName, validateLogLines } from "./validation.ts";

test("container validation accepts Docker names only", () => {
  assert.equal(validateContainerName("security-juice-shop"), "security-juice-shop");
  for (const value of ["", "nginx; reboot", "$(whoami)", "../docker.sock", ["nginx"]]) {
    assert.throws(() => validateContainerName(value), /컨테이너 이름/);
  }
});

test("log line validation applies safe bounds", () => {
  assert.equal(validateLogLines(undefined), 100);
  assert.equal(validateLogLines(500), 500);
  for (const value of [0, 1001, 1.5, "100"]) assert.throws(() => validateLogLines(value), /1~1000/);
});
