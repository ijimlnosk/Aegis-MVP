import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { getProject } from "../../../src/shared/server/projects/registry.ts";

const execFileAsync = promisify(execFile);

export async function getProjectStatus(id: unknown) {
  if (typeof id !== "string") throw new Error("프로젝트 id가 필요합니다.");
  const project = getProject(id);
  if (project.location !== "server") throw new Error("서버 프로젝트가 아닙니다.");
  const { stdout, stderr } = await execFileAsync("git", ["status", "--short", "--branch"], {
    cwd: project.path, timeout: 30_000, maxBuffer: 1024 * 1024,
  });
  return `${stdout}${stderr}`.trim();
}
