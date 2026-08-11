import { execFile } from "node:child_process";
import { mkdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { randomUUID } from "node:crypto";

const execFileAsync = promisify(execFile);
const root = process.cwd();

export async function createVoiceReply(text: string) {
  if (!text.trim() || text.length > 500) throw new Error("음성 응답은 500자 이하여야 합니다.");
  const referenceAudio = join(root, ".aegis/voices/aegis-reference.wav");
  const referenceText = await readFile(join(root, ".aegis/voices/reference.txt"), "utf8");
  const id = randomUUID();
  const outputDir = join(root, "public/aegis-audio", id);
  await mkdir(outputDir, { recursive: true });
  const command = join(root, ".aegis/f5-tts/bin/f5-tts_infer-cli");
  await execFileAsync(command, [
    "--model", "F5TTS_v1_Base", "--ref_audio", referenceAudio,
    "--ref_text", referenceText.trim(), "--gen_text", text.trim(),
    "--output_dir", outputDir,
  ], { cwd: root, timeout: 240_000, maxBuffer: 1024 * 1024 });
  const wav = join(outputDir, "infer_cli_basic.wav");
  const mp3 = join(outputDir, "reply.mp3");
  await execFileAsync("ffmpeg", [
    "-y", "-i", wav, "-af", "apad=pad_dur=0.7",
    "-codec:a", "libmp3lame", "-b:a", "128k", mp3,
  ], { cwd: root, timeout: 60_000, maxBuffer: 1024 * 1024 });
  return { url: `/aegis-audio/${id}/reply.mp3` };
}
