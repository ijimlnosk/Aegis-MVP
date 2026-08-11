import { NextResponse } from "next/server";
import { callMacAgent } from "@/shared/server/macAgent";

export async function POST(request: Request) {
  try {
    const { application } = await request.json() as { application?: unknown };
    if (typeof application !== "string" || !application.trim()) {
      return NextResponse.json({ error: "앱 이름이 필요합니다." }, { status: 400 });
    }
    return NextResponse.json(await callMacAgent("/v1/tools/open-app", { application }));
  } catch (error) {
    const message = error instanceof Error ? error.message : "앱 실행 실패";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
