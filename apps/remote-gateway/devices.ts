import { randomBytes, randomUUID, scryptSync, timingSafeEqual } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import type { RemoteDevice, RemoteDeviceView } from "./models.ts";

const LAST_SEEN_PERSIST_INTERVAL_MS = 60_000;

export class RemoteDeviceStore {
  private devices: RemoteDevice[];
  private readonly path?: string;
  constructor(path?: string) { this.path = path; this.devices = this.load(); }

  register(name?: string) {
    const credential = randomBytes(32).toString("base64url");
    const now = new Date().toISOString();
    const device: RemoteDevice = { id: randomUUID(), name: cleanName(name, this.devices.length + 1),
      credentialHash: hashCredential(credential), createdAt: now, lastSeenAt: now, enabled: true };
    this.devices.push(device); this.save();
    return { device: publicDevice(device), credential };
  }

  authenticate(id: string, credential: string): RemoteDeviceView | undefined {
    return this.authenticateResult(id, credential).device;
  }

  authenticateResult(id: string, credential: string): { device?: RemoteDeviceView; error?: string } {
    const device = this.devices.find(value => value.id === id);
    if (!device || !verifyCredential(credential, device.credentialHash)) return { error: "deviceCredentialInvalid" };
    if (device.revokedAt) return { error: "deviceRevoked" };
    if (!device.enabled) return { error: "deviceDisabled" };
    const now = Date.now();
    const lastSeenAt = Date.parse(device.lastSeenAt);
    if (!Number.isFinite(lastSeenAt) || now - lastSeenAt >= LAST_SEEN_PERSIST_INTERVAL_MS) {
      device.lastSeenAt = new Date(now).toISOString(); this.save();
    }
    return { device: publicDevice(device) };
  }

  list(): RemoteDeviceView[] { return this.devices.map(publicDevice); }
  revoke(id: string) {
    const device = this.devices.find(value => value.id === id);
    if (!device || device.revokedAt) return false;
    device.enabled = false; device.revokedAt = new Date().toISOString(); this.save(); return true;
  }
  disable(id: string) { const device = this.devices.find(value => value.id === id);
    if (!device) return false; device.enabled = false; this.save(); return true; }

  storedRecordsForTesting() { return structuredClone(this.devices); }

  private load(): RemoteDevice[] {
    if (!this.path) return [];
    try { const value = JSON.parse(readFileSync(this.path, "utf8")); return Array.isArray(value) ? value : []; }
    catch { return []; }
  }
  private save() {
    if (!this.path) return;
    mkdirSync(dirname(this.path), { recursive: true, mode: 0o700 });
    const temporary = `${this.path}.tmp`;
    writeFileSync(temporary, JSON.stringify(this.devices), { encoding: "utf8", mode: 0o600 });
    renameSync(temporary, this.path);
  }
}

function hashCredential(value: string) {
  const salt = randomBytes(16); const digest = scryptSync(value, salt, 32);
  return `scrypt:${salt.toString("base64url")}:${digest.toString("base64url")}`;
}
function verifyCredential(value: string, encoded: string) {
  const [algorithm, saltText, digestText] = encoded.split(":");
  if (algorithm !== "scrypt" || !saltText || !digestText) return false;
  const expected = Buffer.from(digestText, "base64url");
  const actual = scryptSync(value, Buffer.from(saltText, "base64url"), expected.length);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
function cleanName(value: string | undefined, index: number) {
  const name = value?.trim().replace(/[\u0000-\u001f]/g, "").slice(0, 64);
  return name || `Remote Device ${index}`;
}
function publicDevice(device: RemoteDevice): RemoteDeviceView {
  return { id: device.id, name: device.name, createdAt: device.createdAt,
    lastSeenAt: device.lastSeenAt, enabled: device.enabled, revokedAt: device.revokedAt };
}
