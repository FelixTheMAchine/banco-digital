import { NextRequest, NextResponse } from "next/server";
import { createHash } from "node:crypto";
import { cookieSecurity, limitedBody, permittedPath, ProxyInputError, validMutationOrigin, validIdempotencyKey } from "@/lib/proxy-security";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
const ACCESS = "aurora_access", REFRESH = "aurora_refresh";
type Tokens = { access_token: string; refresh_token: string; expires_in: number };
const refreshes = new Map<string, { promise: Promise<Tokens | null>; expires: number }>();
type CookieOptions = { httpOnly: true; secure: boolean; sameSite: "strict"; path: string };
function failure(status: number, code: string, message: string) {
  return NextResponse.json({ error: { code, message } }, { status, headers: { "Cache-Control": "no-store" } });
}
function clear(response: NextResponse, cookieOptions: CookieOptions) {
  response.cookies.set(ACCESS, "", { ...cookieOptions, maxAge: 0 });
  response.cookies.set(REFRESH, "", { ...cookieOptions, maxAge: 0 });
}
function write(response: NextResponse, tokens: Tokens, cookieOptions: CookieOptions) {
  response.cookies.set(ACCESS, tokens.access_token, { ...cookieOptions, maxAge: Math.min(tokens.expires_in, 900) });
  response.cookies.set(REFRESH, tokens.refresh_token, { ...cookieOptions, maxAge: 30 * 24 * 60 * 60 });
}
function tokenPair(input: unknown): Tokens | null {
  if (!input || typeof input !== "object") return null;
  const t = input as Partial<Tokens>;
  return typeof t.access_token === "string" && /^[a-f0-9]{64}$/.test(t.access_token) && typeof t.refresh_token === "string" && /^[a-f0-9]{64}$/.test(t.refresh_token) && typeof t.expires_in === "number" && t.expires_in > 0 ? t as Tokens : null;
}
async function rotate(base: URL, raw: string): Promise<Tokens | null> {
  const key = createHash("sha256").update(raw).digest("hex");
  for (const [existing, value] of refreshes) if (value.expires <= Date.now()) refreshes.delete(existing);
  let pending = refreshes.get(key);
  if (!pending) {
    while (refreshes.size >= 256) refreshes.delete(refreshes.keys().next().value!);
    const promise = (async () => {
      const result = await fetch(new URL("api/v1/auth/refresh", base), { method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json" }, body: JSON.stringify({ refresh_token: raw }), cache: "no-store", redirect: "error", signal: AbortSignal.timeout(15000) });
      return result.ok ? tokenPair(await result.json()) : null;
    })();
    pending = { promise, expires: Date.now() + 15000 };
    refreshes.set(key, pending);
    const entry = pending;
    void promise.then(value => {
      if (refreshes.get(key) !== entry) return;
      if (value) entry.expires = Date.now() + 3000;
      else refreshes.delete(key);
    }, () => { if (refreshes.get(key) === entry) refreshes.delete(key); });
  }
  return pending.promise;
}
async function proxy(request: NextRequest, context: { params: Promise<{ path: string[] }> }) {
  const { path: segments } = await context.params;
  const path = permittedPath(segments);
  if (!path) return failure(404, "not_found", "Recurso não encontrado.");
  const mutation = !["GET", "HEAD"].includes(request.method);
  const expectedOrigin = process.env.WEB_ORIGIN || (process.env.NODE_ENV !== "production" ? request.nextUrl.origin : "");
  if (!expectedOrigin) return failure(503, "configuration_error", "Origem da aplicação não configurada.");
  const secure = cookieSecurity(process.env.NODE_ENV === "production", process.env.COOKIE_SECURE, expectedOrigin);
  if (secure === null) return failure(503, "configuration_error", "Configure HTTPS e a origem da aplicação.");
  const cookieOptions: CookieOptions = { httpOnly: true, secure, sameSite: "strict", path: "/api" };
  if (mutation && !validMutationOrigin(request.headers.get("origin"), expectedOrigin, request.headers.get("x-aurora-csrf"), request.headers.get("sec-fetch-site"))) return failure(403, "invalid_origin", "Origem da requisição inválida.");
  const key = request.headers.get("idempotency-key");
  if (key && !validIdempotencyKey(key)) return failure(400, "invalid_request", "Chave de operação inválida.");
  if (request.headers.get("content-length") && Number(request.headers.get("content-length")) > 32768) return failure(413, "payload_too_large", "Requisição muito grande.");
  try {
    const base = new URL(process.env.API_URL || "http://localhost:3001");
    if (!["http:", "https:"].includes(base.protocol) || base.username || base.password) return failure(503, "configuration_error", "API não configurada.");
    base.pathname = base.pathname.replace(/\/?$/, "/");
    const isRefresh = path === "auth/refresh", isLogout = path === "auth/logout";
    const refresh = request.cookies.get(REFRESH)?.value;
    let access = request.cookies.get(ACCESS)?.value;
    if (isRefresh) {
      const tokens = refresh ? await rotate(base, refresh) : null;
      const response = tokens ? NextResponse.json({ authenticated: true }) : failure(401, "unauthorized", "Sua sessão expirou. Entre novamente.");
      if (tokens) write(response, tokens, cookieOptions); else clear(response, cookieOptions);
      response.headers.set("Cache-Control", "no-store");
      return response;
    }
    if (isLogout && refresh) access = (await rotate(base, refresh))?.access_token || access;
    const headers = new Headers({ Accept: path.endsWith(".xlsx") ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" : "application/json" });
    if (access) headers.set("Authorization", `Bearer ${access}`);
    if (key) headers.set("Idempotency-Key", key);
    let body: string | undefined;
    if (["POST", "PATCH", "DELETE"].includes(request.method)) {
      if (["POST", "PATCH"].includes(request.method) && request.headers.get("content-type")?.split(";")[0] !== "application/json") return failure(415, "unsupported_media_type", "Envie JSON.");
      body = await limitedBody(request.body);
      headers.set("Content-Type", "application/json");
    }
    const target = new URL(`api/v1/${path}`, base);
    target.search = request.nextUrl.search;
    const result = await fetch(target, { method: request.method, headers, body: body || undefined, cache: "no-store", redirect: "error", signal: AbortSignal.timeout(15000) });
    if (path === "auth/login" && result.ok) {
      const tokens = tokenPair(await result.json());
      if (!tokens) return failure(502, "invalid_response", "Resposta de autenticação inválida.");
      const response = NextResponse.json({ authenticated: true }, { headers: { "Cache-Control": "no-store" } });
      write(response, tokens, cookieOptions);
      return response;
    }
    const response = new NextResponse(result.status === 204 ? null : await result.arrayBuffer(), { status: result.status, headers: { "Content-Type": result.headers.get("content-type") || "application/json", "Cache-Control": "no-store" } });
    if (result.headers.has("retry-after")) response.headers.set("Retry-After", result.headers.get("retry-after")!);
    if (path.endsWith(".xlsx") && result.ok) response.headers.set("Content-Disposition", 'attachment; filename="aurora-relatorio.xlsx"');
    if (isLogout) clear(response, cookieOptions);
    return response;
  } catch (error) {
    if (error instanceof ProxyInputError) return failure(error.status, error.code, error.message);
    const response = failure(503, "service_unavailable", "Não foi possível conectar ao banco simulado. Tente novamente.");
    if (path === "auth/logout") clear(response, cookieOptions);
    return response;
  }
}
export { proxy as GET, proxy as POST, proxy as PATCH, proxy as DELETE };
