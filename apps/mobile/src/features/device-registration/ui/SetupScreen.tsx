import { useState } from "react";
import { KeyboardAvoidingView, Platform, StyleSheet, Text, TextInput, View } from "react-native";
import { AegisRemoteClient } from "@/shared/api/aegisRemoteClient";
import { normalizeGatewayURL } from "@/shared/lib/gatewayURL";
import { deviceCredentialStore } from "@/shared/storage/deviceCredentialStore";
import { gatewayURLStore } from "@/shared/storage/gatewayURLStore";
import { useRemoteSession } from "@/features/commands/model/sessionStore";
import { AegisButton } from "@/shared/ui/AegisButton";
import { colors } from "@/shared/ui/theme";
import { useGatewayProbe } from "../model/useGatewayProbe";
import { gatewayDiagnostics } from "../model/gatewayDiagnostics";

export function SetupScreen() {
  const storedGatewayURL = useRemoteSession(value => value.gatewayURL);
  const setGatewayURL = useRemoteSession(value => value.setGatewayURL);
  const setCredential = useRemoteSession(value => value.setCredential);
  const setConnection = useRemoteSession(value => value.setConnection);
  const [gateway, setGateway] = useState(storedGatewayURL ?? ""); const [token, setToken] = useState("");
  const [name, setName] = useState(""); const [error, setError] = useState(""); const [busy, setBusy] = useState(false);
  const probe = useGatewayProbe(gateway);
  const diagnostics = gatewayDiagnostics(probe, gateway.trim().toLowerCase().startsWith("https://"));

  const register = async () => { setBusy(true); setError(""); const master = token; setToken("");
    try { const gatewayURL = normalizeGatewayURL(gateway);
      const result = await AegisRemoteClient.register(gatewayURL, master, name);
      const credential = { deviceId: result.device.id, deviceName: result.device.name, credential: result.credential };
      await Promise.all([deviceCredentialStore.save(credential), gatewayURLStore.save(gatewayURL)]);
      setGatewayURL(gatewayURL); setCredential(credential);
      // Retry /v1/status (now authenticated) rather than assuming success --
      // useRemoteCommands' status effect resolves this to connected/desktopUnavailable.
      setConnection("connecting");
    } catch (value) { setError(value instanceof Error ? value.message : "기기 등록에 실패했습니다."); }
    finally { setBusy(false); } };

  return <KeyboardAvoidingView style={styles.screen} behavior={Platform.OS === "ios" ? "padding" : undefined}>
    <View style={styles.card}><Text style={styles.brand}>AEGIS REMOTE</Text><Text style={styles.title}>Mac에 연결</Text>
      {probe === "deviceCredentialInvalid" ? <Text style={styles.banner}>Gateway 연결됨 · 기기 등록 필요</Text> : null}
      <Text style={styles.label}>Gateway 주소</Text><TextInput value={gateway} onChangeText={setGateway}
        autoCapitalize="none" keyboardType="url" placeholder="https://your-mac.tailnet-name.ts.net" placeholderTextColor={colors.muted} style={styles.input} />
      <Text style={styles.label}>기기 이름</Text><TextInput value={name} onChangeText={setName}
        placeholder="Galaxy Fold / iPhone" placeholderTextColor={colors.muted} style={styles.input} />
      <Text style={styles.label}>Master Remote Token</Text><TextInput value={token} onChangeText={setToken}
        secureTextEntry autoCapitalize="none" placeholder="최초 등록에만 사용" placeholderTextColor={colors.muted} style={styles.input} />
      {error ? <Text style={styles.error}>{error}</Text> : null}
      <AegisButton title={busy ? "등록 중..." : "이 기기 등록"} disabled={busy || !gateway || !token} onPress={() => void register()} />
      {diagnostics ? <View style={styles.diagnostics}>
        <DiagnosticRow label="Gateway" value={diagnostics.gateway} />
        <DiagnosticRow label="HTTPS" value={diagnostics.https} />
        <DiagnosticRow label="Authentication" value={diagnostics.authentication} />
      </View> : null}
      <Text style={styles.note}>Master Token은 저장되지 않습니다. Tailscale 연결이 필요합니다.</Text>
    </View></KeyboardAvoidingView>;
}
function DiagnosticRow({ label, value }: { label: string; value: string }) {
  return <Text style={styles.diagnosticRow}>{label}: <Text style={styles.diagnosticValue}>{value}</Text></Text>;
}
const styles = StyleSheet.create({ screen: { flex: 1, backgroundColor: colors.background, justifyContent: "center", padding: 22 },
  card: { backgroundColor: colors.surface, borderColor: colors.border, borderWidth: 1, borderRadius: 20, padding: 20, gap: 10 },
  brand: { color: colors.accent, fontWeight: "800", letterSpacing: 2 }, title: { color: colors.text, fontSize: 26, fontWeight: "700", marginBottom: 10 },
  banner: { color: colors.success, fontSize: 13, fontWeight: "700", marginBottom: 4 },
  label: { color: colors.muted, fontSize: 13 }, input: { minHeight: 48, color: colors.text, backgroundColor: colors.background,
    borderColor: colors.border, borderWidth: 1, borderRadius: 12, paddingHorizontal: 14 }, error: { color: colors.error },
  diagnostics: { backgroundColor: colors.background, borderColor: colors.border, borderWidth: 1, borderRadius: 12, padding: 12, gap: 4 },
  diagnosticRow: { color: colors.muted, fontSize: 12 }, diagnosticValue: { color: colors.text, fontWeight: "600" },
  note: { color: colors.muted, fontSize: 12, lineHeight: 18, marginTop: 4 } });
