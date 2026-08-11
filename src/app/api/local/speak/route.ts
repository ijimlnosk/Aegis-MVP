import { NextResponse } from "next/server";
import { createVoiceReply } from "@/shared/server/localVoice";

export async function POST(request: Request) {
  try {
    const { text } = await request.json() as { text?: unknown };
    if (typeof text !== "string") return NextResponse.json({ error: "음성으로 읽을 텍스트가 필요합니다." }, { status: 400 });
    return NextResponse.json(await createVoiceReply(text));
  } catch (error) {
    const message = error instanceof Error ? error.message : "음성 생성에 실패했습니다.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
