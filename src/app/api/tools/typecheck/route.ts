import { NextResponse } from "next/server";
import { getProjectRoot } from "@/shared/server/projectRoot";
import { runCommand } from "@/shared/server/runCommand";

export async function POST() {
  try {
    const root = getProjectRoot();
    const output = await runCommand("npm", ["run", "typecheck"], root);
    return NextResponse.json({ root, output: output || "타입 오류 없음" });
  } catch (error) {
    const detail = error as Error & { stdout?: string; stderr?: string };
    return NextResponse.json({
      root: getProjectRoot(),
      output: `${detail.stdout ?? ""}${detail.stderr ?? detail.message}`.trim(),
    });
  }
}
