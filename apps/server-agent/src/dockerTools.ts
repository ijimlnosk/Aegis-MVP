import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { validateContainerName, validateLogLines } from "./validation.ts";

const execFileAsync = promisify(execFile);

export async function getContainers() {
  return docker(["ps", "--format", "{{.Names}}\t{{.Status}}\t{{.Ports}}"]);
}

export async function getDockerLogs(container: unknown, lines: unknown) {
  return docker(["logs", "--tail", String(validateLogLines(lines)), validateContainerName(container)]);
}

export async function changeContainerState(action: "restart" | "stop" | "start", container: unknown) {
  return docker([action, validateContainerName(container)]);
}

async function docker(args: string[]) {
  const { stdout, stderr } = await execFileAsync("docker", args, { timeout: 60_000, maxBuffer: 1024 * 1024 });
  return `${stdout}${stderr}`.trim();
}
