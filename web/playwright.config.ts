import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.E2E_WEB_URL || "http://localhost:3000";
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 90000,
  expect: { timeout: 15000 },
  reporter: [["list"]],
  use: { baseURL, trace: "retain-on-failure", screenshot: "only-on-failure" },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: process.env.E2E_EXTERNAL_SERVER ? undefined : {
    command: "npm run start",
    url: `${baseURL}/login`,
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
    env: { API_URL: process.env.E2E_API_URL || "http://127.0.0.1:3001", WEB_ORIGIN: baseURL, COOKIE_SECURE: "false", NEXT_TELEMETRY_DISABLED: "1" }
  }
});
