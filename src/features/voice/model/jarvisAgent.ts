import { RealtimeAgent, tool } from "@openai/agents/realtime";
import { z } from "zod";
import { postJson } from "@/shared/api/postJson";

const projectStatus = tool({
  name: "get_project_status",
  description: "설정된 개발 프로젝트의 Git 브랜치와 변경 파일을 확인한다.",
  parameters: z.object({}),
  execute: () => postJson("/api/tools/project-status"),
});

const runTypecheck = tool({
  name: "run_project_typecheck",
  description: "설정된 프로젝트에서 npm run typecheck를 실행한다.",
  parameters: z.object({}),
  needsApproval: true,
  execute: () => postJson("/api/tools/typecheck"),
});

const getActiveApp = tool({
  name: "get_active_mac_application",
  description: "현재 Mac에서 전면에 떠 있는 앱 이름을 확인한다.",
  parameters: z.object({}),
  execute: () => postJson("/api/tools/active-app"),
});

const openApp = tool({
  name: "open_mac_application",
  description: "허용 목록에 등록된 Mac 앱을 실행한다.",
  parameters: z.object({ application: z.string().min(1) }),
  needsApproval: true,
  execute: ({ application }) => postJson("/api/tools/open-app", { application }),
});

const captureScreen = tool({
  name: "capture_mac_screen",
  description: "현재 Mac 화면을 캡처한다. 화면에는 민감한 정보가 있을 수 있다.",
  parameters: z.object({}),
  needsApproval: true,
  execute: () => postJson("/api/tools/capture-screen"),
});

export const jarvisAgent = new RealtimeAgent({
  name: "Aegis",
  instructions: `
당신은 사용자의 개인 개발 보조 AI인 Aegis다.
항상 자연스럽고 짧은 한국어로 말한다.
프로젝트 상태는 추측하지 말고 도구로 확인한다.
조회 도구는 바로 사용하고, 명령 실행 도구는 승인 흐름을 따른다.
도구 결과는 핵심 숫자와 다음 행동을 중심으로 보고한다.
사용자가 요청하지 않은 파일 수정이나 삭제는 절대 수행하지 않는다.
  `.trim(),
  tools: [projectStatus, runTypecheck, getActiveApp, openApp, captureScreen],
});
