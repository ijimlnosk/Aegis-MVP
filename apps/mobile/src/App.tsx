import { StatusBar, StyleSheet } from "react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { QueryProvider } from "@/app/providers/QueryProvider";
import { RootNavigator } from "@/app/navigation/RootNavigator";
import { colors } from "@/shared/ui/theme";

export default function App() {
  return <SafeAreaProvider style={styles.root}>
    <StatusBar barStyle="light-content" backgroundColor={colors.background} />
    <QueryProvider><RootNavigator /></QueryProvider>
  </SafeAreaProvider>;
}
const styles = StyleSheet.create({ root: { flex: 1, backgroundColor: colors.background } });
