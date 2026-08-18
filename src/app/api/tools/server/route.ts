import { NextResponse } from "next/server";
import { executeApprovedTool, executeReadTool } from "@/shared/server/agent/executor";
import type { ApprovalToolName, ReadToolName } from "@/shared/server/agent/types";

const reads: Record<string, ReadToolName> = {
  status: "get_system_status", containers: "get_docker_containers", logs: "get_docker_logs",
};
const actions: Record<string, ApprovalToolName> = {
  restart: "restart_docker_container", stop: "stop_docker_container", start: "start_docker_container",
};

export async function POST(request: Request) {
  try {
    const body = await request.json() as Record<string, unknown>;
    if (typeof body.operation !== "string") throw new Error("서버 작업이 필요합니다.");
    if (reads[body.operation]) return NextResponse.json(await executeReadTool(reads[body.operation], body));
    if (actions[body.operation]) {
      return NextResponse.json(await executeApprovedTool({ tool: actions[body.operation], args: body }));
    }
    throw new Error("지원하지 않는 서버 작업입니다.");
  } catch (error) {
    const message = error instanceof Error ? error.message : "서버 작업 실패";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
