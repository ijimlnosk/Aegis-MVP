import { NextResponse } from "next/server";
import { callMacAgent } from "@/shared/server/macAgent";

export async function POST() {
  try {
    return NextResponse.json(await callMacAgent("/v1/tools/capture-screen"));
  } catch (error) {
    const message = error instanceof Error ? error.message : "화면 캡처 실패";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
