export interface Tokens { access_token: string; refresh_token: string; token_type: string; expires_in: number }
export interface TokenStore { read(): Promise<Tokens | null>; write(tokens: Tokens): Promise<void>; clear(): Promise<void> }
export type RequestOptions = { method?: "GET" | "POST" | "PATCH" | "DELETE"; body?: unknown; idempotencyKey?: string; authenticated?: boolean };

export class ApiError extends Error {
  readonly code: string;
  readonly status: number;
  constructor(message: string, code: string, status: number) { super(message); this.name = "ApiError"; this.code = code; this.status = status; }
}

export function createApiClient(options: { baseUrl: string; store: TokenStore; fetcher?: typeof fetch; onExpired?: () => void; timeoutMs?: number }) {
  const fetcher = options.fetcher ?? fetch;
  let refreshInFlight: Promise<Tokens> | null = null;
  let generation = 0;
  let loggingOut = false;
  let storeChanges: Promise<unknown> = Promise.resolve();
  function mutateStore<T>(action: () => Promise<T>): Promise<T> {
    const operation = storeChanges.then(action);
    storeChanges = operation.catch(() => {});
    return operation;
  }
  function clearStore() { return mutateStore(() => options.store.clear()); }
  function writeStore(tokens: Tokens, expectedGeneration: number) {
    return mutateStore(async () => {
      if (generation !== expectedGeneration || loggingOut) throw new ApiError("Sessão encerrada.", "session_expired", 401);
      await options.store.write(tokens);
      if (generation !== expectedGeneration || loggingOut) { await options.store.clear(); throw new ApiError("Sessão encerrada.", "session_expired", 401); }
    });
  }

  async function fetchJson(path: string, init: RequestInit): Promise<{ response: Response; body: any }> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), options.timeoutMs ?? 15000);
    try {
      const response = await fetcher(`${options.baseUrl}/api/v1${path}`, { ...init, signal: controller.signal });
      const text = await response.text();
      let body: any = null;
      try { body = text ? JSON.parse(text) : null; } catch { /* O contrato HTTP é validado abaixo. */ }
      if (response.ok && text && body === null) throw new ApiError("Resposta inválida do servidor. Tente novamente.", "invalid_response", response.status);
      return { response, body };
    } catch (error) {
      if (error instanceof ApiError) throw error;
      throw new ApiError("Não foi possível conectar. Confira a API e sua conexão.", "network_error", 0);
    } finally { clearTimeout(timer); }
  }

  function responseError(response: Response, body: any): ApiError {
    return new ApiError(typeof body?.error?.message === "string" ? body.error.message : "Não foi possível concluir a solicitação.", typeof body?.error?.code === "string" ? body.error.code : "request_failed", response.status);
  }

  function validTokens(tokens: any): tokens is Tokens {
    return tokens && typeof tokens.access_token === "string" && /^[0-9a-f]{64}$/.test(tokens.access_token)
      && typeof tokens.refresh_token === "string" && /^[0-9a-f]{64}$/.test(tokens.refresh_token)
      && tokens.token_type === "Bearer" && Number.isSafeInteger(tokens.expires_in) && tokens.expires_in > 0 && tokens.expires_in <= 900;
  }

  async function refresh(staleAccess: string): Promise<Tokens> {
    if (loggingOut) throw new ApiError("Sessão encerrada.", "session_expired", 401);
    if (refreshInFlight) return refreshInFlight;
    const expectedGeneration = generation;
    let pending!: Promise<Tokens>;
    pending = (async () => {
      const current = await options.store.read();
      if (!current) throw new ApiError("Sua sessão expirou. Entre novamente.", "session_expired", 401);
      // Outra chamada pode já ter renovado antes de esta resposta 401 chegar.
      if (current.access_token !== staleAccess) return current;
      const { response, body } = await fetchJson("/auth/refresh", { method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json" }, body: JSON.stringify({ refresh_token: current.refresh_token }) });
      if (!response.ok || !validTokens(body)) throw responseError(response, body);
      if (generation !== expectedGeneration || loggingOut) throw new ApiError("Sessão encerrada.", "session_expired", 401);
      await writeStore(body, expectedGeneration);
      return body;
    })().catch(async error => {
      if (generation === expectedGeneration) { const expiredGeneration = ++generation; await clearStore(); if (generation === expiredGeneration) options.onExpired?.(); }
      throw error;
    }).finally(() => { if (refreshInFlight === pending) refreshInFlight = null; });
    refreshInFlight = pending;
    return pending;
  }

  async function request<T = any>(path: string, config: RequestOptions = {}): Promise<T> {
    let invalidPath = !path.startsWith("/") || path.startsWith("//") || path.includes("://") || path.includes("\\") || path.includes("#");
    try { invalidPath ||= path.split("?")[0].split("/").some(segment => { const decoded = decodeURIComponent(segment); return decoded === "." || decoded === ".." || decoded.includes("/") || decoded.includes("\\"); }); }
    catch { invalidPath = true; }
    if (invalidPath) throw new ApiError("Caminho de API inválido.", "invalid_path", 0);
    const authenticated = config.authenticated !== false;
    const expectedGeneration = generation;
    if (authenticated && loggingOut) throw new ApiError("Sessão encerrada.", "session_expired", 401);
    const current = authenticated ? await options.store.read() : null;
    if (authenticated && !current) throw new ApiError("Entre para continuar.", "unauthorized", 401);
    const send = (access?: string) => {
      const headers: Record<string, string> = { Accept: "application/json", "Content-Type": "application/json" };
      if (access) headers.Authorization = `Bearer ${access}`;
      if (config.idempotencyKey) headers["Idempotency-Key"] = config.idempotencyKey;
      return fetchJson(path, { method: config.method ?? "GET", headers, ...(config.body === undefined ? {} : { body: JSON.stringify(config.body) }) });
    };
    let result = await send(current?.access_token);
    if (authenticated && generation !== expectedGeneration) throw new ApiError("Sessão encerrada.", "session_expired", 401);
    if (result.response.status === 401 && authenticated && current) {
      const renewed = await refresh(current.access_token);
      result = await send(renewed.access_token);
    }
    if (authenticated && generation !== expectedGeneration) throw new ApiError("Sessão encerrada.", "session_expired", 401);
    if (!result.response.ok) {
      if (result.response.status === 401 && authenticated && generation === expectedGeneration) { const expiredGeneration = ++generation; await clearStore(); if (generation === expiredGeneration) options.onExpired?.(); }
      throw responseError(result.response, result.body);
    }
    return result.body as T;
  }

  async function login(body: { email: string; password: string; otp_code?: string; recovery_code?: string }): Promise<void> {
    const expectedGeneration = ++generation;
    loggingOut = false;
    refreshInFlight = null;
    await clearStore();
    const result = await request<Tokens>("/auth/login", { method: "POST", body, authenticated: false });
    if (!validTokens(result)) throw new ApiError("Resposta de autenticação inválida.", "invalid_response", 0);
    if (generation !== expectedGeneration || loggingOut) throw new ApiError("Sessão encerrada.", "session_expired", 401);
    await writeStore(result, expectedGeneration);
  }

  async function logout(): Promise<void> {
    loggingOut = true;
    const expectedGeneration = ++generation;
    try {
      const current = await options.store.read();
      if (current) {
        const result = await fetchJson("/auth/logout", { method: "DELETE", headers: { Accept: "application/json", Authorization: `Bearer ${current.access_token}` } });
        if (result.response.status === 401) {
          const renewed = await fetchJson("/auth/refresh", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ refresh_token: current.refresh_token }) });
          // A concurrently consumed refresh is rejected by Rails and revokes the family.
          if (renewed.response.ok && validTokens(renewed.body)) {
            await fetchJson("/auth/logout", { method: "DELETE", headers: { Accept: "application/json", Authorization: `Bearer ${renewed.body.access_token}` } });
          }
        }
      }
    } finally { if (generation === expectedGeneration) { await clearStore(); if (generation === expectedGeneration) options.onExpired?.(); } }
  }

  return { request, login, logout };
}
