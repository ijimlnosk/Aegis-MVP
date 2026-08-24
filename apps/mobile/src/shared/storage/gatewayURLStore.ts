import * as Keychain from "react-native-keychain";

const service = "aegis.remote.gatewayURL.v1";

// Kept separate from deviceCredentialStore: discarding an invalid device
// credential (deviceCredentialInvalid/deviceRevoked/deviceDisabled) must never
// force the user to re-type the Gateway URL.
export const gatewayURLStore = {
  async load(): Promise<string | undefined> {
    const result = await Keychain.getGenericPassword({ service });
    return result ? result.password : undefined;
  },
  async save(value: string) { await Keychain.setGenericPassword("gatewayURL", value, { service }); },
  async clear() { await Keychain.resetGenericPassword({ service }); },
};
