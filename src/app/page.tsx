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
        <p className="hint">Ollama / Qwen3 4B · 이 Mac에서 직접 실행 중</p>
      </section>
      <LocalAgentPanel />
    </main>
  );
}
