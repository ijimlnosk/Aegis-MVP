import assert from "node:assert/strict";
import test from "node:test";
import { normalizeGatewayURL } from "./gatewayURL";

test("accepts current Tailscale HTTP and HTTPS gateway URLs", () => {
  assert.equal(normalizeGatewayURL("http://100.121.105.13:8790/"), "http://100.121.105.13:8790");
  assert.equal(normalizeGatewayURL("https://aegis.example.test/path"), "https://aegis.example.test");
});

test("rejects cleartext public and credential-bearing URLs", () => {
  assert.throws(() => normalizeGatewayURL("http://8.8.8.8:8790"), /insecurePublicGateway/);
  assert.throws(() => normalizeGatewayURL("https://token@example.test"), /invalidGatewayURL/);
});

test("preserves a Tailscale MagicDNS HTTPS gateway exactly -- no port appended, no downgrade to http", () => {
  const url = "https://kims-macbook-pro.tailabbdd3.ts.net";
  assert.equal(normalizeGatewayURL(url), url);
  assert.equal(normalizeGatewayURL(`${url}/`), url);
});
