import { StyleSheet, Text, View } from "react-native";
import type { RemoteChatMessage } from "@/entities/message/model/types";
import { colors } from "@/shared/ui/theme";

export function MessageBubble({ message }: { message: RemoteChatMessage }) {
  const mine = message.role === "user", error = message.role === "error";
  return <View style={[styles.bubble, mine ? styles.mine : styles.theirs, error && styles.error]}>
    {error ? <Text style={styles.errorLabel}>실패</Text> : null}
    <Text selectable style={styles.text}>{message.content}</Text>
  </View>;
}
const styles = StyleSheet.create({ bubble: { maxWidth: "88%", borderRadius: 16, padding: 13, marginVertical: 5 },
  mine: { alignSelf: "flex-end", backgroundColor: "#34436E" }, theirs: { alignSelf: "flex-start", backgroundColor: colors.surface,
    borderWidth: 1, borderColor: colors.border }, error: { borderColor: colors.error },
  errorLabel: { color: colors.error, fontSize: 12, fontWeight: "700", marginBottom: 4 }, text: { color: colors.text, lineHeight: 20 } });
