import { NextResponse } from "next/server";
import { executeReadTool } from "@/shared/server/agent/executor";

export async function POST() {
  return NextResponse.json(await executeReadTool("get_projects", {}));
}
