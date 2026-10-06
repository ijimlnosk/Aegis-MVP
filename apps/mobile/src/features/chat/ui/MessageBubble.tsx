import { useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { collapseMessage } from "@/entities/message/model/collapse";
import type { RemoteChatMessage } from "@/entities/message/model/types";
import { colors } from "@/shared/ui/theme";

export function MessageBubble({ message }: { message: RemoteChatMessage }) {
  const mine = message.role === "user", error = message.role === "error";
  const [expanded, setExpanded] = useState(false);
  const { preview, truncated } = collapseMessage(message.content);
  return <View style={[styles.bubble, mine ? styles.mine : styles.theirs, error && styles.error]}>
    {error ? <Text style={styles.errorLabel}>실패</Text> : null}
    <Text selectable style={styles.text}>{expanded || !truncated ? message.content : preview}</Text>
    {truncated ? <Pressable accessibilityRole="button" hitSlop={8} onPress={() => setExpanded(value => !value)}>
      <Text style={styles.more}>{expanded ? "접기" : "더 보기"}</Text></Pressable> : null}
  </View>;
}
const styles = StyleSheet.create({ bubble: { maxWidth: "88%", borderRadius: 16, padding: 13, marginVertical: 5 },
  mine: { alignSelf: "flex-end", backgroundColor: "#34436E" }, theirs: { alignSelf: "flex-start", backgroundColor: colors.surface,
    borderWidth: 1, borderColor: colors.border }, error: { borderColor: colors.error },
  errorLabel: { color: colors.error, fontSize: 12, fontWeight: "700", marginBottom: 4 }, text: { color: colors.text, lineHeight: 20 },
  more: { color: colors.accent, fontWeight: "700", marginTop: 8 } });
