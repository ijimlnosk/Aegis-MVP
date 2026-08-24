export const DEVICE_CREDENTIAL_KEY = "aegis.remote.deviceCredential";
let compatibilityId = 0;
const terminalStates = new Set(["completed", "failed", "cancelled"]);

export function friendlyProgressLabel(phase) {
  return ({ queued: "작업을 준비하고 있습니다...", planning: "요청을 이해하고 계획을 세우고 있습니다...",
    running: "작업을 진행하고 있습니다...", analyzing: "코드를 분석하고 있습니다...",
    coding: "Codex가 코드를 수정하고 있습니다...", validating: "변경사항을 검증하고 있습니다...",
    repairing: "검증 오류를 수정하고 있습니다...", gitPlanning: "커밋 계획을 만들고 있습니다...",
    committing: "커밋을 생성하고 있습니다...", pushing: "원격 저장소에 반영하고 있습니다...",
    screenAnalyzing: "화면을 확인하고 있습니다...", serverChecking: "서버 상태를 확인하고 있습니다...",
    awaitingApproval: "승인을 기다리고 있습니다.", cancelled: "작업이 취소되었습니다." })[phase]
    ?? "작업을 진행하고 있습니다...";
}
export function formatElapsed(seconds) { return seconds < 60 ? `${seconds}초 경과` : `${Math.floor(seconds / 60)}분 ${seconds % 60}초 경과`; }
export function pollingDelay(attempt, awaitingApproval = false) {
  if (awaitingApproval) return 3000; return attempt < 10 ? 1000 : attempt < 30 ? 2000 : 3000;
}

