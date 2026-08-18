import { NextResponse } from "next/server";
import { executeReadTool } from "@/shared/server/agent/executor";

export async function POST(request: Request) {
  try {
    const body = await request.json() as { project?: unknown };
    return NextResponse.json(await executeReadTool("get_project_status", { project: body.project }));
  } catch (error) {
    const message = error instanceof Error ? error.message : "상태 확인 실패";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
