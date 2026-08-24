import { Pressable, StyleSheet, Text } from "react-native";
import { colors } from "./theme";

export function AegisButton({ title, onPress, danger = false, disabled = false }: {
  title: string; onPress(): void; danger?: boolean; disabled?: boolean;
}) {
  return <Pressable accessibilityRole="button" disabled={disabled} onPress={onPress}
    style={[styles.button, danger && styles.danger, disabled && styles.disabled]}>
    <Text style={styles.text}>{title}</Text>
  </Pressable>;
}
const styles = StyleSheet.create({ button: { minHeight: 46, paddingHorizontal: 18, borderRadius: 12,
  backgroundColor: colors.accent, alignItems: "center", justifyContent: "center" },
  danger: { backgroundColor: colors.error }, disabled: { opacity: 0.45 }, text: { color: "white", fontWeight: "700" } });
