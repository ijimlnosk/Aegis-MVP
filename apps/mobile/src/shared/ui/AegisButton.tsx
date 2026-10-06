import { Pressable, StyleSheet, Text } from "react-native";
import { colors } from "./theme";

export function AegisButton({ title, onPress, danger = false, secondary = false, disabled = false, accessibilityLabel }: {
  title: string; onPress(): void; danger?: boolean; secondary?: boolean; disabled?: boolean; accessibilityLabel?: string;
}) {
  return <Pressable accessibilityRole="button" accessibilityLabel={accessibilityLabel} accessibilityState={{ disabled }}
    disabled={disabled} onPress={onPress}
    style={({ pressed }) => [styles.button, danger && styles.danger, secondary && styles.secondary,
      pressed && styles.pressed, disabled && styles.disabled]}>
    <Text style={[styles.text, secondary && styles.secondaryText]}>{title}</Text>
  </Pressable>;
}
const styles = StyleSheet.create({ button: { minHeight: 46, paddingHorizontal: 18, borderRadius: 12,
  backgroundColor: colors.accent, alignItems: "center", justifyContent: "center" },
  danger: { backgroundColor: colors.error }, secondary: { backgroundColor: "transparent", borderWidth: 1, borderColor: colors.border },
  pressed: { opacity: 0.75 }, disabled: { opacity: 0.45 }, text: { color: "white", fontWeight: "700" },
  secondaryText: { color: colors.text } });
