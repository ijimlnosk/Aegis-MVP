import { useState } from "react";
import { ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from "react-native";
import { slashSuggestions } from "@/entities/command/model/slashCommands";
import { colors } from "@/shared/ui/theme";
import { SlashCommandPalette } from "./SlashCommandPalette";

const quick = ["PTFriends 상태 보여줘", "sol-server 상태 보여줘", "현재 화면 상태 알려줘", "PTFriends 어디까지 했지?"];
export function ChatComposer({ disabled, onSend }: { disabled: boolean; onSend(value: string): void }) {
  const [text, setText] = useState(""); const submit = (value = text) => {
    const trimmed = value.trim(); if (!trimmed || disabled) return; setText(""); onSend(trimmed); };
  const suggestions = disabled ? [] : slashSuggestions(text);
  return <View style={styles.wrap}>{suggestions.length > 0
    ? <SlashCommandPalette commands={suggestions} onChoose={submit} />
    : <ScrollView horizontal showsHorizontalScrollIndicator={false}
    contentContainerStyle={styles.chips}>{quick.map(value => <TouchableOpacity key={value} style={styles.chip}
      onPress={() => submit(value)} disabled={disabled}><Text style={styles.chipText}>{value.replace(" 보여줘", "")}</Text></TouchableOpacity>)}</ScrollView>}
    {/* TextInput stays editable=true always: toggling it off fires Android's HIDE_SOFT_INPUT_FROM_VIEW mid-command. */}
    <View style={styles.row}><TextInput style={styles.input} multiline value={text} onChangeText={setText}
      placeholder="Aegis에게 요청... (/ 로 명령어)" placeholderTextColor={colors.muted} />
      <TouchableOpacity accessibilityRole="button" accessibilityLabel="요청 전송" style={[styles.send, disabled && styles.disabled]}
        disabled={disabled} onPress={() => submit()}><Text style={styles.sendText}>전송</Text></TouchableOpacity></View>
  </View>;
}
const styles = StyleSheet.create({ wrap: { borderTopColor: colors.border, borderTopWidth: 1, paddingTop: 8, backgroundColor: colors.background },
  chips: { gap: 8, paddingBottom: 8 }, chip: { borderColor: colors.border, borderWidth: 1, borderRadius: 18, paddingVertical: 8, paddingHorizontal: 12 },
  chipText: { color: colors.muted, fontSize: 12 }, row: { flexDirection: "row", alignItems: "flex-end", gap: 8 },
  input: { flex: 1, minHeight: 46, maxHeight: 120, color: colors.text, backgroundColor: colors.surface, borderColor: colors.border,
    borderWidth: 1, borderRadius: 14, paddingHorizontal: 13, paddingVertical: 11 }, send: { minHeight: 46, paddingHorizontal: 14,
    backgroundColor: colors.accent, borderRadius: 12, justifyContent: "center" }, sendText: { color: "white", fontWeight: "800" }, disabled: { opacity: 0.45 } });
