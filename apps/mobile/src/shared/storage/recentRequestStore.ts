import * as Keychain from "react-native-keychain";
import { parseRecentRequests } from "@/entities/command/model/recentRequests";

const service = "aegis.remote.recentRequests.v1";

export const recentRequestStore = {
  async load(): Promise<string[]> {
    const result = await Keychain.getGenericPassword({ service });
    return parseRecentRequests(result ? result.password : undefined);
  },
  async save(values: string[]) { await Keychain.setGenericPassword("recentRequests", JSON.stringify(values), { service }); },
  async clear() { await Keychain.resetGenericPassword({ service }); },
};
