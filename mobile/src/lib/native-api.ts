import * as SecureStore from "expo-secure-store";
import Constants from "expo-constants";
import * as Crypto from "expo-crypto";
import { ApiError, createApiClient, type RequestOptions, type Tokens } from "./api-client";
import { createFinancialIntents, retainUncertainFailure, type FinancialIntent } from "./financial-intents";

const SESSION_KEY = "aurora.session.v1";
const BIOMETRIC_KEY = "aurora.biometric.enabled";
const INTENT_KEY = "aurora.operation.pending.v1";
const secureOptions: SecureStore.SecureStoreOptions = { keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY };
let expiredHandler: (() => void) | undefined;

export const tokenStore = {
  async read(): Promise<Tokens | null> {
    const raw = await SecureStore.getItemAsync(SESSION_KEY);
    if (!raw) return null;
    try {
      const value = JSON.parse(raw);
      if (typeof value.access_token === "string" && /^[0-9a-f]{64}$/.test(value.access_token)
        && typeof value.refresh_token === "string" && /^[0-9a-f]{64}$/.test(value.refresh_token)
        && value.token_type === "Bearer" && Number.isSafeInteger(value.expires_in) && value.expires_in > 0 && value.expires_in <= 900) return value;
    } catch { /* Credencial corrompida deve exigir novo login. */ }
    await SecureStore.deleteItemAsync(SESSION_KEY);
    return null;
  },
  async write(tokens: Tokens) { await SecureStore.setItemAsync(SESSION_KEY, JSON.stringify(tokens), secureOptions); },
  async clear() { await SecureStore.deleteItemAsync(SESSION_KEY); }
};

const baseUrl = (process.env.EXPO_PUBLIC_API_URL || "http://localhost:3001").replace(/\/+$/, "");
function assertConfiguration() {
  let parsed: URL;
  try { parsed = new URL(baseUrl); } catch { throw new ApiError("Configure EXPO_PUBLIC_API_URL com o endereço da API.", "invalid_configuration", 0); }
  if (!["https:", "http:"].includes(parsed.protocol) || parsed.username || parsed.password || parsed.pathname !== "/" || parsed.search || parsed.hash) {
    throw new ApiError("A URL da API deve conter apenas protocolo, host e porta.", "invalid_configuration", 0);
  }
  if (parsed.protocol !== "https:" && !__DEV__ && Constants.expoConfig?.extra?.appVariant !== "development") {
    throw new ApiError("Este build exige uma API HTTPS. Configure EXPO_PUBLIC_API_URL.", "https_required", 0);
  }
}

const client = createApiClient({ baseUrl, store: tokenStore, onExpired: () => expiredHandler?.() });
export const api = {
  request<T = any>(path: string, config?: RequestOptions): Promise<T> { assertConfiguration(); return client.request<T>(path, config); },
  login(body: { email: string; password: string; otp_code?: string; recovery_code?: string }) { assertConfiguration(); return client.login(body); },
  logout() { return client.logout(); }
};

const financialIntents = createFinancialIntents({
  store: {
    async read(): Promise<FinancialIntent[]> {
      const raw = await SecureStore.getItemAsync(INTENT_KEY);
      if (!raw) return [];
      try {
        const data = JSON.parse(raw);
        const items = Array.isArray(data) ? data : [data];
        if (items.length <= 8 && items.every(item => item && typeof item.scope === "string" && item.scope.length <= 40 && typeof item.key === "string" && item.key.length <= 40 && /^[0-9a-f]{64}$/.test(item.fingerprint))) return items;
      } catch { /* Um registro inválido não é usado para autorizar operações. */ }
      await SecureStore.deleteItemAsync(INTENT_KEY);
      return [];
    },
    async write(intent) { await SecureStore.setItemAsync(INTENT_KEY, JSON.stringify(intent), secureOptions); },
    async clear() { await SecureStore.deleteItemAsync(INTENT_KEY); }
  },
  fingerprint: value => Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, value),
  newKey: () => Crypto.randomUUID(),
  retainFailure: retainUncertainFailure
});

export function financialRequest<T = any>(userId: string, path: string, body: unknown): Promise<T> {
  return financialIntents.perform(userId, { path, body }, idempotencyKey => api.request<T>(path, { method: "POST", body, idempotencyKey }));
}

export function setSessionExpiredHandler(handler?: () => void) { expiredHandler = handler; }
export const biometricPreference = {
  async read() { return (await SecureStore.getItemAsync(BIOMETRIC_KEY)) === "1"; },
  async set(enabled: boolean) { await SecureStore.setItemAsync(BIOMETRIC_KEY, enabled ? "1" : "0", secureOptions); }
};

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "Não foi possível concluir. Tente novamente.";
}
