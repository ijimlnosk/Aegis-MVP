import { executeApprovedTool, executeReadTool } from "./agent/executor";
import { approvalTools, isToolName, tools } from "./agent/tools";
import type { AgentMessage, PendingAction, ReadToolName } from "./agent/types";

export async function chatWithLocalAgent(message: string) {
  const first = await ask([{ role: "user", content: message }]);
  const call = first.message.tool_calls?.[0]?.function;
  if (!call) return { reply: visibleText(first.message.content) || "응답을 생성하지 못했습니다." };
  if (!isToolName(call.name)) return { reply: "지원하지 않는 작업 요청입니다." };
  const args = asObject(call.arguments);
  if (approvalTools.has(call.name as PendingAction["tool"])) {
    return { pending: { tool: call.name, args } as PendingAction };
  }
  const output = await executeReadTool(call.name as ReadToolName, args);
  const final = await ask([
    { role: "user", content: message }, first.message,
    { role: "tool", tool_name: call.name, content: JSON.stringify(output) },
  ]);
  return { reply: visibleText(final.message.content) || JSON.stringify(output) };
}

export async function approveLocalAction(action: PendingAction) {
  if (!approvalTools.has(action.tool)) throw new Error("승인할 수 없는 작업입니다.");
  return executeApprovedTool(action);
}

async function ask(messages: unknown[]) {
  const baseURL = process.env.AEGIS_OLLAMA_URL;
  if (!baseURL) throw new Error("AEGIS_OLLAMA_URL이 설정되지 않았습니다.");
  const timeout = Number(process.env.AEGIS_OLLAMA_REMOTE_TIMEOUT_SECONDS ?? "300") * 1000;
  const response = await fetch(`${baseURL.replace(/\/$/, "")}/api/chat`, {
    method: "POST", headers: { "Content-Type": "application/json" }, cache: "no-store",
    signal: AbortSignal.timeout(timeout),
    body: JSON.stringify({
      model: process.env.OLLAMA_MODEL ?? "qwen3:4b", stream: false, think: false,
      options: { temperature: 0.2, num_predict: 256 }, tools,
      messages: [{ role: "system", content: "당신은 Aegis다. 한국어로 짧게 답한다. 도구 인자에는 명령어가 아닌 registry id와 이름만 넣고, 한 번에 하나의 도구만 사용한다." }, ...messages],
    }),
  });
  if (!response.ok) throw new Error(`Ollama 요청 실패: ${await response.text()}`);
  return response.json() as Promise<{ message: AgentMessage }>;
}

function asObject(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function visibleText(value?: string) {
  const visible = value?.includes("</think>") ? value.slice(value.lastIndexOf("</think>") + 8) : value;
  const cleaned = visible?.replace(/<think>[\s\S]*/g, "").trim();
  const activeApp = cleaned?.match(/^현재 활성 앱\s*[:：]\s*(.+?)\.?$/m)?.[1];
  return activeApp ? `현재 활성 앱은 ${activeApp}입니다.` : cleaned;
}
