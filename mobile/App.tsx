import React, { Component, useState } from "react";
import { ActivityIndicator, Text, View, useColorScheme } from "react-native";
import { NavigationContainer, DarkTheme, DefaultTheme } from "@react-navigation/native";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import { StatusBar } from "expo-status-bar";
import { AuthProvider, useAuth } from "./src/contexts/AuthContext";
import { AuthenticationScreen } from "./src/screens/AuthScreens";
import { AccountScreen, DashboardScreen, ScheduledScreen, StatementScreen, TransfersScreen } from "./src/screens/BankingScreens";
import { InvestmentsScreen, LoansScreen } from "./src/screens/ProductScreens";
import { GoalsScreen, NotificationsScreen, ProfileScreen, SecurityScreen } from "./src/screens/ProfileScreens";
import { Button, Card, Notice, Page, usePalette } from "./src/components/ui";

const Tabs = createBottomTabNavigator();
const Stack = createNativeStackNavigator();
function MainTabs() {
  const c = usePalette();
  const icons: Record<string, keyof typeof Ionicons.glyphMap> = { Início: "grid-outline", Movimentar: "swap-horizontal-outline", Planejar: "trending-up-outline", Investir: "pie-chart-outline", Perfil: "person-outline" };
  return <Tabs.Navigator screenOptions={({ route }) => ({ headerShown: false, tabBarActiveTintColor: c.accent, tabBarInactiveTintColor: c.muted, tabBarStyle: { backgroundColor: c.card, borderTopColor: c.border, paddingTop: 7, height: 82, paddingBottom: 22 }, tabBarLabelStyle: { fontSize: 10, fontWeight: "600" }, tabBarIcon: ({ color, size }) => <Ionicons name={icons[route.name] ?? "ellipse-outline"} color={color} size={size} /> })}><Tabs.Screen name="Início" component={DashboardScreen} /><Tabs.Screen name="Movimentar" component={TransfersScreen} /><Tabs.Screen name="Planejar" component={LoansScreen} /><Tabs.Screen name="Investir" component={InvestmentsScreen} /><Tabs.Screen name="Perfil" component={ProfileScreen} /></Tabs.Navigator>;
}
function Root() {
  const auth = useAuth(); const dark = useColorScheme() === "dark"; const c = usePalette(); const [unlockError, setUnlockError] = useState("");
  if (auth.booting) return <View style={{ flex: 1, justifyContent: "center", backgroundColor: c.bg }}><ActivityIndicator accessibilityLabel="Carregando sessão" color={c.accent} size="large" /></View>;
  if (auth.locked) return <Page title="Seu Aurora está protegido" subtitle="Desbloqueie para continuar."><Card>{unlockError ? <Notice error>{unlockError}</Notice> : null}<Button title="Desbloquear com biometria" onPress={() => { void auth.unlock().then(ok => { if (!ok) setUnlockError("Biometria não confirmada. Tente novamente ou entre com sua senha."); }).catch(() => setUnlockError("Não foi possível confirmar a biometria.")); }} /><Button title="Entrar novamente com senha" secondary onPress={() => void auth.logout().catch(() => {})} /></Card></Page>;
  if (!auth.user) return <AuthenticationScreen />;
  return <NavigationContainer theme={dark ? DarkTheme : DefaultTheme}><Stack.Navigator screenOptions={{ headerStyle: { backgroundColor: c.card }, headerTintColor: c.text, headerBackTitle: "Voltar", headerTitleStyle: { fontSize: 16 } }}><Stack.Screen name="Main" component={MainTabs} options={{ headerShown: false }} /><Stack.Screen name="Account" component={AccountScreen} options={{ title: "Minha conta" }} /><Stack.Screen name="Statement" component={StatementScreen} options={{ title: "Extrato" }} /><Stack.Screen name="Scheduled" component={ScheduledScreen} options={{ title: "Agendamentos" }} /><Stack.Screen name="Security" component={SecurityScreen} options={{ title: "Segurança" }} /><Stack.Screen name="Notifications" component={NotificationsScreen} options={{ title: "Notificações" }} /><Stack.Screen name="Goals" component={GoalsScreen} options={{ title: "Objetivos" }} /></Stack.Navigator></NavigationContainer>;
}
class ErrorBoundary extends Component<{ children: React.ReactNode }, { failed: boolean; version: number }> {
  state = { failed: false, version: 0 };
  static getDerivedStateFromError() { return { failed: true }; }
  render() {
    if (this.state.failed) return <View style={{ flex: 1, backgroundColor: "#102E38", padding: 28, justifyContent: "center", gap: 20 }}><Text style={{ color: "#FFF", fontSize: 25, fontWeight: "700" }}>Vamos recomeçar com segurança.</Text><Text style={{ color: "#BAD4D9", lineHeight: 24 }}>O aplicativo encontrou uma falha. Nenhuma operação deve ser repetida sem conferir o extrato.</Text><Button title="Reabrir aplicativo" onPress={() => this.setState(state => ({ failed: false, version: state.version + 1 }))} /></View>;
    return <React.Fragment key={this.state.version}>{this.props.children}</React.Fragment>;
  }
}
export default function App() { return <SafeAreaProvider><ErrorBoundary><AuthProvider><StatusBar style="auto" /><Root /></AuthProvider></ErrorBoundary></SafeAreaProvider>; }
