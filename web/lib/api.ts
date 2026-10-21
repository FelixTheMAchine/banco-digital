export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}
let refreshing: Promise<boolean> | null = null;
async function refreshSession(): Promise<boolean> {
  if (!refreshing) refreshing = fetch("/api/auth/refresh", { method: "POST", headers: { "Content-Type": "application/json", "X-Aurora-CSRF": "1" }, body: "{}", credentials: "same-origin" }).then(r => r.ok).catch(() => false).finally(() => { refreshing = null; });
  return refreshing;
}
export async function api<T = Record<string, unknown>>(path: string, options: { method?: string; body?: unknown; idempotencyKey?: string; retry?: boolean } = {}): Promise<T> {
  const headers: Record<string,string> = { Accept: "application/json" };
  if (options.method && options.method !== "GET") { headers["Content-Type"] = "application/json"; headers["X-Aurora-CSRF"] = "1"; }
  if (options.idempotencyKey) headers["Idempotency-Key"] = options.idempotencyKey;
  const response = await fetch(`/api/${path}`, { method: options.method || "GET", headers, body: options.body === undefined ? undefined : JSON.stringify(options.body), credentials: "same-origin", cache: "no-store" });
  if (response.status === 401 && !path.startsWith("auth/") && options.retry !== false && await refreshSession()) return api<T>(path, { ...options, retry: false });
  const value = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) throw new ApiError(response.status, value?.error?.code || "request_failed", value?.error?.message || "Não foi possível concluir. Tente novamente.");
  return value as T;
}
export async function downloadReport(path: string) {
  let response = await fetch(`/api/${path}`, { credentials: "same-origin", cache: "no-store" });
  if (response.status === 401 && await refreshSession()) response = await fetch(`/api/${path}`, { credentials: "same-origin", cache: "no-store" });
  if (!response.ok) throw new Error("Não foi possível exportar o relatório. Confira sua autenticação multifator.");
  const url = URL.createObjectURL(await response.blob());
  const anchor = document.createElement("a"); anchor.href = url; anchor.download = "aurora-relatorio.xlsx"; anchor.click(); URL.revokeObjectURL(url);
}
