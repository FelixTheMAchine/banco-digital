import { expect, test } from "@playwright/test";
import { createHmac } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";

test("BFF rejects cross-origin mutations and does not expose credentials to anonymous clients", async ({ request }) => {
  const blocked = await request.post("/api/account/deposits", { headers: { Origin: "https://evil.example.test", "X-Aurora-CSRF": "1" }, data: { amount_cents: 100 } });
  expect(blocked.status()).toBe(403);
  const anonymous = await request.get("/api/me");
  expect(anonymous.status()).toBe(401);
  expect(await anonymous.text()).not.toMatch(/access_token|refresh_token|password_digest/);
});

test("authorized administrator reviews lists and downloads an audited XLSX with MFA", async ({ page }) => {
  const file = process.env.E2E_ADMIN_FIXTURE;
  test.skip(!file || !existsSync(file), "Configure E2E_ADMIN_FIXTURE with an isolated, private demo MFA fixture.");
  const fixture = JSON.parse(readFileSync(file!, "utf8")) as { email: string; password: string; secret: string };
  const crashes: string[] = [];
  page.on("pageerror", error => crashes.push(error.message));
  await page.goto("/login");
  await page.getByLabel("E-mail", { exact: true }).fill(fixture.email);
  await page.getByLabel("Senha", { exact: true }).fill(fixture.password);
  await page.getByRole("button", { name: "Entrar na conta" }).click();
  await expect(page.getByLabel("Código do autenticador", { exact: true })).toBeVisible();
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const character of fixture.secret.replace(/=+$/, "").toUpperCase()) {
    const value = alphabet.indexOf(character);
    if (value < 0) throw new Error("Invalid isolated MFA fixture.");
    bits += value.toString(2).padStart(5, "0");
  }
  const key = Buffer.from(Array.from({ length: Math.floor(bits.length / 8) }, (_, index) => Number.parseInt(bits.slice(index * 8, index * 8 + 8), 2)));
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000)));
  const digest = createHmac("sha1", key).update(counter).digest();
  const offset = digest[digest.length - 1] & 15;
  const code = String((digest.readUInt32BE(offset) & 0x7fffffff) % 1000000).padStart(6, "0");
  await page.getByLabel("Código do autenticador", { exact: true }).fill(code);
  await page.getByRole("button", { name: "Entrar na conta" }).click();
  await expect(page).toHaveURL(/\/dashboard$/);
  await page.getByRole("link", { name: "Administração", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Administração Aurora" })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Áreas administrativas" })).toBeVisible();
  for (const tab of ["Clientes", "Contas", "Movimentações", "Alertas", "Crédito", "Auditoria", "Regras"]) {
    await page.getByRole("navigation", { name: "Áreas administrativas" }).getByRole("button", { name: tab, exact: true }).click();
    await expect(page.locator(".loading")).toHaveCount(0);
    await expect(page.locator(".alert.error")).toHaveCount(0);
  }
  await page.getByRole("button", { name: "Relatórios", exact: true }).click();
  await page.getByRole("button", { name: "Revisar exportação" }).click();
  const downloadEvent = page.waitForEvent("download");
  await page.getByRole("dialog").getByRole("button", { name: "Confirmar exportação" }).click();
  const download = await downloadEvent;
  expect(download.suggestedFilename()).toBe("aurora-relatorio.xlsx");
  expect(await download.failure()).toBeNull();
  expect(crashes).toEqual([]);
});

