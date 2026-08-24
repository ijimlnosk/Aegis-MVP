import { useEffect } from "react";
import { ActivityIndicator, StyleSheet, View } from "react-native";
import { useRemoteSession } from "@/features/commands/model/sessionStore";
import { SetupScreen } from "@/features/device-registration/ui/SetupScreen";
import { ChatScreen } from "@/features/chat/ui/ChatScreen";
import { colors } from "@/shared/ui/theme";
import { requiresReRegistration } from "@/shared/api/remoteError";
import { deviceCredentialStore } from "@/shared/storage/deviceCredentialStore";
import { gatewayURLStore } from "@/shared/storage/gatewayURLStore";
import { commandRecoveryStore } from "@/shared/storage/commandRecoveryStore";

export function RootNavigator() {
  const connection = useRemoteSession(value => value.connection);
  const credential = useRemoteSession(value => value.credential);
  const setGatewayURL = useRemoteSession(value => value.setGatewayURL);
  const setCredential = useRemoteSession(value => value.setCredential);
  const setConnection = useRemoteSession(value => value.setConnection);
  const restoreActive = useRemoteSession(value => value.restoreActive);
  useEffect(() => { void Promise.all([gatewayURLStore.load(), deviceCredentialStore.load(), commandRecoveryStore.load()])
    .then(([gatewayURL, value, recovery]) => {
      if (gatewayURL) setGatewayURL(gatewayURL);
      if (value) { setCredential(value); setConnection("connecting");
        if (recovery) restoreActive(recovery.sessionId, recovery.commandId, recovery.startedAt); }
      else setConnection("deviceCredentialInvalid");
    }).catch(() => setConnection("deviceCredentialInvalid"));
  }, [restoreActive, setConnection, setCredential, setGatewayURL]);
  if (connection === "disconnected" && !credential) return <View style={styles.loading}><ActivityIndicator color={colors.accent} /></View>;
  if (!credential || requiresReRegistration(connection)) return <SetupScreen />;
  return <ChatScreen />;
}
const styles = StyleSheet.create({ loading: { flex: 1, alignItems: "center", justifyContent: "center", backgroundColor: colors.background } });
