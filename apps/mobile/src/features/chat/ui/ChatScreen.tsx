import { useRef, useState } from "react";
import { FlatList, KeyboardAvoidingView, Platform, StyleSheet, View, type NativeSyntheticEvent, type NativeScrollEvent } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { ConnectionHeader } from "@/entities/connection/ui/ConnectionHeader";
import { ApprovalCard } from "@/features/approvals/ui/ApprovalCard";
import { CommandProgressCard } from "@/features/commands/ui/CommandProgressCard";
import { useRemoteCommands } from "@/features/commands/model/useRemoteCommands";
import { SettingsSheet } from "@/features/settings/ui/SettingsSheet";
import { colors } from "@/shared/ui/theme";
import { ChatComposer } from "./ChatComposer";
import { MessageBubble } from "./MessageBubble";

const NEAR_BOTTOM_PX = 80;

export function ChatScreen() {
  const remote = useRemoteCommands(); const [settings, setSettings] = useState(false);
  const list = useRef<FlatList>(null); const nearBottom = useRef(true);
  const approval = remote.active?.pendingApproval;

  const onScroll = (event: NativeSyntheticEvent<NativeScrollEvent>) => {
    const { contentOffset, contentSize, layoutMeasurement } = event.nativeEvent;
    nearBottom.current = contentSize.height - contentOffset.y - layoutMeasurement.height < NEAR_BOTTOM_PX;
  };
  // New content (a poll/progress update) only autoscrolls if the user was already
  // near the bottom -- reading older history is never interrupted.
  const onContentSizeChange = () => { if (nearBottom.current) list.current?.scrollToEnd({ animated: true }); };
  const onSend = (value: string) => { nearBottom.current = true; void remote.send(value); list.current?.scrollToEnd({ animated: true }); };

  return <SafeAreaView style={styles.screen}>
    <KeyboardAvoidingView style={styles.screen} behavior={Platform.OS === "ios" ? "padding" : "height"}>
    <ConnectionHeader state={remote.connection} onSettings={() => setSettings(true)} />
    <FlatList ref={list} data={remote.messages} keyExtractor={item => item.id}
      renderItem={({ item }) => <MessageBubble message={item} />} contentContainerStyle={styles.list}
      onScroll={onScroll} scrollEventThrottle={100} onContentSizeChange={onContentSizeChange}
      ListFooterComponent={<View style={styles.footer}>{approval
        ? <ApprovalCard approval={approval} onDecision={value => void remote.decide(value)}
            onCancel={() => void remote.cancel()} />
        : remote.active ? <CommandProgressCard command={remote.active} onCancel={() => void remote.cancel()} /> : null}</View>} />
    <View style={styles.composer}><ChatComposer disabled={Boolean(remote.active) || remote.connection !== "connected"}
      onSend={onSend} /></View>
    <SettingsSheet visible={settings} gatewayURL={remote.gatewayURL} credential={remote.credential} connection={remote.connection}
      lastCommand={remote.lastCommand}
      onClose={() => setSettings(false)} onTest={async () => remote.testConnection()}
      onDisconnect={async () => { await remote.disconnect(); setSettings(false); }} />
  </KeyboardAvoidingView></SafeAreaView>;
}
const styles = StyleSheet.create({ screen: { flex: 1, backgroundColor: colors.background },
  list: { padding: 14, gap: 10, flexGrow: 1, justifyContent: "flex-end" }, footer: { marginTop: 10 },
  composer: { paddingHorizontal: 14, paddingBottom: Platform.OS === "ios" ? 8 : 12 } });