export function createId(cryptoAPI = globalThis.crypto) {
  if (typeof cryptoAPI?.randomUUID === "function") return cryptoAPI.randomUUID();
  if (typeof cryptoAPI?.getRandomValues !== "function") {
    compatibilityId += 1;
    return `compat-${Date.now().toString(36)}-${compatibilityId.toString(36)}`;
  }
  const bytes = new Uint8Array(16); cryptoAPI.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  const hex = [...bytes].map(value => value.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
}

export function createConnectionController(fetchImpl, onState) {
  let connecting = false;
  return { async connect(token, headers) {
    if (connecting) return { kind: "duplicate" };
    if (!token.trim()) { onState("emptyToken"); return { kind: "emptyToken" }; }
    connecting = true; onState("connecting");
    try { const response = await fetchImpl("/v1/status", { headers: headers(token) });
      if (response.status === 401) { onState("unauthorized"); return { kind: "unauthorized" }; }
      if (!response.ok) { onState("unexpected"); return { kind: "unexpected" }; }
      onState("connected"); return { kind: "connected" };
    } catch { onState("networkError"); return { kind: "networkError" }; }
    finally { connecting = false; }
  } };
}

export function createDeviceAuthController(fetchImpl, storage, onState) {
  let running = false, sessionMaster = "";
  const current = () => readCredential(storage);
  const headers = value => ({ Authorization: `Device ${value.credential}`,
    "X-Aegis-Device-ID": value.id, "Content-Type": "application/json" });
  return { current,
    headers() { const value = current();
      if (value) return headers(value);
      if (sessionMaster) return { Authorization: `Bearer ${sessionMaster}`,
        "X-Aegis-Device-ID": "mobile-session", "Content-Type": "application/json" };
      throw new Error("deviceCredentialInvalid"); },
    async autoConnect() {
      const value = current(); if (!value) return { kind: "registrationRequired" };
      onState("connecting");
      try { const response = await fetchImpl("/v1/status", { headers: headers(value) });
        if (response.status === 401) { removeCredential(storage); onState("credentialInvalid"); return { kind: "credentialInvalid" }; }
        if (!response.ok) { onState("unexpected"); return { kind: "unexpected" }; }
        onState("connected"); return { kind: "connected", device: value };
      } catch { onState("networkError"); return { kind: "networkError" }; }
    },
    async register(name, masterToken) {
      if (running) return { kind: "duplicate" };
      if (!masterToken.trim()) { onState("emptyToken"); return { kind: "emptyToken" }; }
      running = true; onState("registering");
      try { const response = await fetchImpl("/v1/devices/register", { method: "POST",
        headers: { Authorization: `Bearer ${masterToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({ name: name.trim() || undefined }) });
        if (response.status === 401) { onState("registrationTokenInvalid"); return { kind: "registrationTokenInvalid" }; }
        if (response.status === 429) { onState("registrationRateLimited"); return { kind: "registrationRateLimited" }; }
        if (!response.ok) return await legacyMasterConnection(masterToken);
        const result = await response.json(); if (!validIssuedCredential(result)) throw new Error("invalidRegistrationResponse");
        const value = { id: result.device.id, name: result.device.name, credential: result.credential };
        storage.setItem(DEVICE_CREDENTIAL_KEY, JSON.stringify(value)); onState("connected");
        return { kind: "connected", device: value, sessionOnly: !storage.persistent };
      } catch { return await legacyMasterConnection(masterToken); }
      finally { running = false; }
    },
    async revokeCurrent() {
      const value = current(); if (!value) return { kind: "registrationRequired" };
      try { await fetchImpl(`/v1/devices/${encodeURIComponent(value.id)}/revoke`,
        { method: "POST", headers: headers(value) }); } finally { removeCredential(storage); }
      sessionMaster = ""; onState("credentialInvalid"); return { kind: "revoked" };
    },
  };
  async function legacyMasterConnection(masterToken) {
    try { const response = await fetchImpl("/v1/status", { headers: { Authorization: `Bearer ${masterToken}`,
      "X-Aegis-Device-ID": "mobile-session", "Content-Type": "application/json" } });
      if (response.status === 401) { onState("registrationTokenInvalid"); return { kind: "registrationTokenInvalid" }; }
      if (!response.ok) { onState("unexpected"); return { kind: "unexpected" }; }
      sessionMaster = masterToken; onState("connected");
      return { kind: "connected", device: { name: "이번 세션" }, sessionOnly: true };
    } catch { onState("networkError"); return { kind: "networkError" }; }
  }
}

export function initializeRemoteUI(documentAPI = document, cryptoAPI = globalThis.crypto,
                                   fetchImpl = globalThis.fetch, storageSource) {
  const byId = id => documentAPI.getElementById(id);
  const state = byId("state"), error = byId("client-error"), connectButton = byId("connect");
  const history = byId("history"), composer = byId("composer"), tokenInput = byId("token");
  let timer, activeCommand, activeProgress, renderedApproval, pollAttempt = 0, pollInFlight = false;
  try {
    installProgressStyles(documentAPI);
    const session = createId(cryptoAPI); const storage = compatibleStorage(storageSource);
    const showState = value => { const labels = { emptyToken: "토큰을 입력하세요.", registering: "기기 등록 중...",
      connecting: "연결 중...", registrationTokenInvalid: "등록 토큰 인증 실패",
      registrationRateLimited: "등록 시도가 너무 많습니다. 잠시 후 다시 시도하세요.", credentialInvalid: "기기 등록이 필요합니다.",
      unexpected: "Gateway 응답을 확인할 수 없습니다.", networkError: "Gateway에 연결할 수 없습니다.", connected: "연결됨 · 이 기기" };
      state.textContent = labels[value] ?? value;
      error.textContent = ["networkError", "unexpected"].includes(value) ? state.textContent : "없음"; };
    const auth = createDeviceAuthController(fetchImpl, storage, showState);
    const showConnected = device => { byId("auth").hidden = true; composer.hidden = false;
      const deviceStatus = byId("device-status"), currentDevice = byId("current-device");
      if (deviceStatus) deviceStatus.hidden = false;
      if (currentDevice) currentDevice.textContent = device?.name || "이 기기"; };
    const showRegistration = () => { byId("auth").hidden = false; composer.hidden = true;
      const deviceStatus = byId("device-status"); if (deviceStatus) deviceStatus.hidden = true; };
    connectButton.addEventListener("click", async () => { connectButton.disabled = true;
      const master = tokenInput.value; tokenInput.value = "";
      try { const result = await auth.register(byId("device-name")?.value || "", master);
        if (result.kind === "connected") { showConnected(result.device);
          if (result.sessionOnly) error.textContent = "이 브라우저에서는 자동 로그인을 사용할 수 없어 이번 세션에서만 연결합니다.";
        } else showRegistration(); }
      catch { showClientError("클라이언트 등록 오류"); } finally { connectButton.disabled = false; } });
    byId("disconnect")?.addEventListener("click", async () => {
      if (globalThis.confirm && !globalThis.confirm("이 기기의 원격 연결을 해제할까요?")) return;
      await auth.revokeCurrent(); showRegistration(); });
    composer.addEventListener("submit", async event => { event.preventDefault();
      const input = byId("message"), text = input.value.trim(); if (!text) return;
      if (activeCommand) { state.textContent = "현재 작업이 진행 중입니다."; return; }
      input.value = ""; add(text, "mine");
      const id = createId(cryptoAPI); activeCommand = id;
      const sendButton = byId("send"); if (sendButton) sendButton.disabled = true;
      activeProgress = createProgressCard(id); activeProgress.update({ status: "planning", progress: {
        phase: "planning", message: "요청을 확인하고 있습니다...", cancellable: true, startedAt: new Date().toISOString() } });
      try { const response = await fetchImpl("/v1/commands", { method: "POST",
        headers: auth.headers(), body: JSON.stringify({ id, sessionId: session, text, timestamp: new Date().toISOString() }) });
        if (response.status === 401) { removeCredential(storage); showRegistration(); return showState("credentialInvalid"); }
        if (!response.ok) throw new Error("commandRejected"); poll(id);
      } catch { activeProgress.fail("명령을 전송하지 못했습니다."); finishActive(); } });
    async function poll(id) { if (pollInFlight || id !== activeCommand) return;
      clearTimeout(timer); pollInFlight = true;
      try { const response = await fetchImpl(`/v1/commands/${id}`, { headers: auth.headers() });
        if (response.status === 401) { removeCredential(storage); showRegistration(); return showState("credentialInvalid"); }
        if (response.status === 404) { activeProgress.fail("명령 상태를 찾을 수 없습니다."); return finishActive(); }
        if (!response.ok) { activeProgress.connectionLost(); return schedule(id, 3000); }
        const command = await response.json(); activeProgress.update(command); state.textContent = friendlyProgressLabel(command.progress?.phase ?? command.status);
        if (command.pendingApproval) return renderApproval(command);
        if (terminalStates.has(command.status)) { activeProgress.finish(command); return finishActive(); }
        schedule(id, pollingDelay(++pollAttempt, command.status === "awaitingApproval"));
      } catch { activeProgress.connectionLost(); schedule(id, 3000); }
      finally { pollInFlight = false; } }
    function schedule(id, delay) { clearTimeout(timer); timer = setTimeout(() => poll(id), delay); }
    function renderApproval(command) { activeProgress.pauseForApproval();
      if (renderedApproval === command.pendingApproval.id) return;
      renderedApproval = command.pendingApproval.id;
      const box = documentAPI.createElement("div"); box.className = "approval-content";
      box.textContent = [command.pendingApproval.title, command.pendingApproval.goal,
        `위험: ${command.pendingApproval.risk}`, `범위: ${command.pendingApproval.scope}`].join("\n");
      for (const decision of ["approve", "reject"]) { const button = documentAPI.createElement("button");
        button.textContent = decision === "approve" ? "승인" : "거절"; if (decision === "reject") button.className = "danger";
        button.onclick = () => { button.disabled = true; activeProgress.resume("승인된 작업을 진행하고 있습니다...");
          void fetchImpl(`/v1/approvals/${command.pendingApproval.id}/${decision}`,
            { method: "POST", headers: auth.headers(), body: JSON.stringify({ sessionId: session, commandId: command.commandId }) })
            .catch(() => activeProgress?.connectionLost());
          box.remove(); pollInFlight = false; poll(command.commandId); };
        box.append(documentAPI.createElement("br"), button); } activeProgress.root.append(box); }
    function add(text, kind = "aegis") { const element = documentAPI.createElement("div");
      element.className = `card ${kind}`; element.textContent = text; history.append(element);
      globalThis.scrollTo?.(0, documentAPI.body.scrollHeight); }
    function showClientError(message) { error.textContent = message; state.textContent = "클라이언트 오류"; add(message); }
    function finishActive() { clearTimeout(timer); pollInFlight = false; activeCommand = undefined;
      const sendButton = byId("send"); if (sendButton) sendButton.disabled = false;
      activeProgress = undefined;
      renderedApproval = undefined; pollAttempt = 0; }
    function createProgressCard(id) {
      const root = documentAPI.createElement("div"), title = documentAPI.createElement("div");
      const row = documentAPI.createElement("div"), spinner = documentAPI.createElement("span");
      const message = documentAPI.createElement("span"), elapsed = documentAPI.createElement("div");
      const step = documentAPI.createElement("div"), slow = documentAPI.createElement("div");
      const cancel = documentAPI.createElement("button"); let started = Date.now(), clock;
      root.className = "card progress-card"; title.className = "progress-title"; title.textContent = "Aegis 작업 중";
      row.className = "progress-row"; spinner.className = "spinner"; message.textContent = "요청을 확인하고 있습니다...";
      elapsed.className = "elapsed"; elapsed.textContent = "0초 경과"; step.className = "step";
      slow.className = "slow"; slow.textContent = "작업이 평소보다 오래 걸리고 있지만 계속 진행 중입니다.";
      cancel.textContent = "작업 취소"; cancel.hidden = true; cancel.onclick = () => { cancel.disabled = true;
        message.textContent = "취소 요청 중..."; void fetchImpl(`/v1/commands/${id}/cancel`, { method: "POST", headers: auth.headers() })
          .then(response => { if (!response.ok) throw new Error(); pollInFlight = false; poll(id); })
          .catch(() => { cancel.disabled = false; message.textContent = "취소 요청을 전달하지 못했습니다."; }); };
      row.append(spinner, message); root.append(title, row, elapsed, step, slow, cancel); history.append(root);
      clock = setInterval(() => { const seconds = Math.floor((Date.now() - started) / 1000);
        elapsed.textContent = formatElapsed(seconds); if (seconds >= 20) slow.style.display = "block"; }, 1000);
      return { root, update(command) { const progress = command.progress ?? { phase: command.status };
          spinner.hidden = false;
          message.textContent = progress.message || friendlyProgressLabel(progress.phase); cancel.hidden = !progress.cancellable;
          if (progress.startedAt) started = Date.parse(progress.startedAt) || started;
          step.textContent = progress.currentStep && progress.totalSteps ? `현재 작업 ${progress.currentStep} / ${progress.totalSteps}` : ""; },
        connectionLost() { spinner.hidden = true; message.textContent = "Gateway와 연결이 끊겼습니다. 재연결 중..."; cancel.hidden = true; },
        pauseForApproval() { spinner.hidden = true; cancel.hidden = true; message.textContent = "승인을 기다리고 있습니다."; },
        resume(value) { spinner.hidden = false; message.textContent = value; },
        finish(command) { clearInterval(clock); spinner.hidden = true; cancel.hidden = true; slow.style.display = "none";
          title.textContent = command.status === "completed" ? "✓ 작업 완료" : command.status === "cancelled" ? "작업 취소됨" : "✕ 작업 실패";
          message.textContent = command.messages?.join("\n") || friendlyProgressLabel(command.status); },
        fail(value) { clearInterval(clock); spinner.hidden = true; cancel.hidden = true; title.textContent = "✕ 작업 실패"; message.textContent = value; } };
    }
    void auth.autoConnect().then(result => result.kind === "connected" ? showConnected(result.device) : showRegistration());
    return { initialized: true };
  } catch { state.textContent = "Remote UI 초기화에 실패했습니다.";
    error.textContent = "필수 화면 요소를 초기화할 수 없습니다."; connectButton.disabled = true;
    return { initialized: false }; }
}

function readCredential(storage) { try { const value = JSON.parse(storage.getItem(DEVICE_CREDENTIAL_KEY) || "null");
  return value && typeof value.id === "string" && typeof value.credential === "string" ? value : undefined;
} catch { return undefined; } }
function removeCredential(storage) { try { storage.removeItem(DEVICE_CREDENTIAL_KEY); } catch {} }
function validIssuedCredential(value) { return typeof value?.device?.id === "string" &&
  typeof value.device.name === "string" && typeof value.credential === "string" && value.credential.length >= 43; }

export function compatibleStorage(source) {
  const memory = new Map(); let persistent;
  try { persistent = source ?? globalThis.localStorage;
    const probe = "aegis.remote.storageProbe"; persistent.setItem(probe, "1"); persistent.removeItem(probe);
  } catch { persistent = undefined; }
  return { persistent: Boolean(persistent),
    getItem(key) { try { return persistent?.getItem(key) ?? memory.get(key) ?? null; } catch { return memory.get(key) ?? null; } },
    setItem(key, value) { memory.set(key, value); try { persistent?.setItem(key, value); } catch {} },
    removeItem(key) { memory.delete(key); try { persistent?.removeItem(key); } catch {} },
  };
}

function installProgressStyles(documentAPI) {
  if (!documentAPI.head || documentAPI.getElementById("aegis-progress-styles")) return;
  const style = documentAPI.createElement("style"); style.id = "aegis-progress-styles";
  style.textContent = `.progress-row{display:flex;align-items:center;gap:10px}.spinner{width:16px;height:16px;border:2px solid #596582;border-top-color:#aeb7ff;border-radius:50%;animation:aegis-spin .8s linear infinite;flex:none}.progress-title{font-weight:700;margin-bottom:10px}.elapsed,.slow,.step{color:#aab3cb;font-size:13px;margin-top:8px}.slow{display:none}.progress-card button{min-height:44px;margin-top:12px}@keyframes aegis-spin{to{transform:rotate(360deg)}}@media(prefers-reduced-motion:reduce){.spinner{animation:none;border-top-color:#596582;background:#aeb7ff}}`;
  documentAPI.head.append(style);
}

if (typeof document !== "undefined") initializeRemoteUI();
