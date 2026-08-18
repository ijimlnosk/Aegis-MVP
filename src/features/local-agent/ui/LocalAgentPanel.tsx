"use client";

import { useState } from "react";
import { postJson } from "@/shared/api/postJson";

interface PendingAction { tool: string; args: Record<string, unknown> }
interface ChatResponse { reply?: string; pending?: PendingAction }

export function LocalAgentPanel() {
  const [message, setMessage] = useState("");
  const [result, setResult] = useState("로컬 Aegis가 준비되었습니다.");
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [busy, setBusy] = useState(false);

  async function send() {
    if (!message.trim() || busy) return;
    setBusy(true);
    try {
      const data = await postJson<ChatResponse>("/api/local/chat", { message });
      setMessage("");
      setPending(data.pending ?? null);
      setResult(data.reply ?? getApprovalText(data.pending));
      setAudioUrl(data.reply ? await createSpeech(data.reply) : null);
    } catch (error) {
      setResult(error instanceof Error ? error.message : "요청에 실패했습니다.");
    } finally { setBusy(false); }
  }

  async function approve() {
    if (!pending) return;
    setBusy(true);
    try {
      const data = await postJson<{ output?: string }>("/api/local/approve", pending);
      setResult(data.output || "작업을 완료했습니다.");
      setPending(null);
    } catch (error) {
      setResult(error instanceof Error ? error.message : "작업에 실패했습니다.");
    } finally { setBusy(false); }
  }

  return <section className="console">
    {audioUrl ? <audio className="voice-player" controls autoPlay src={audioUrl} onCanPlay={(event) => void event.currentTarget.play()} onError={() => setResult("음성을 불러오지 못했습니다. 다시 요청해 주세요.")}>Aegis 음성을 재생할 수 없습니다.</audio> : null}
    <details className="text-result"><summary>텍스트 보기</summary><p className="hint">{result}</p></details>
    {pending && <div className="approval"><h2>{getApprovalText(pending)}</h2><button className="button button--primary" onClick={approve}>실행 승인</button><button className="button" onClick={() => setPending(null)}>거절</button></div>}
    <div className="local-input"><input value={message} onChange={(event) => setMessage(event.target.value)} onKeyDown={(event) => event.key === "Enter" && send()} placeholder="예: 현재 활성 앱 확인해줘" /><button className="button button--primary" onClick={send}>{busy ? "처리 중" : "보내기"}</button></div>
  </section>;
}

async function createSpeech(text: string) {
  const response = await postJson<{ url: string }>("/api/local/speak", { text });
  return response.url;
}

function getApprovalText(action?: PendingAction) {
  if (action?.tool === "open_mac_application") return `${String(action.args.application)}을(를) 실행할까요?`;
  if (action?.tool === "capture_mac_screen") return "현재 화면을 캡처할까요?";
  if (action?.tool === "run_project_typecheck") return `${String(action.args.project)} 타입 검사를 실행할까요?`;
  const operation = action?.tool.split("_")[0];
  const labels: Record<string, string> = { restart: "재시작", stop: "중지", start: "시작" };
  return `${String(action?.args.container)} 컨테이너를 ${labels[operation ?? ""] ?? "변경"}할까요?`;
}
