import { execFile } from "node:child_process";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export async function getActiveApplication() {
  const script = 'tell application "System Events" to get name of first application process whose frontmost is true';
  const { stdout } = await execFileAsync("osascript", ["-e", script]);
  return stdout.trim() || "알 수 없음";
}

export async function openApplication(
  application: string,
  allowedApps: Set<string>,
  allowAllApps: boolean,
) {
  if (!allowAllApps && !allowedApps.has(application)) {
    throw new Error(`허용되지 않은 앱입니다: ${application}`);
  }
  await execFileAsync("open", ["-a", application]);
  return `${application}을(를) 실행했습니다.`;
}

export async function captureCurrentScreen() {
  const directory = await mkdtemp(join(tmpdir(), "aegis-screen-"));
  const path = join(directory, "screen.png");
  await execFileAsync("screencapture", ["-x", path]);
  return { path, capturedAt: new Date().toISOString() };
}
