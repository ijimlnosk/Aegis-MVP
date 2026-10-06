import assert from "node:assert/strict";
import test from "node:test";
import { SLASH_COMMANDS, slashSuggestions } from "./slashCommands";

test("a bare slash lists every command", () => {
  assert.deepEqual(slashSuggestions("/"), SLASH_COMMANDS);
});

test("suggestions filter by prefix case-insensitively", () => {
  assert.deepEqual(slashSuggestions(" /ST").map(command => command.usage), ["/status"]);
  assert.deepEqual(slashSuggestions("/zzz"), []);
});

test("natural language and typed arguments hide the palette", () => {
  assert.deepEqual(slashSuggestions("PTFriends 상태"), []);
  assert.deepEqual(slashSuggestions("/status now"), []);
});
