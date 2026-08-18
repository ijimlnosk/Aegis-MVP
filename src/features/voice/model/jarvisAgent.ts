import { RealtimeAgent, tool } from "@openai/agents/realtime";
import { z } from "zod";
import { postJson } from "@/shared/api/postJson";

const projectId = z.object({ project: z.string().min(1) });
const container = z.object({ container: z.string().min(1) });
const tools = [
  tool({ name: "get_projects", description: "설정된 프로젝트 목록을 확인한다.", parameters: z.object({}), execute: () => postJson("/api/tools/projects") }),
  tool({ name: "get_project_status", description: "프로젝트의 Git 상태를 확인한다.", parameters: projectId, execute: ({ project }) => postJson("/api/tools/project-status", { project }) }),
  tool({ name: "run_project_typecheck", description: "프로젝트 타입 검사를 실행한다.", parameters: projectId, needsApproval: true, execute: ({ project }) => postJson("/api/tools/typecheck", { project }) }),
  tool({ name: "get_active_mac_application", description: "현재 Mac의 전면 앱을 확인한다.", parameters: z.object({}), execute: () => postJson("/api/tools/active-app") }),
  tool({ name: "open_mac_application", description: "허용 목록의 Mac 앱을 실행한다.", parameters: z.object({ application: z.string().min(1) }), needsApproval: true, execute: ({ application }) => postJson("/api/tools/open-app", { application }) }),
  tool({ name: "capture_mac_screen", description: "현재 Mac 화면을 캡처한다.", parameters: z.object({}), needsApproval: true, execute: () => postJson("/api/tools/capture-screen") }),
  tool({ name: "get_system_status", description: "sol-server의 RAM, 디스크, 업타임, Docker 목록을 확인한다.", parameters: z.object({}), execute: () => server("status") }),
  tool({ name: "get_docker_containers", description: "sol-server의 Docker 컨테이너를 확인한다.", parameters: z.object({}), execute: () => server("containers") }),
  tool({ name: "get_docker_logs", description: "컨테이너 최근 로그를 확인한다.", parameters: container.extend({ lines: z.number().int().min(1).max(1000).optional() }), execute: (args) => server("logs", args) }),
  ...(["restart", "stop", "start"] as const).map((operation) => tool({
    name: `${operation}_docker_container`, description: `컨테이너를 ${operation}한다.`,
    parameters: container, needsApproval: true,
    execute: ({ container: name }) => server(operation, { container: name }),
  })),
];

export const jarvisAgent = new RealtimeAgent({
  name: "Aegis",
  instructions: `당신은 개인 보조 AI Aegis다. 자연스럽고 짧은 한국어로 답한다.
프로젝트는 목록에서 registry id를 찾아 사용한다. 조회는 바로 실행하고 변경 작업은 승인받는다.
명령어를 만들지 않으며 도구에는 프로젝트 id, 컨테이너 이름 같은 데이터만 전달한다.`,
  tools,
});

function server(operation: string, args: object = {}) {
  return postJson("/api/tools/server", { operation, ...args });
}
