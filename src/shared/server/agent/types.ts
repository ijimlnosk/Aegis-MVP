export type ReadToolName = "get_projects" | "get_project_status" |
  "get_active_mac_application" | "get_system_status" |
  "get_docker_containers" | "get_docker_logs";

export type ApprovalToolName = "run_project_typecheck" |
  "open_mac_application" | "capture_mac_screen" |
  "restart_docker_container" | "stop_docker_container" |
  "start_docker_container";

export type ToolName = ReadToolName | ApprovalToolName;
export interface PendingAction { tool: ApprovalToolName; args: Record<string, unknown> }

export interface AgentMessage {
  role: string;
  content?: string;
  tool_calls?: Array<{ function: { name: string; arguments: unknown } }>;
}
