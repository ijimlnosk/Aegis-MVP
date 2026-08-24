"use client";

import { LocalAgentPanel } from "@/features/local-agent/ui/LocalAgentPanel";

export default function HomePage() {
  return (
    <main className="shell">
      <header className="topbar">
        <span className="brand">AEGIS / 01</span>
        <span className="signal signal--listening">LOCAL</span>
      </header>

      <section className="hero">
        <p className="eyebrow">PERSONAL INTELLIGENCE SYSTEM</p>
        <h1>무엇을 도와드릴까요?</h1>
        <p className="hint">환경 설정된 Ollama 백엔드 사용 중</p>
      </section>
      <LocalAgentPanel />
    </main>
  );
}
