import { create } from "zustand";
import type { DeviceCredential } from "@/entities/device/model/types";
import type { RemoteChatMessage } from "@/entities/message/model/types";
import type { CommandFailureCode, CommandStatus, RemoteCommand } from "@/entities/command/model/types";
import type { ConnectionState } from "@/entities/connection/model/types";
import { createId } from "@/shared/lib/createId";

export interface LastCommandOutcome { status: CommandStatus; failureCode?: CommandFailureCode }

interface RemoteSessionState {
  sessionId: string;
  gatewayURL?: string;
  credential?: DeviceCredential;
  connection: ConnectionState;
  messages: RemoteChatMessage[];
  active?: RemoteCommand;
  lastCommand?: LastCommandOutcome;
  setGatewayURL(value?: string): void;
  setCredential(value?: DeviceCredential): void;
  setConnection(value: ConnectionState): void;
  addMessage(value: RemoteChatMessage): void;
  setActive(value?: RemoteCommand): void;
  setLastCommand(value?: LastCommandOutcome): void;
  restoreActive(sessionId: string, commandId: string, startedAt: string): void;
  newConversation(): void;
}

export const useRemoteSession = create<RemoteSessionState>(set => ({
  sessionId: createId(), connection: "disconnected", messages: [],
  setGatewayURL: gatewayURL => set({ gatewayURL }),
  setCredential: credential => set({ credential }), setConnection: connection => set({ connection }),
  addMessage: value => set(state => ({ messages: [...state.messages, value].slice(-100) })),
  setActive: active => set({ active }),
  setLastCommand: lastCommand => set({ lastCommand }),
  restoreActive: (sessionId, commandId, startedAt) => set({ sessionId, active: { commandId, status: "running", messages: [],
    progress: { phase: "running", message: "진행 중인 작업을 복구하고 있습니다...", cancellable: false, startedAt } } }),
  newConversation: () => set({ sessionId: createId(), messages: [], active: undefined }),
}));
