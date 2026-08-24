import { Alert, Modal, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import type { ConnectionState } from "@/entities/connection/model/types";
import type { DeviceCredential } from "@/entities/device/model/types";
import type { LastCommandOutcome } from "@/features/commands/model/sessionStore";
import { AegisButton } from "@/shared/ui/AegisButton";
import { colors } from "@/shared/ui/theme";
import { DebugDiagnostics } from "./DebugDiagnostics";

export function SettingsSheet({ visible, gatewayURL, credential, connection, lastCommand, onClose, onTest, onDisconnect }: {
  visible: boolean; gatewayURL?: string; credential?: DeviceCredential; connection: ConnectionState;
  lastCommand?: LastCommandOutcome; onClose(): void; onTest(): Promise<unknown>; onDisconnect(): Promise<void>;
}) {
  const confirmDisconnect = () => Alert.alert("이 기기 연결 해제", "Gateway 등록과 보안 자격 증명을 삭제할까요?", [
    { text: "취소", style: "cancel" }, { text: "연결 해제", style: "destructive", onPress: () => void onDisconnect() },
  ]);
  return <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
    <View style={styles.screen}><View style={styles.header}><Text style={styles.title}>설정</Text>
      <TouchableOpacity style={styles.close} onPress={onClose}><Text style={styles.closeText}>닫기</Text></TouchableOpacity></View>
      <Row label="Gateway" value={gatewayURL ?? "등록되지 않음"} mono />
      <Row label="Device" value={credential?.deviceName ?? "등록되지 않음"} />
      <Row label="Connection" value={connection} />
      <View style={styles.actions}><AegisButton title="연결 테스트" onPress={() => void onTest()
        .then(() => Alert.alert("연결됨", "Gateway 연결이 정상입니다."))
        .catch(error => Alert.alert("연결 실패", error instanceof Error ? error.message : "Gateway 상태를 확인하세요."))} />
        <AegisButton title="이 기기 연결 해제" danger onPress={confirmDisconnect} /></View>
      <Text style={styles.note}>기기 자격 증명은 OS 보안 저장소에만 저장됩니다. Master Token은 저장하지 않습니다.</Text>
      <DebugDiagnostics connection={connection} lastCommand={lastCommand} />
    </View></Modal>;
}
function Row({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) {
  return <View style={styles.row}><Text style={styles.label}>{label}</Text><Text style={[styles.value, mono && styles.mono]}>{value}</Text></View>;
}
const styles = StyleSheet.create({ screen: { flex: 1, backgroundColor: colors.background, padding: 22, gap: 12 },
  header: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: 14 },
  title: { color: colors.text, fontSize: 28, fontWeight: "800" }, close: { minHeight: 44, justifyContent: "center", paddingHorizontal: 8 },
  closeText: { color: colors.accent, fontWeight: "700" }, row: { padding: 16, borderRadius: 14, backgroundColor: colors.surface,
    borderWidth: 1, borderColor: colors.border, gap: 6 }, label: { color: colors.muted, fontSize: 12 },
  value: { color: colors.text, fontSize: 16 }, mono: { fontFamily: "monospace", fontSize: 13 }, actions: { gap: 10, marginTop: 10 },
  note: { color: colors.muted, lineHeight: 19, fontSize: 12 } });
