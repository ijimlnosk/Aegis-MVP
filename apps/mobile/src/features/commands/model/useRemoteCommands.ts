import { AppState } from "react-native";
import { useCallback, useEffect, useMemo, useRef } from "react";
import { AegisRemoteClient } from "@/shared/api/aegisRemoteClient";
import { RemoteError, requiresReRegistration } from "@/shared/api/remoteError";
import { deviceCredentialStore } from "@/shared/storage/deviceCredentialStore";
import { gatewayURLStore } from "@/shared/storage/gatewayURLStore";
import { commandRecoveryStore } from "@/shared/storage/commandRecoveryStore";
import { createId } from "@/shared/lib/createId";
import { terminalCommandContent } from "@/entities/command/model/failureMessages";
import { useRemoteSession } from "./sessionStore";
import { pollDelay } from "./progress";
import { connectionStateFor } from "./connectionState";
import { useConnectionMonitor } from "./useConnectionMonitor";

const TERMINAL_STATUSES: ReadonlySet<string> = new Set(["completed", "failed", "cancelled"]);

// Bounded, secret-free diagnostics for physical-device debugging (dev builds only).
// Never logs the master token, device credential, bridge token, or message content.
function logCommandOutcome(commandId: string, sessionId: string, status: string, failureCode?: string) {
  if (!__DEV__) return;
  console.log("[AegisRemote]", { commandId, sessionPrefix: sessionId.slice(0, 8), status, failureCode: failureCode ?? null });
}

