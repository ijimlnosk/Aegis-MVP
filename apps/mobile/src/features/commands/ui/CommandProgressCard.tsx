import { useEffect, useState } from "react";
import { ActivityIndicator, StyleSheet, Text, View } from "react-native";
import type { RemoteCommand } from "@/entities/command/model/types";
import { AegisButton } from "@/shared/ui/AegisButton";
import { colors } from "@/shared/ui/theme";
import { elapsedText, progressLabel } from "../model/progress";

export function CommandProgressCard({ command, onCancel }: { command: RemoteCommand; onCancel(): void }) {
  const started = Date.parse(command.progress?.startedAt ?? new Date().toISOString());
  const [elapsed, setElapsed] = useState(0);
  useEffect(() => { const timer = setInterval(() => setElapsed(Math.floor((Date.now() - started) / 1_000)), 1_000);
    return () => clearInterval(timer); }, [started]);
  const progress = command.progress, phase = progress?.phase ?? "running";
  return <View style={styles.card}><View style={styles.row}><ActivityIndicator color={colors.accent} />
    <View style={styles.copy}><Text style={styles.title}>Aegis 작업 중</Text>
      <Text style={styles.message}>{progress?.message || progressLabel(phase)}</Text></View></View>
    <Text style={styles.elapsed}>{elapsedText(elapsed)}</Text>
    {progress?.currentStep && progress.totalSteps ? <Text style={styles.step}>현재 작업 {progress.currentStep} / {progress.totalSteps}</Text> : null}
    {elapsed >= 20 ? <Text style={styles.slow}>작업이 평소보다 오래 걸리고 있지만 계속 진행 중입니다.</Text> : null}
    {progress?.cancellable ? <AegisButton title="작업 취소" danger onPress={onCancel} /> : null}
  </View>;
}
const styles = StyleSheet.create({ card: { backgroundColor: colors.elevated, borderColor: colors.border, borderWidth: 1,
  borderRadius: 16, padding: 16, gap: 10 }, row: { flexDirection: "row", gap: 12, alignItems: "center" }, copy: { flex: 1 },
  title: { color: colors.text, fontWeight: "700" }, message: { color: colors.text, marginTop: 3, lineHeight: 20 },
  elapsed: { color: colors.muted }, step: { color: colors.accent }, slow: { color: colors.warning, lineHeight: 19 } });
