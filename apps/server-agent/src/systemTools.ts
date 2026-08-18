import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export async function getDiskUsage() {
  return output("df", ["-h", "/"]);
}

export async function getMemoryUsage() {
  return output("free", ["-h"]);
}

export async function getUptime() {
  return output("uptime", ["-p"]);
}

async function output(command: string, args: string[]) {
  const { stdout } = await execFileAsync(command, args, { timeout: 30_000 });
  return stdout.trim();
}
