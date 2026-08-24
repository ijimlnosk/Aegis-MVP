import * as Keychain from "react-native-keychain";
import type { DeviceCredential } from "@/entities/device/model/types";
import { parseDeviceCredential } from "./credentialParsing";

const service = "aegis.remote.deviceCredential.v1";

export const deviceCredentialStore = {
  async load(): Promise<DeviceCredential | undefined> {
    const result = await Keychain.getGenericPassword({ service });
    return result ? parseDeviceCredential(result.password) : undefined;
  },
  async save(value: DeviceCredential) {
    await Keychain.setGenericPassword(value.deviceId, JSON.stringify(value), {
      service, accessible: Keychain.ACCESSIBLE.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
    });
  },
  async clear() { await Keychain.resetGenericPassword({ service }); },
};
