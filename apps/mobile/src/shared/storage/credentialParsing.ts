import type { DeviceCredential } from "@/entities/device/model/types";

export interface RecoverableCommand { commandId: string; sessionId: string; startedAt: string }

export function parseDeviceCredential(raw: string): DeviceCredential | undefined {
  try { const value = JSON.parse(raw) as DeviceCredential;
    return value.deviceId && value.credential ? value : undefined;
  } catch { return undefined; }
}

export function parseRecoverableCommand(raw: string): RecoverableCommand | undefined {
  try { const value = JSON.parse(raw) as RecoverableCommand;
    return value.commandId && value.sessionId && value.startedAt ? value : undefined;
  } catch { return undefined; }
}
