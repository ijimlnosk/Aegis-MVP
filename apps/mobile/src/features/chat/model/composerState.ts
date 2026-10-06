import type { ConnectionState } from "@/entities/connection/model/types";
import type { RemoteCommand } from "@/entities/command/model/types";

/** Why the composer is blocked, in words, or undefined when the user can send. */
export function composerBlockReason(connection: ConnectionState, active?: RemoteCommand): string | undefined {
  if (active?.pendingApproval) return "위 승인 카드에서 먼저 결정해 주세요.";
  if (active) return "Aegis가 작업 중입니다. 끝나면 다시 보낼 수 있어요.";
  if (connection === "connected") return undefined;
  if (connection === "connecting" || connection === "reconnecting") return "Mac에 연결하는 중입니다…";
  if (connection === "desktopUnavailable") return "Mac의 AegisDesktop에 연결되지 않습니다. Mac이 켜져 있는지 확인해 주세요.";
  return "연결되지 않았습니다. 설정에서 연결 상태를 확인해 주세요.";
}