export function useRemoteCommands() {
  // Selected individually (not the whole store) so each callback/effect below only
  // depends on values that are stable across unrelated store updates. Depending on
  // the whole store snapshot previously made the status-check effect re-fire on its
  // own setConnection() call, looping /v1/status forever and exhausting the Gateway's
  // rate limiter -- every real command then got a 429, shown as a generic failure.
  const sessionId = useRemoteSession(value => value.sessionId);
  const gatewayURL = useRemoteSession(value => value.gatewayURL);
  const credential = useRemoteSession(value => value.credential);
  const connection = useRemoteSession(value => value.connection);
  const messages = useRemoteSession(value => value.messages);
  const active = useRemoteSession(value => value.active);
  const lastCommand = useRemoteSession(value => value.lastCommand);
  const setGatewayURL = useRemoteSession(value => value.setGatewayURL);
  const setCredential = useRemoteSession(value => value.setCredential);
  const setConnection = useRemoteSession(value => value.setConnection);
  const screenLocked = useRemoteSession(value => value.screenLocked);
  const setScreenLocked = useRemoteSession(value => value.setScreenLocked);
  const addMessage = useRemoteSession(value => value.addMessage);
  const setActive = useRemoteSession(value => value.setActive);
  const setLastCommand = useRemoteSession(value => value.setLastCommand);
  const newConversation = useRemoteSession(value => value.newConversation);

  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const attempts = useRef(0); const polling = useRef(false);
  // setActive() intentionally renders immediate feedback before the POST returns.
  // Do not let the active-command effect poll that id before the Gateway has
  // accepted it, otherwise the initial GET races the POST and returns 404.
  const pendingSubmissionIds = useRef<Set<string>>(new Set());
  // A fresh send() and the activeCommandId-change effect below can both start polling
  // the same command around the same time; this makes the terminal (completed/failed/
  // cancelled) handling idempotent so an overlapping poll never adds a second chat message.
  const finalizedCommandIds = useRef<Set<string>>(new Set());
  const pollRef = useRef<(id: string) => Promise<void>>(async () => undefined);
  const activeCommandId = active?.commandId;
  const client = useMemo(() => credential && gatewayURL
    ? new AegisRemoteClient(gatewayURL, credential) : undefined, [gatewayURL, credential]);

  // Only the device credential is invalid here; the Gateway URL is left in place
  // (see requiresReRegistration) so re-registration doesn't ask for it again,
  // and we stop -- no retry loop against a credential we know is bad.
  const disconnectInvalid = useCallback(async (error: unknown) => {
    if (error instanceof RemoteError && requiresReRegistration(error.code)) {
      await Promise.all([deviceCredentialStore.clear(), commandRecoveryStore.clear()]);
      setCredential(); setConnection(error.code); return true;
    }
    return false;
  }, [setCredential, setConnection]);
  const restartStatusCheck = useConnectionMonitor(client, disconnectInvalid, setConnection, setScreenLocked);

  const poll = useCallback(async (id: string) => {
    if (!client || polling.current) return; polling.current = true;
    try { const command = await client.command(id); setActive(command); setConnection("connected");
      if (TERMINAL_STATUSES.has(command.status)) {
        if (finalizedCommandIds.current.has(id)) { setActive(); await commandRecoveryStore.clear(); return; }
        finalizedCommandIds.current.add(id);
        logCommandOutcome(id, sessionId, command.status, command.failureCode);
        addMessage({ id: createId(), role: command.status === "completed" ? "assistant" : "error",
          content: terminalCommandContent(command), createdAt: new Date().toISOString(), commandId: id, status: command.status });
        setLastCommand({ status: command.status, failureCode: command.failureCode });
        setActive(); await commandRecoveryStore.clear(); attempts.current = 0;
        restartStatusCheck(); return;
      }
      timer.current = setTimeout(() => void pollRef.current(id), pollDelay(++attempts.current, command.status === "awaitingApproval"));
    } catch (error) { if (error instanceof RemoteError && error.code === "commandNotFound") {
        setActive(); await commandRecoveryStore.clear();
        addMessage({ id: createId(), role: "error", content: error.message, createdAt: new Date().toISOString(), commandId: id });
      } else if (!await disconnectInvalid(error)) {
        setConnection("reconnecting"); timer.current = setTimeout(() => void pollRef.current(id), 3_000); } }
    finally { polling.current = false; }
  }, [client, disconnectInvalid, sessionId, setActive, setConnection, addMessage, setLastCommand, restartStatusCheck]);
  useEffect(() => { pollRef.current = poll; }, [poll]);

  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);


  useEffect(() => {
    if (client && activeCommandId && !pendingSubmissionIds.current.has(activeCommandId)) {
      void pollRef.current(activeCommandId);
    }
  }, [activeCommandId, client]);
  useEffect(() => { const subscription = AppState.addEventListener("change", value => {
    if (value !== "active") return;
    if (active) { polling.current = false; void poll(active.commandId); }
    // Always re-check on resume: even when connected, the Mac may have locked meanwhile.
    else restartStatusCheck();
  }); return () => subscription.remove(); }, [poll, active, restartStatusCheck]);

  const send = async (text: string) => {
    if (!client || active) return false;
    const id = createId(), now = new Date().toISOString();
    pendingSubmissionIds.current.add(id);
    addMessage({ id: createId(), role: "user", content: text, createdAt: now, commandId: id });
    setActive({ commandId: id, status: "planning", messages: [], progress: {
      phase: "planning", message: "요청을 확인하고 있습니다...", cancellable: true, startedAt: now } });
    await commandRecoveryStore.save({ commandId: id, sessionId, startedAt: now });
    // setActive() above already changed activeCommandId, so the effect below also starts
    // polling this same command -- both racing is fine (see finalizedCommandIds above),
    // and calling poll() here too means real polling doesn't wait on that effect alone.
    try {
      await client.send(id, sessionId, text);
      pendingSubmissionIds.current.delete(id);
      void poll(id);
      return true;
    }
    catch (error) { setActive(); await commandRecoveryStore.clear();
      pendingSubmissionIds.current.delete(id);
      if (!await disconnectInvalid(error)) { setConnection(connectionStateFor(error));
        addMessage({ id: createId(), role: "error", content: error instanceof Error ? error.message : "명령을 전송하지 못했습니다.", createdAt: now, commandId: id }); }
      return false; }
  };
  const decide = async (accepted: boolean) => { const command = active, approval = command?.pendingApproval;
    if (!client || !command || !approval) return;
    setActive({ ...command, status: "running", pendingApproval: undefined,
      progress: { phase: "running", message: "승인된 작업을 진행하고 있습니다...", cancellable: true,
        startedAt: command.progress?.startedAt ?? new Date().toISOString() } });
    void client.approve(command.commandId, sessionId, approval.id, accepted).catch(() => undefined);
    polling.current = false; void poll(command.commandId);
  };
  const cancel = async () => { if (!client || !active) return; const command = active;
    setActive({ ...command, progress: { ...command.progress!, phase: "running", message: "취소 요청 중...", cancellable: false } });
    try { await client.cancel(command.commandId); } catch (error) {
      if (error instanceof RemoteError && error.code === "commandNotFound") {
        setActive(); await commandRecoveryStore.clear();
        addMessage({ id: createId(), role: "error", content: error.message, createdAt: new Date().toISOString(), commandId: command.commandId });
        return;
      }
      setActive(command); addMessage({ id: createId(), role: "error", content: error instanceof Error ? error.message : "취소 요청을 전송하지 못했습니다.", createdAt: new Date().toISOString(), commandId: command.commandId });
      return;
    }
    polling.current = false; void poll(command.commandId); };
  const testConnection = async () => client?.status();
  const disconnect = async () => { if (client && credential) await client.revoke().catch(() => undefined);
    await Promise.all([deviceCredentialStore.clear(), gatewayURLStore.clear(), commandRecoveryStore.clear()]);
    newConversation(); setCredential(); setGatewayURL();
    setConnection("deviceCredentialInvalid"); };
  return { sessionId, gatewayURL, credential, connection, screenLocked, messages, active,
    lastCommand, send, decide, cancel, testConnection, disconnect };
}
