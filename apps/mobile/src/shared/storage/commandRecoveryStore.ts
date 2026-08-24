import * as Keychain from "react-native-keychain";
import { parseRecoverableCommand, type RecoverableCommand } from "./credentialParsing";

const service = "aegis.remote.activeCommand.v1";
export type { RecoverableCommand };

export const commandRecoveryStore = {
  async load(): Promise<RecoverableCommand | undefined> {
    const result = await Keychain.getGenericPassword({ service });
    return result ? parseRecoverableCommand(result.password) : undefined;
  },
  async save(value: RecoverableCommand) { await Keychain.setGenericPassword("activeCommand", JSON.stringify(value), { service }); },
  async clear() { await Keychain.resetGenericPassword({ service }); },
};
