import { NextResponse } from "next/server";
import { executeApprovedTool } from "@/shared/server/agent/executor";

export async function POST(request: Request) {
  try {
    const body = await request.json() as { project?: unknown };
    return NextResponse.json(await executeApprovedTool({
      tool: "run_project_typecheck", args: { project: body.project },
    }));
  } catch (error) {
    const detail = error as Error & { stdout?: string; stderr?: string };
    return NextResponse.json({ output: `${detail.stdout ?? ""}${detail.stderr ?? detail.message}`.trim() });
  }
}
