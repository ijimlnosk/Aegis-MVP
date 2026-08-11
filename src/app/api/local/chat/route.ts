import { NextResponse } from "next/server";
import { chatWithLocalAgent } from "@/shared/server/localAgent";

export async function POST(request: Request) {
  try {
    const { message } = await request.json() as { message?: unknown };
    if (typeof message !== "string" || !message.trim()) {
      return NextResponse.json({ error: "요청 내용을 입력하세요." }, { status: 400 });
    }
    return NextResponse.json(await chatWithLocalAgent(message));
  } catch (error) {
    const message = error instanceof Error ? error.message : "로컬 AI 요청에 실패했습니다.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
