export interface SlashCommand {
  usage: string;
  summary: string;
}

// Mirrors AegisDesktop's SlashCommand; the Desktop resolves and answers every command.
export const SLASH_COMMANDS: readonly SlashCommand[] = [
  { usage: "/help", summary: "Aegis가 할 수 있는 일과 명령어" },
  { usage: "/status", summary: "AI 백엔드·원격 제어·코딩 에이전트 상태" },
  { usage: "/projects", summary: "등록된 프로젝트 목록" },
  { usage: "/perf", summary: "최근 요청 응답 시간과 AI planner 사용 현황" },
];

export function slashSuggestions(text: string): SlashCommand[] {
  const trimmed = text.trim();
  if (!trimmed.startsWith("/") || /\s/.test(trimmed)) return [];
  const prefix = trimmed.toLowerCase();
  return SLASH_COMMANDS.filter(command => command.usage.startsWith(prefix));
}
