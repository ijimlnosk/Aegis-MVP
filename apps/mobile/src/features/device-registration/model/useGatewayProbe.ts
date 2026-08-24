import { useEffect, useState } from "react";
import { AegisRemoteClient } from "@/shared/api/aegisRemoteClient";
import { RemoteError } from "@/shared/api/remoteError";
import { normalizeGatewayURL } from "@/shared/lib/gatewayURL";

export type GatewayProbeStatus = "idle" | "checking" | "connected" | "deviceCredentialInvalid" |
  "deviceRevoked" | "deviceDisabled" | "authenticationFailed" | "gatewayServerError" | "gatewayUnavailable";

// Unauthenticated /v1/status probe used before device registration: a 401
// deviceCredentialInvalid response still proves the Gateway is reachable, so
// registration must stay available -- only a fetch()/network failure means
// the Gateway itself is unreachable.
export function useGatewayProbe(gateway: string): GatewayProbeStatus {
  const [status, setStatus] = useState<GatewayProbeStatus>("idle");
  useEffect(() => {
    let cancelled = false; let url: string;
    try { url = normalizeGatewayURL(gateway); } catch { setStatus("idle"); return; }
    setStatus("checking");
    const timer = setTimeout(() => {
      void new AegisRemoteClient(url).status()
        .then(() => !cancelled && setStatus("connected"))
        .catch((error: unknown) => { if (cancelled) return;
          setStatus(error instanceof RemoteError ? error.code as GatewayProbeStatus : "gatewayUnavailable"); });
    }, 500);
    return () => { cancelled = true; clearTimeout(timer); };
  }, [gateway]);
  return status;
}
