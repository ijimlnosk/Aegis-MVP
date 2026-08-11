import type { SessionStatus } from "@/entities/session/model/types";

interface Props {
  status: SessionStatus;
  onClick: () => void;
}

export function VoiceOrb({ status, onClick }: Props) {
  return (
    <button
      className={`orb orb--${status}`}
      onClick={onClick}
      aria-label={status === "idle" ? "음성 연결" : "음성 연결 종료"}
    >
      <svg className="orb__icon" viewBox="0 0 24 24" fill="none" aria-hidden>
        <path d="M12 3a3 3 0 0 0-3 3v6a3 3 0 1 0 6 0V6a3 3 0 0 0-3-3Z" stroke="currentColor" strokeWidth="1.5" />
        <path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3M9 21h6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      </svg>
    </button>
  );
}
