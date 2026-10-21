import React, { useState } from "react";
import { ActivityIndicator, Alert, KeyboardAvoidingView, Platform, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View, useColorScheme, type TextInputProps } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

const light = { bg: "#F3F6F6", card: "#FFFFFF", text: "#172C35", muted: "#60757B", border: "#DCE6E7", accent: "#087E77", accentSoft: "#E1F4EF", danger: "#B63B49", positive: "#087E77", navy: "#102E38", coral: "#FFB58F" };
const dark = { bg: "#0B1E27", card: "#132E38", text: "#ECF6F6", muted: "#A2B8BD", border: "#294550", accent: "#6BE0C4", accentSoft: "#173F40", danger: "#FF9DAB", positive: "#6BE0C4", navy: "#102E38", coral: "#FFB58F" };
export function usePalette() { return useColorScheme() === "dark" ? dark : light; }

export function Page({ children, title, subtitle, onRefresh, refreshing = false }: { children: React.ReactNode; title: string; subtitle?: string; onRefresh?: () => void; refreshing?: boolean }) {
  const c = usePalette();
  return <SafeAreaView edges={["top", "left", "right"]} style={{ flex: 1, backgroundColor: c.bg }}><KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}><ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.page} refreshControl={onRefresh ? <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={c.accent} /> : undefined}><Text accessibilityRole="header" style={[styles.title, { color: c.text }]}>{title}</Text>{subtitle ? <Text style={[styles.subtitle, { color: c.muted }]}>{subtitle}</Text> : null}{children}<Text style={[styles.footer, { color: c.muted }]}>AURORA · Simulação educativa · Dinheiro fictício</Text></ScrollView></KeyboardAvoidingView></SafeAreaView>;
}
export function Card({ children, accent = false }: { children: React.ReactNode; accent?: boolean }) {
  const c = usePalette();
  return <View style={[styles.card, { backgroundColor: accent ? c.navy : c.card, borderColor: accent ? c.navy : c.border }]}>{children}</View>;
}
export function Label({ children, muted = false, large = false }: { children: React.ReactNode; muted?: boolean; large?: boolean }) { const c = usePalette(); return <Text style={{ color: muted ? c.muted : c.text, fontSize: large ? 21 : 15, lineHeight: large ? 28 : 22, fontWeight: large ? "700" : "400" }}>{children}</Text>; }
export function Heading({ children }: { children: React.ReactNode }) { const c = usePalette(); return <Text accessibilityRole="header" style={[styles.heading, { color: c.text }]}>{children}</Text>; }
export function Field({ label, error, ...props }: TextInputProps & { label: string; error?: string }) {
  const c = usePalette();
  return <View style={styles.field}><Text style={[styles.fieldLabel, { color: c.text }]}>{label}</Text><TextInput accessibilityLabel={label} placeholderTextColor={c.muted} autoCorrect={false} maxLength={512} {...props} style={[styles.input, { borderColor: error ? c.danger : c.border, color: c.text, backgroundColor: c.card }, props.style]} />{error ? <Text accessibilityRole="alert" style={{ color: c.danger }}>{error}</Text> : null}</View>;
}
export function Button({ title, onPress, loading = false, secondary = false, destructive = false, disabled = false }: { title: string; onPress: () => void; loading?: boolean; secondary?: boolean; destructive?: boolean; disabled?: boolean }) {
  const c = usePalette();
  return <Pressable accessibilityRole="button" accessibilityState={{ disabled: disabled || loading, busy: loading }} disabled={disabled || loading} onPress={onPress} style={({ pressed }) => [styles.button, { backgroundColor: destructive ? c.danger : secondary ? c.accentSoft : c.accent, opacity: disabled || loading ? 0.55 : pressed ? 0.8 : 1 }]}>{loading ? <ActivityIndicator color={secondary ? c.accent : c.bg} /> : <Text style={{ fontSize: 15, fontWeight: "700", color: destructive ? "#FFF" : secondary ? c.accent : c.bg }}>{title}</Text>}</Pressable>;
}
export function Notice({ children, error = false }: { children: React.ReactNode; error?: boolean }) { const c = usePalette(); return <View accessibilityRole={error ? "alert" : undefined} style={[styles.notice, { backgroundColor: error ? `${c.danger}18` : c.accentSoft }]}><Text style={{ color: error ? c.danger : c.accent, lineHeight: 21 }}>{children}</Text></View>; }
export function Row({ label, value }: { label: string; value: React.ReactNode }) { const c = usePalette(); return <View style={[styles.row, { borderBottomColor: c.border }]}><Text style={{ color: c.muted, flex: 1, marginRight: 14 }}>{label}</Text><Text selectable style={{ color: c.text, flex: 1, textAlign: "right", fontWeight: "600" }}>{value}</Text></View>; }
export function Choices<T extends string>({ label, value, options, onChange }: { label: string; value: T; options: { value: T; label: string }[]; onChange: (value: T) => void }) { const c = usePalette(); return <View style={styles.field}><Text style={[styles.fieldLabel, { color: c.text }]}>{label}</Text><View style={{ flexDirection: "row", flexWrap: "wrap", gap: 8 }}>{options.map(option => <Pressable key={option.value} accessibilityRole="radio" accessibilityState={{ checked: value === option.value }} onPress={() => onChange(option.value)} style={{ backgroundColor: value === option.value ? c.accent : c.card, borderColor: c.border, borderWidth: 1, borderRadius: 13, paddingHorizontal: 13, paddingVertical: 11 }}><Text style={{ color: value === option.value ? c.bg : c.text }}>{option.label}</Text></Pressable>)}</View></View>; }
export function Busy() { const c = usePalette(); return <ActivityIndicator size="large" style={{ padding: 24 }} color={c.accent} />; }
export function useTask() {
  const [busy, setBusy] = useState(false); const [error, setError] = useState(""); const [message, setMessage] = useState("");
  const run = async (task: () => Promise<void>) => { setBusy(true); setError(""); setMessage(""); try { await task(); } catch (e) { setError(e instanceof Error ? e.message : "Falha inesperada. Tente novamente."); } finally { setBusy(false); } };
  return { busy, error, message, setMessage, run };
}
export function Feedback({ task }: { task: ReturnType<typeof useTask> }) { return <>{task.error ? <Notice error>{task.error}</Notice> : null}{task.message ? <Notice>{task.message}</Notice> : null}</>; }
export function confirm(title: string, message: string, action: () => void, destructive = false) {
  Alert.alert(title, message, [{ text: "Cancelar", style: "cancel" }, { text: "Confirmar", style: destructive ? "destructive" : "default", onPress: action }]);
}
const styles = StyleSheet.create({ page: { padding: 22, paddingBottom: 30, gap: 16 }, title: { fontSize: 30, fontWeight: "800", letterSpacing: -0.8 }, subtitle: { fontSize: 15, lineHeight: 23, marginTop: -8 }, card: { borderWidth: 1, borderRadius: 22, padding: 20, gap: 12 }, heading: { fontSize: 19, fontWeight: "700", marginTop: 8 }, field: { gap: 7, marginBottom: 4 }, fieldLabel: { fontSize: 14, fontWeight: "600" }, input: { minHeight: 50, borderWidth: 1, borderRadius: 13, padding: 13, fontSize: 16 }, button: { minHeight: 50, borderRadius: 14, padding: 14, alignItems: "center", justifyContent: "center" }, notice: { padding: 15, borderRadius: 14 }, row: { paddingVertical: 10, borderBottomWidth: StyleSheet.hairlineWidth, flexDirection: "row", alignItems: "flex-start" }, footer: { textAlign: "center", fontSize: 11, paddingTop: 12 } });
