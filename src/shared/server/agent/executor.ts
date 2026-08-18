import { callMacAgent } from "../macAgent";
import { runCommand } from "../runCommand";
import { callServerAgent } from "../serverAgent";
import { getProject, getProjects } from "../projects/registry";
import type { PendingAction, ReadToolName } from "./types";

export async function executeReadTool(tool: ReadToolName, args: Record<string, unknown>) {
  if (tool === "get_projects") return getProjects().map(({ id, name, location }) => ({ id, name, location }));
  if (tool === "get_active_mac_application") return callMacAgent("/v1/tools/active-app");
  if (tool === "get_system_status") return callServerAgent("/v1/tools/system-status");
  if (tool === "get_docker_containers") return callServerAgent("/v1/tools/docker-containers");
  if (tool === "get_docker_logs") return callServerAgent("/v1/tools/docker-logs", args);
  const project = getProject(requireString(args.project, "프로젝트 id"));
  if (project.location === "server") return callServerAgent("/v1/tools/project-status", { project: project.id });
  return { output: await runCommand("git", ["status", "--short", "--branch"], project.path) };
}

export async function executeApprovedTool(action: PendingAction) {
  if (action.tool === "run_project_typecheck") {
    const project = getProject(requireString(action.args.project, "프로젝트 id"));
    if (project.location !== "mac") throw new Error("서버 프로젝트 타입 검사는 아직 지원하지 않습니다.");
    return { output: await runCommand("npm", ["run", "typecheck"], project.path) };
  }
  if (action.tool === "open_mac_application") {
    return callMacAgent("/v1/tools/open-app", { application: requireString(action.args.application, "앱 이름") });
  }
  if (action.tool === "capture_mac_screen") return callMacAgent("/v1/tools/capture-screen");
  const operation = action.tool.replace("_docker_container", "");
  return callServerAgent(`/v1/tools/docker-${operation}`, action.args);
}

function requireString(value: unknown, label: string) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${label}이(가) 필요합니다.`);
  return value;
}
