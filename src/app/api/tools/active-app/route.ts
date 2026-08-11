import { NextResponse } from "next/server";
import { callMacAgent } from "@/shared/server/macAgent";

export async function POST() {
  try {
    return NextResponse.json(await callMacAgent("/v1/tools/active-app"));
  } catch (error) {
    const message = error instanceof Error ? error.message : "활성 앱 확인 실패";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
