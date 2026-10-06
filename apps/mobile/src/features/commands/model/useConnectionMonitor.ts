import { useCallback, useEffect, useRef } from "react";
import type { AegisRemoteClient } from "@/shared/api/aegisRemoteClient";
import type { ConnectionState } from "@/entities/connection/model/types";
import { connectionStateFor } from "./connectionState";
import { reconnectDelay } from "./progress";

// Self-scheduling: on any non-"connected" outcome it reschedules itself with backoff
// instead of leaving a stale error on screen forever. Triggered by `client` identity
// changes (new credential/gatewayURL) and by the returned restart function (foreground
// resume, finished commands) -- never by its own setConnection() call, so it can't
// loop tight like the bug this replaced.
export function useConnectionMonitor(client: AegisRemoteClient | undefined,
  disconnectInvalid: (error: unknown) => Promise<boolean>,
  setConnection: (value: ConnectionState) => void, setScreenLocked: (value: boolean) => void) {
  const statusTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const statusAttempts = useRef(0);
  const checkStatusRef = useRef<() => void>(() => undefined);

  const checkStatus = useCallback(() => {
    if (!client) return;
    void client.status().then(status => { statusAttempts.current = 0;
      setScreenLocked(status.screenLocked === true);
      setConnection(status.desktopBridge === "reachable" ? "connected" : "desktopUnavailable");
      if (status.desktopBridge !== "reachable") {
        statusTimer.current = setTimeout(() => checkStatusRef.current(), reconnectDelay(++statusAttempts.current));
      }
    }).catch(error => void disconnectInvalid(error).then(handled => { if (handled) return;
      setConnection(connectionStateFor(error));
      statusTimer.current = setTimeout(() => checkStatusRef.current(), reconnectDelay(++statusAttempts.current));
    }));
  }, [client, disconnectInvalid, setConnection, setScreenLocked]);
  useEffect(() => { checkStatusRef.current = checkStatus; }, [checkStatus]);
  useEffect(() => { statusAttempts.current = 0; checkStatusRef.current();
    return () => { if (statusTimer.current) clearTimeout(statusTimer.current); }; }, [client]);

  return useCallback(() => {
    if (statusTimer.current) clearTimeout(statusTimer.current);
    statusAttempts.current = 0; checkStatusRef.current();
  }, []);
}
