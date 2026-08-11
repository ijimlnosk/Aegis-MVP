import assert from "node:assert/strict";
import test from "node:test";
import { loadConfig } from "./config.ts";

test("Mac Agent requires a local authentication token", () => {
  assert.throws(() => loadConfig({}), /MAC_AGENT_TOKEN/);
});

test("Mac Agent parses its allowlisted applications", () => {
  const config = loadConfig({
    MAC_AGENT_TOKEN: "local-secret",
    MAC_AGENT_ALLOWED_APPS: "Finder, Visual Studio Code",
  });
  assert.deepEqual([...config.allowedApps], ["Finder", "Visual Studio Code"]);
  assert.equal(config.allowAllApps, false);
});

test("Mac Agent allows all apps only with an explicit wildcard", () => {
  assert.equal(loadConfig({ MAC_AGENT_TOKEN: "local-secret", MAC_AGENT_ALLOWED_APPS: "*" }).allowAllApps, true);
});
