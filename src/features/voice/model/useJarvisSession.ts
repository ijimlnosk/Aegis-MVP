"use client";

import { RealtimeSession } from "@openai/agents/realtime";
import { useMemo, useRef, useState } from "react";
import type {
  ActivityItem,
  ApprovalView,
  SessionStatus,
} from "@/entities/session/model/types";
import { postJson } from "@/shared/api/postJson";
import { jarvisAgent } from "./jarvisAgent";

interface TokenResponse { value: string }

export function useJarvisSession() {
  const sessionRef = useRef<RealtimeSession | null>(null);
  const [status, setStatus] = useState<SessionStatus>("idle");
  const [approval, setApproval] = useState<ApprovalView | null>(null);
  const [activity, setActivity] = useState<ActivityItem[]>([]);

  const addActivity = (message: string) => setActivity((items) => [
    { id: crypto.randomUUID(), message, time: new Date().toLocaleTimeString("ko-KR") },
    ...items,
  ].slice(0, 6));

  async function connect() {
    try {
      setStatus("connecting");
      const token = await postJson<TokenResponse>("/api/realtime/token");
      const session = new RealtimeSession(jarvisAgent, {
        model: "gpt-realtime-2.1",
      });
      session.on("tool_approval_requested", (_context, _agent, request) => {
        const approvalCopy = getApprovalCopy(request.approvalItem.name);
        setApproval({
          title: approvalCopy.title,
          detail: approvalCopy.detail,
          item: request.approvalItem,
        });
      });
      session.on("history_updated", () => addActivity("대화 내용이 갱신되었습니다."));
      await session.connect({ apiKey: token.value });
      sessionRef.current = session;
      setStatus("listening");
      addActivity("음성 세션이 연결되었습니다.");
    } catch (error) {
      setStatus("error");
      addActivity(error instanceof Error ? error.message : "연결에 실패했습니다.");
    }
  }

  function disconnect() {
    sessionRef.current?.close();
    sessionRef.current = null;
    setStatus("idle");
    addActivity("음성 세션을 종료했습니다.");
  }

  async function resolveApproval(approved: boolean) {
    if (!approval || !sessionRef.current) return;
    if (approved) await sessionRef.current.approve(approval.item);
    else await sessionRef.current.reject(approval.item);
    addActivity(approved ? "도구 실행을 승인했습니다." : "도구 실행을 거절했습니다.");
    setApproval(null);
  }

  const text = useMemo(() => getSessionText(status), [status]);
  return {
    status,
    approval,
    activity,
    statusLabel: text.label,
    hint: text.hint,
    toggleConnection: status === "idle" || status === "error" ? connect : disconnect,
    resolveApproval,
  };
}

function getApprovalCopy(toolName?: string) {
  const copy = {
    run_project_typecheck: {
      title: "프로젝트 타입 검사를 실행할까요?",
      detail: "설정된 프로젝트에서 npm run typecheck를 실행합니다.",
    },
    open_mac_application: {
      title: "Mac 앱을 실행할까요?",
      detail: "등록된 허용 목록 안의 앱만 실행할 수 있습니다.",
    },
    capture_mac_screen: {
      title: "현재 화면을 캡처할까요?",
      detail: "화면에 보이는 민감한 정보가 포함될 수 있습니다.",
    },
  };
  return copy[toolName as keyof typeof copy] ?? {
    title: "이 작업을 실행할까요?",
    detail: "실행 전에 사용자 승인이 필요합니다.",
  };
}

function getSessionText(status: SessionStatus) {
  const copy = {
    idle: { label: "OFFLINE", hint: "버튼을 눌러 음성 연결을 시작하세요." },
    connecting: { label: "CONNECTING", hint: "보안 음성 세션을 연결하고 있습니다." },
    connected: { label: "ONLINE", hint: "연결되었습니다." },
    listening: { label: "LISTENING", hint: "말씀하세요. 듣고 있습니다." },
    error: { label: "ERROR", hint: "설정을 확인한 뒤 다시 눌러주세요." },
  };
  return copy[status];
}
