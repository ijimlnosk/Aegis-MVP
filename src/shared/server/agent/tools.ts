import type { ApprovalToolName, ToolName } from "./types";

const object = (properties: object = {}, required?: string[]) => ({ type: "object", properties, required });
const project = { project: { type: "string", description: "registry의 프로젝트 id" } };
const container = { container: { type: "string", description: "Docker 컨테이너 이름" } };

export const tools = [
  tool("get_projects", "설정된 프로젝트 목록을 확인한다.", object()),
  tool("get_project_status", "프로젝트의 Git 상태를 확인한다.", object(project, ["project"])),
  tool("run_project_typecheck", "프로젝트 타입 검사를 실행한다. 승인이 필요하다.", object(project, ["project"])),
  tool("get_active_mac_application", "현재 Mac의 전면 앱을 확인한다.", object()),
  tool("open_mac_application", "허용된 Mac 앱을 실행한다. 승인이 필요하다.", object({ application: { type: "string" } }, ["application"])),
  tool("capture_mac_screen", "현재 Mac 화면을 캡처한다. 승인이 필요하다.", object()),
  tool("get_system_status", "sol-server의 업타임, 메모리, 디스크, Docker 상태를 확인한다.", object()),
  tool("get_docker_containers", "sol-server의 Docker 컨테이너 목록을 확인한다.", object()),
  tool("get_docker_logs", "Docker 컨테이너의 최근 로그를 확인한다.", object({ ...container, lines: { type: "number" } }, ["container"])),
  ...(["restart", "stop", "start"] as const).map((action) =>
    tool(`${action}_docker_container` as ToolName, `Docker 컨테이너를 ${action}한다. 승인이 필요하다.`, object(container, ["container"]))),
];

export const approvalTools = new Set<ApprovalToolName>([
  "run_project_typecheck", "open_mac_application", "capture_mac_screen",
  "restart_docker_container", "stop_docker_container", "start_docker_container",
]);

export function isToolName(value: string): value is ToolName {
  return tools.some((item) => item.function.name === value);
}

function tool(name: ToolName, description: string, parameters: object) {
  return { type: "function", function: { name, description, parameters } };
}
