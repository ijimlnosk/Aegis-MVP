import { StyleSheet, Text, View } from "react-native";
import type { ConnectionState } from "@/entities/connection/model/types";
import { connectionDiagnostics } from "@/entities/connection/model/diagnostics";
import type { LastCommandOutcome } from "@/features/commands/model/sessionStore";
import { colors } from "@/shared/ui/theme";

// Development-only diagnostics (never shown in a release build, never a credential/token).
export function DebugDiagnostics({ connection, lastCommand }: { connection: ConnectionState; lastCommand?: LastCommandOutcome }) {
  if (!__DEV__) return null;
  const diagnostics = connectionDiagnostics(connection);
  return <View style={styles.box}>
    <Text style={styles.title}>진단 (개발 모드)</Text>
    <Line label="Gateway" value={diagnostics.gateway} />
    <Line label="Authentication" value={diagnostics.authentication} />
    <Line label="Desktop Bridge" value={diagnostics.desktopBridge} />
    <Line label="Last command" value={lastCommand?.status ?? "없음"} />
    <Line label="Last failure" value={lastCommand?.failureCode ?? "없음"} />
  </View>;
}
function Line({ label, value }: { label: string; value: string }) {
  return <Text style={styles.line}>{label}: <Text style={styles.value}>{value}</Text></Text>;
}
const styles = StyleSheet.create({ box: { backgroundColor: colors.background, borderColor: colors.border,
  borderWidth: 1, borderRadius: 12, padding: 12, gap: 4 },
  title: { color: colors.warning, fontSize: 12, fontWeight: "700", marginBottom: 2 },
  line: { color: colors.muted, fontSize: 12 }, value: { color: colors.text, fontWeight: "600" } });
