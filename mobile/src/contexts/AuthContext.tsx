import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { AppState } from "react-native";
import * as LocalAuthentication from "expo-local-authentication";
import { api, biometricPreference, setSessionExpiredHandler, tokenStore } from "../lib/native-api";

export interface Customer {
  id: string; full_name: string; email: string; cpf: string; phone: string; birth_date: string;
  profession: string; monthly_salary_cents: number; other_income_cents: number;
  monthly_expenses_cents: number; existing_debts_cents: number; status: string;
  address: { street: string; number: string; city: string; state: string; postal_code: string };
  role: "customer" | "admin";
  mfa_enabled: boolean;
}
interface AuthState {
  user: Customer | null; booting: boolean; locked: boolean; biometricEnabled: boolean;
  login: (data: { email: string; password: string; otp_code?: string; recovery_code?: string }) => Promise<void>;
  logout: () => Promise<void>; reloadUser: () => Promise<void>; unlock: () => Promise<boolean>;
  setBiometricEnabled: (enabled: boolean) => Promise<void>;
}
const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<Customer | null>(null);
  const [booting, setBooting] = useState(true);
  const [locked, setLocked] = useState(false);
  const [biometricEnabled, setBiometric] = useState(false);
  const biometricRef = useRef(false);
  const authenticatedRef = useRef(false);

  const reloadUser = useCallback(async () => {
    const data = await api.request<{ user: Customer }>("/me");
    setUser(data.user);
    authenticatedRef.current = true;
  }, []);

  useEffect(() => {
    let alive = true;
    setSessionExpiredHandler(() => { if (alive) { setUser(null); setLocked(false); authenticatedRef.current = false; } });
    (async () => {
      try {
        const enabled = await biometricPreference.read();
        if (!alive) return;
        biometricRef.current = enabled;
        setBiometric(enabled);
        const tokens = await tokenStore.read();
        if (tokens) {
          if (enabled) { setLocked(true); authenticatedRef.current = true; }
          else await reloadUser();
        }
      } catch { /* Uma sessão indisponível nunca libera dados sem autenticação. */ }
      finally { if (alive) setBooting(false); }
    })();
    const subscription = AppState.addEventListener("change", state => {
      if (state !== "active" && biometricRef.current && authenticatedRef.current) setLocked(true);
    });
    return () => { alive = false; setSessionExpiredHandler(undefined); subscription.remove(); };
  }, [reloadUser]);

  const login: AuthState["login"] = async data => {
    await api.login(data);
    try { await reloadUser(); setLocked(false); }
    catch (error) { await tokenStore.clear(); setUser(null); throw error; }
  };
  const logout = async () => { try { await api.logout(); } finally { setUser(null); setLocked(false); authenticatedRef.current = false; } };
  const unlock = async () => {
    const available = await LocalAuthentication.hasHardwareAsync() && await LocalAuthentication.isEnrolledAsync();
    if (!available) return false;
    const result = await LocalAuthentication.authenticateAsync({ promptMessage: "Desbloquear Aurora", cancelLabel: "Cancelar", fallbackLabel: "Usar código do aparelho", disableDeviceFallback: false, biometricsSecurityLevel: "strong" });
    if (result.success) { await reloadUser(); setLocked(false); }
    return result.success;
  };
  const setBiometricEnabled = async (enabled: boolean) => {
    if (enabled) {
      const available = await LocalAuthentication.hasHardwareAsync() && await LocalAuthentication.isEnrolledAsync();
      if (!available) throw new Error("Cadastre uma biometria compatível no seu aparelho primeiro.");
      const confirmed = await LocalAuthentication.authenticateAsync({ promptMessage: "Ativar desbloqueio biométrico", cancelLabel: "Cancelar", fallbackLabel: "Usar código do aparelho", disableDeviceFallback: false, biometricsSecurityLevel: "strong" });
      if (!confirmed.success) throw new Error("A biometria não foi confirmada.");
    }
    await biometricPreference.set(enabled);
    biometricRef.current = enabled;
    setBiometric(enabled);
  };

  return <AuthContext.Provider value={{ user, booting, locked, biometricEnabled, login, logout, reloadUser, unlock, setBiometricEnabled }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error("AuthProvider ausente.");
  return value;
}
