import { StyleSheet, Text, View } from "react-native";
import type { RemoteApproval } from "@/entities/approval/model/types";
import { AegisButton } from "@/shared/ui/AegisButton";
import { colors } from "@/shared/ui/theme";

export function ApprovalCard({ approval, onDecision, onCancel }: {
  approval: RemoteApproval; onDecision(accepted: boolean): void; onCancel?: () => void;
}) {
  const action = approval.risk === "remoteMutation" ? "Push" : approval.title.includes("커밋") ? "커밋 진행" : "승인";
  return <View style={styles.card}><Text style={styles.title}>{approval.title}</Text>
    <Text style={styles.project}>{approval.scope}</Text><Text style={styles.label}>목표</Text>
    <Text style={styles.value}>{approval.goal}</Text><Text style={styles.label}>위험도</Text>
    <Text style={styles.value}>{approval.risk}</Text><View style={styles.actions}>
      <View style={styles.button}><AegisButton title="거절" danger onPress={() => onDecision(false)} /></View>
      <View style={styles.button}><AegisButton title={action} onPress={() => onDecision(true)} /></View>
    </View>{onCancel ? <AegisButton title="작업 취소" danger onPress={onCancel} /> : null}</View>;
}
const styles = StyleSheet.create({ card: { backgroundColor: colors.elevated, borderColor: colors.warning,
  borderWidth: 1, borderRadius: 16, padding: 16, gap: 8 }, title: { color: colors.text, fontSize: 18, fontWeight: "800" },
  project: { color: colors.accent, fontWeight: "700" }, label: { color: colors.muted, fontSize: 12, marginTop: 4 },
  value: { color: colors.text, lineHeight: 20 }, actions: { flexDirection: "row", gap: 10, marginTop: 8 }, button: { flex: 1 } });
