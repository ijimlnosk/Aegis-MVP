import { Pressable, StyleSheet, Text, View } from "react-native";
import type { ConnectionState } from "../model/types";
import { colors } from "@/shared/ui/theme";

export function ConnectionHeader({ state, onSettings }: { state: ConnectionState; onSettings(): void }) {
  const connected = state === "connected"; const labels: Record<ConnectionState, string> = {
    connected: "연결됨", connecting: "연결 중", reconnecting: "재연결 중", disconnected: "연결 안 됨",
    gatewayUnavailable: "Gateway 연결 안 됨", desktopUnavailable: "Mac 연결 안 됨", deviceCredentialInvalid: "등록 필요",
    deviceRevoked: "연결 해제됨", deviceDisabled: "비활성화됨", authenticationFailed: "인증 실패", gatewayServerError: "Gateway 오류" };
  return <View style={styles.header}><View><Text style={styles.title}>Aegis</Text><View style={styles.status}>
    <View style={[styles.dot, { backgroundColor: connected ? colors.success : colors.warning }]} />
    <Text style={styles.label}>{labels[state]}</Text></View></View>
    <Pressable onPress={onSettings} hitSlop={12}><Text style={styles.settings}>설정</Text></Pressable></View>;
}
const styles = StyleSheet.create({ header: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingBottom: 12 },
  title: { color: colors.text, fontSize: 25, fontWeight: "800" }, status: { flexDirection: "row", alignItems: "center", gap: 6 },
  dot: { width: 8, height: 8, borderRadius: 4 }, label: { color: colors.muted, fontSize: 12 }, settings: { color: colors.accent, padding: 10 } });
