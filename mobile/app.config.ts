import type { ExpoConfig } from "expo/config";

const production = process.env.APP_VARIANT === "production";
if (production) {
  let address: URL;
  try { address = new URL(process.env.EXPO_PUBLIC_API_URL ?? ""); }
  catch { throw new Error("Defina EXPO_PUBLIC_API_URL HTTPS antes de gerar um build de produção."); }
  if (address.protocol !== "https:" || address.username || address.password || address.pathname !== "/" || address.search || address.hash) {
    throw new Error("O build de produção exige uma origem HTTPS válida para a API.");
  }
}

const config: ExpoConfig = {
  name: "Aurora • banco simulado",
  slug: "aurora-banco-simulado",
  version: "1.0.0",
  orientation: "portrait",
  userInterfaceStyle: "automatic",
  scheme: "aurora-simulado",
  ios: {
    supportsTablet: true,
    bundleIdentifier: "com.aurorasimulado.mobile",
    infoPlist: {
      ITSAppUsesNonExemptEncryption: false,
      LSApplicationQueriesSchemes: ["otpauth"],
      ...(!production ? { NSAppTransportSecurity: { NSAllowsLocalNetworking: true, NSAllowsArbitraryLoads: true } } : {})
    }
  },
  android: {
    package: "com.aurorasimulado.mobile",
    allowBackup: false,
    blockedPermissions: ["android.permission.RECORD_AUDIO", "android.permission.READ_MEDIA_IMAGES", "android.permission.READ_EXTERNAL_STORAGE", "android.permission.WRITE_EXTERNAL_STORAGE"]
  },
  plugins: [
    "expo-status-bar",
    ["expo-secure-store", { configureAndroidBackup: true, faceIDPermission: "Use o Face ID para desbloquear sua sessão local do Aurora." }],
    ["expo-local-authentication", { faceIDPermission: "Use sua biometria para desbloquear o aplicativo Aurora." }],
    ["expo-build-properties", { android: { usesCleartextTraffic: !production } }]
  ],
  extra: { appVariant: production ? "production" : "development" },
  updates: { enabled: false }
};

export default config;
