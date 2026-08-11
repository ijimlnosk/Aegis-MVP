import { getProjectRoot } from "@/shared/server/projectRoot";
import { runCommand } from "@/shared/server/runCommand";
import { callMacAgent } from "@/shared/server/macAgent";

type ToolName = "get_project_status" | "get_active_mac_application" |
  "run_project_typecheck" | "open_mac_application" | "capture_mac_screen";

type PendingAction = { tool: Exclude<ToolName, "get_project_status" | "get_active_mac_application">; args: Record<string, unknown> };

const tools = [
  { type: "function", function: { name: "get_project_status", description: "설정된 개발 프로젝트의 Git 상태를 확인한다.", parameters: { type: "object", properties: {} } } },
  { type: "function", function: { name: "get_active_mac_application", description: "현재 Mac에서 전면에 떠 있는 앱 이름을 확인한다.", parameters: { type: "object", properties: {} } } },
  { type: "function", function: { name: "run_project_typecheck", description: "프로젝트 타입 검사를 실행한다. 사용자 승인이 필요하다.", parameters: { type: "object", properties: {} } } },
  { type: "function", function: { name: "open_mac_application", description: "Mac 앱을 실행한다. 사용자 승인이 필요하다.", parameters: { type: "object", properties: { application: { type: "string" } }, required: ["application"] } } },
  { type: "function", function: { name: "capture_mac_screen", description: "현재 Mac 화면을 캡처한다. 사용자 승인이 필요하다.", parameters: { type: "object", properties: {} } } },
];

const approvalTools = new Set<ToolName>(["run_project_typecheck", "open_mac_application", "capture_mac_screen"]);

export async function chatWithLocalAgent(message: string) {
  const first = await ask([{ role: "user", content: message }]);
  const call = first.message.tool_calls?.[0]?.function;
  if (!call) return { reply: visibleText(first.message.content) || "응답을 생성하지 못했습니다." };
  if (!isToolName(call.name)) return { reply: "지원하지 않는 작업 요청입니다." };
  const args = asObject(call.arguments);
  if (approvalTools.has(call.name)) {
    return { pending: { tool: call.name as PendingAction["tool"], args } satisfies PendingAction };
  }

  const output = await executeReadTool(call.name);
  const final = await ask([
    { role: "user", content: message },
    first.message,
    { role: "tool", tool_name: call.name, content: JSON.stringify(output) },
  ]);
  return { reply: visibleText(final.message.content) || JSON.stringify(output) };
}

export async function approveLocalAction(action: PendingAction) {
  if (!approvalTools.has(action.tool)) throw new Error("승인할 수 없는 작업입니다.");
  if (action.tool === "run_project_typecheck") {
    return { output: await runCommand("npm", ["run", "typecheck"], getProjectRoot()) };
  }
  if (action.tool === "open_mac_application") {
    const application = action.args.application;
    if (typeof application !== "string" || !application.trim()) throw new Error("앱 이름이 필요합니다.");
    return callMacAgent("/v1/tools/open-app", { application });
  }
  return callMacAgent("/v1/tools/capture-screen");
}

async function executeReadTool(tool: ToolName) {
  if (tool === "get_project_status") {
    return { output: await runCommand("git", ["status", "--short", "--branch"], getProjectRoot()) };
  }
  return callMacAgent("/v1/tools/active-app");
}

async function ask(messages: unknown[]) {
  const response = await fetch(`${process.env.OLLAMA_URL ?? "http://127.0.0.1:11434"}/api/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: process.env.OLLAMA_MODEL ?? "qwen3:4b",
      stream: false,
      think: false,
      options: { temperature: 0.2 },
      tools,
      messages: [{ role: "system", content: "당신은 Aegis다. 한국어로 짧게 답하고, 사고 과정이나 <think> 내용을 절대 출력하지 않는다. 한 번에 하나의 도구만 사용한다." }, ...messages],
    }),
    cache: "no-store",
  });
  if (!response.ok) throw new Error(`Ollama 요청 실패: ${await response.text()}`);
  return response.json() as Promise<{ message: { content?: string; tool_calls?: Array<{ function: { name: string; arguments: unknown } }> } }>;
}

function asObject(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function isToolName(value: string): value is ToolName {
  return ["get_project_status", "get_active_mac_application", "run_project_typecheck", "open_mac_application", "capture_mac_screen"].includes(value);
}

function visibleText(value?: string) {
  const afterThinking = value?.includes("</think>")
    ? value.slice(value.lastIndexOf("</think>") + "</think>".length)
    : value;
  const cleaned = afterThinking?.replace(/<think>[\s\S]*/g, "").trim();
  const activeApp = cleaned?.match(/^현재 활성 앱\s*[:：]\s*(.+?)\.?$/m)?.[1];
  return activeApp ? `현재 활성 앱은 ${activeApp}입니다.` : cleaned;
}
