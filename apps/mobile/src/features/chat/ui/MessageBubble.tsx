import { useState } from "react";
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { collapseMessage } from "@/entities/message/model/collapse";
import { splitSegments } from "@/entities/message/model/segments";
import type { RemoteChatMessage } from "@/entities/message/model/types";
import { colors } from "@/shared/ui/theme";

export function MessageBubble({ message }: { message: RemoteChatMessage }) {
  const mine = message.role === "user", error = message.role === "error";
  const [expanded, setExpanded] = useState(false);
  const { preview, truncated } = collapseMessage(message.content);
  const segments = splitSegments(expanded || !truncated ? message.content : preview);
  const hasCode = segments.some(segment => segment.kind === "code");
  return <View style={[styles.bubble, mine ? styles.mine : styles.theirs, error && styles.error, hasCode && styles.wide]}>
    {error ? <Text style={styles.errorLabel}>실패</Text> : null}
    {segments.map((segment, index) => segment.kind === "code"
      // Code keeps its line breaks and alignment; long lines scroll sideways instead of wrapping.
      ? <ScrollView key={index} horizontal style={styles.codeBox} showsHorizontalScrollIndicator={false}>
          <Text selectable style={styles.code}>{segment.text}</Text></ScrollView>
      : <Text key={index} selectable style={styles.text}>{segment.text}</Text>)}
    {truncated ? <Pressable accessibilityRole="button" hitSlop={8} onPress={() => setExpanded(value => !value)}>
      <Text style={styles.more}>{expanded ? "접기" : "더 보기"}</Text></Pressable> : null}
  </View>;
}
const mono = Platform.select({ ios: "Menlo", default: "monospace" });
const styles = StyleSheet.create({ bubble: { maxWidth: "88%", borderRadius: 16, padding: 13, marginVertical: 5, gap: 8 },
  wide: { maxWidth: "96%" },
  mine: { alignSelf: "flex-end", backgroundColor: "#34436E" }, theirs: { alignSelf: "flex-start", backgroundColor: colors.surface,
    borderWidth: 1, borderColor: colors.border }, error: { borderColor: colors.error },
  errorLabel: { color: colors.error, fontSize: 12, fontWeight: "700" }, text: { color: colors.text, lineHeight: 20 },
  codeBox: { backgroundColor: colors.background, borderRadius: 8, padding: 8 },
  code: { color: colors.text, fontFamily: mono, fontSize: 12, lineHeight: 17 },
  more: { color: colors.accent, fontWeight: "700" } });
