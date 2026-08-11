import { NextResponse } from "next/server";
import { approveLocalAction } from "@/shared/server/localAgent";

export async function POST(request: Request) {
  try {
    const action = await request.json() as { tool?: unknown; args?: unknown };
    if (typeof action.tool !== "string" || !action.args || typeof action.args !== "object") {
      return NextResponse.json({ error: "승인 작업 형식이 올바르지 않습니다." }, { status: 400 });
    }
    return NextResponse.json(await approveLocalAction(action as Parameters<typeof approveLocalAction>[0]));
  } catch (error) {
    const message = error instanceof Error ? error.message : "승인 작업에 실패했습니다.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
