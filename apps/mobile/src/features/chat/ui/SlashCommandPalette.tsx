import { StyleSheet, Text, TouchableOpacity, View } from "react-native";
import type { SlashCommand } from "@/entities/command/model/slashCommands";
import { colors } from "@/shared/ui/theme";

export function SlashCommandPalette({ commands, onChoose }: { commands: SlashCommand[]; onChoose(usage: string): void }) {
  return <View style={styles.palette} accessibilityRole="menu">{commands.map(command =>
    <TouchableOpacity key={command.usage} style={styles.row} accessibilityRole="menuitem"
      accessibilityLabel={`${command.usage}, ${command.summary}`} onPress={() => onChoose(command.usage)}>
      <Text style={styles.usage}>{command.usage}</Text><Text style={styles.summary}>{command.summary}</Text>
    </TouchableOpacity>)}</View>;
}
const styles = StyleSheet.create({
  palette: { backgroundColor: colors.elevated, borderColor: colors.border, borderWidth: 1, borderRadius: 12, marginBottom: 8, overflow: "hidden" },
  row: { minHeight: 44, flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 12, paddingVertical: 10 },
  usage: { color: colors.accent, fontWeight: "800", fontFamily: "monospace" },
  summary: { color: colors.muted, fontSize: 13, flexShrink: 1 },
});
