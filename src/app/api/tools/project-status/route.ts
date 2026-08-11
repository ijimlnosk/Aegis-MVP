import { NextResponse } from "next/server";
import { getProjectRoot } from "@/shared/server/projectRoot";
import { runCommand } from "@/shared/server/runCommand";

export async function POST() {
  try {
    const root = getProjectRoot();
    const output = await runCommand(
      "git",
      ["status", "--short", "--branch"],
      root,
    );
    return NextResponse.json({ root, output: output || "변경 사항 없음" });
  } catch (error) {
    const message = error instanceof Error ? error.message : "상태 확인 실패";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