test("customer completes banking and educational flows without browser crashes", async ({ page, context, request }) => {
  test.skip(!process.env.E2E_EMAIL || !process.env.E2E_PASSWORD, "Configure an isolated seeded customer using E2E_EMAIL and E2E_PASSWORD.");
  const crashes: string[] = [];
  page.on("pageerror", error => crashes.push(error.message));
  await page.goto("/login");
  await page.getByLabel("E-mail", { exact: true }).fill(process.env.E2E_EMAIL!);
  await page.getByLabel("Senha", { exact: true }).fill(process.env.E2E_PASSWORD!);
  await page.getByRole("button", { name: "Entrar na conta" }).click();
  await expect(page).toHaveURL(/\/dashboard$/);
  await expect(page.getByRole("heading", { name: /Olá,/ })).toBeVisible();
  const cookies = await context.cookies();
  expect(cookies.filter(cookie => cookie.name.startsWith("aurora_")).every(cookie => cookie.httpOnly && cookie.sameSite === "Strict")).toBeTruthy();
  expect(await page.evaluate(() => Object.keys(localStorage).filter(key => /token|session|refresh/i.test(key)))).toEqual([]);
  const rotations = await page.evaluate(async () => Promise.all([1, 2].map(async () => {
    const result = await fetch("/api/auth/refresh", { method: "POST", headers: { "Content-Type": "application/json", "X-Aurora-CSRF": "1" }, body: "{}" });
    return { status: result.status, body: await result.json() };
  })));
  expect(rotations).toEqual([{ status: 200, body: { authenticated: true } }, { status: 200, body: { authenticated: true } }]);
  const open = page.getByRole("button", { name: /Abrir conta simulada/ });
  if (await open.isVisible()) await open.click();
  await page.getByRole("link", { name: "Minha conta", exact: true }).click();
  await page.getByRole("button", { name: /Depósito simulado/ }).click();
  const dialog = page.getByRole("dialog");
  await dialog.getByLabel("Valor (R$)", { exact: true }).fill("5,00");
  await dialog.getByRole("button", { name: "Revisar operação" }).click();
  await expect(dialog.getByText("R$ 5,00", { exact: true })).toBeVisible();
  await dialog.getByRole("button", { name: "Confirmar operação" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Operação simulada concluída" })).toBeVisible();
  await page.getByRole("link", { name: "Extrato", exact: true }).first().click();
  await expect(page.getByRole("heading", { name: "Seu extrato" })).toBeVisible();
  await page.getByRole("button", { name: /^Comprovante/ }).first().click();
  await expect(page.getByRole("dialog").getByText("Dinheiro fictício", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Fechar", exact: true }).click();
  if (process.env.E2E_RECIPIENT_EMAIL) {
    const backend = process.env.E2E_API_URL || "http://127.0.0.1:3001";
    const login = await request.post(`${backend}/api/v1/auth/login`, { data: { email: process.env.E2E_RECIPIENT_EMAIL, password: process.env.E2E_RECIPIENT_PASSWORD || process.env.E2E_PASSWORD } });
    expect(login.status()).toBe(200);
    const tokens = await login.json();
    const recipient = await request.get(`${backend}/api/v1/account`, { headers: { Authorization: `Bearer ${tokens.access_token}` } });
    expect(recipient.status()).toBe(200);
    const target = (await recipient.json()).account.number as string;
    await page.goto("/transferencias");
    await page.getByLabel("Número da conta de destino").fill(target);
    await page.getByLabel("Valor (R$)", { exact: true }).fill("1,00");
    await page.getByRole("button", { name: "Revisar transferência" }).click();
    await expect(page.getByRole("dialog").getByText(`Para a conta ${target}`)).toBeVisible();
    await page.getByRole("dialog").getByRole("button", { name: "Confirmar", exact: true }).click();
    await expect(page.getByRole("dialog", { name: "Transferência concluída" })).toBeVisible();
    await page.getByRole("button", { name: "Fechar", exact: true }).click();
    await request.delete(`${backend}/api/v1/auth/logout`, { headers: { Authorization: `Bearer ${tokens.access_token}` } });
  }
  await page.goto("/emprestimos/simulador");
  await page.getByLabel("Valor solicitado (R$)", { exact: false }).fill("1.000,00");
  await page.getByLabel("Prazo em meses", { exact: true }).fill("12");
  await page.getByRole("button", { name: "Simular parcelas" }).click();
  await expect(page.getByText("Parcela nominal estimada", { exact: true })).toBeVisible();
  await expect(page.getByText("CET anual estimado", { exact: true })).toBeVisible();
  await page.goto("/investimentos/simulador");
  await page.getByLabel("Valor inicial (R$)", { exact: true }).fill("1.000,00");
  await page.getByLabel("Aporte mensal (R$)", { exact: true }).fill("100,00");
  await page.getByLabel("Prazo em meses", { exact: true }).fill("12");
  await page.getByRole("button", { name: "Simular evolução" }).click();
  await expect(page.getByRole("heading", { name: "Seu cenário em 12 meses" })).toBeVisible();
  for (const [path, heading] of [["/perfil", "Meu perfil"], ["/seguranca", "Sua segurança"], ["/notificacoes", "Notificações"]]) {
    await page.goto(path);
    await expect(page.getByRole("heading", { name: heading, exact: true })).toBeVisible();
    await expect(page.locator(".loading")).toHaveCount(0);
    await expect(page.locator(".alert.error")).toHaveCount(0);
  }
  await page.goto("/perfil");
  await page.getByRole("button", { name: "Revisar desativação" }).click();
  const confirmation = page.getByLabel("Digite DESATIVAR para confirmar");
  await confirmation.pressSequentially("DESATIVAR");
  await expect(confirmation).toBeFocused();
  await expect(page.getByRole("dialog").getByRole("button", { name: "Confirmar desativação" })).toBeEnabled();
  await page.getByRole("dialog").getByRole("button", { name: "Voltar", exact: true }).click();
  await page.goto("/admin");
  await expect(page.getByText(/Acesso restrito à administração|Acesso administrativo restrito|Somente administradores/).first()).toBeVisible();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: /Olá,/ })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Navegação no celular" })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  expect(crashes).toEqual([]);
});
