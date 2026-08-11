import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export async function runCommand(
  command: string,
  args: string[],
  cwd: string,
) {
  const result = await execFileAsync(command, args, {
    cwd,
    timeout: 60_000,
    maxBuffer: 1024 * 1024,
  });
  return `${result.stdout}${result.stderr}`.trim();
}
