import { useEffect, useState } from "react";
import { StyleSheet, Text, View } from "react-native";
import type { RemoteApproval } from "@/entities/approval/model/types";
import { presentApproval, remainingText } from "@/entities/approval/model/approvalPresentation";
import { AegisButton } from "@/shared/ui/AegisButton";
import { colors } from "@/shared/ui/theme";

export function ApprovalCard({ approval, onDecision, onCancel }: {
  approval: RemoteApproval; onDecision(accepted: boolean): void; onCancel?: () => void;
}) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const timer = setInterval(() => setNow(Date.now()), 1_000); return () => clearInterval(timer); }, []);
  const presentation = presentApproval(approval.risk);
  const remaining = remainingText(approval.expiresAt, now);
  const expired = remaining === undefined && Boolean(approval.expiresAt);
  return <View style={[styles.card, presentation.irreversible && styles.irreversible]}>
    <Text style={styles.title}>{approval.title}</Text>
    <Text style={styles.project}>{approval.scope}</Text>
    <Text style={[styles.effect, presentation.irreversible && styles.effectStrong]}>승인하면: {presentation.effect}</Text>
    {approval.goal ? <><Text style={styles.label}>내용</Text><Text selectable style={styles.value}>{approval.goal}</Text></> : null}
    <Text style={expired ? styles.expired : styles.remaining}>
      {expired ? "승인 시간이 지났습니다. 같은 요청을 다시 보내 주세요." : remaining}</Text>
    <View style={styles.actions}>
      <View style={styles.button}><AegisButton title="거절" secondary onPress={() => onDecision(false)} /></View>
      <View style={styles.button}><AegisButton title={presentation.confirmLabel} danger={presentation.irreversible}
        disabled={expired} accessibilityLabel={`${presentation.confirmLabel} 승인`} onPress={() => onDecision(true)} /></View>
    </View>
    {onCancel ? <AegisButton title="작업 전체 취소" secondary onPress={onCancel} /> : null}
  </View>;
}
const styles = StyleSheet.create({ card: { backgroundColor: colors.elevated, borderColor: colors.warning,
  borderWidth: 1, borderRadius: 16, padding: 16, gap: 8 }, irreversible: { borderColor: colors.error },
  title: { color: colors.text, fontSize: 18, fontWeight: "800" }, project: { color: colors.accent, fontWeight: "700" },
  effect: { color: colors.text, lineHeight: 20 }, effectStrong: { color: colors.error, fontWeight: "700" },
  label: { color: colors.muted, fontSize: 12, marginTop: 4 }, value: { color: colors.text, lineHeight: 20 },
  remaining: { color: colors.muted, fontSize: 12 }, expired: { color: colors.warning, lineHeight: 19 },
  actions: { flexDirection: "row", gap: 10, marginTop: 8 }, button: { flex: 1 } });
