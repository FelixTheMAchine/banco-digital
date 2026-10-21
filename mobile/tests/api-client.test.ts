import test from "node:test";
import assert from "node:assert/strict";
import { ApiError, createApiClient, type Tokens, type TokenStore } from "../src/lib/api-client.ts";

const oldTokens: Tokens = { access_token: "a".repeat(64), refresh_token: "b".repeat(64), token_type: "Bearer", expires_in: 900 };
const newTokens: Tokens = { access_token: "c".repeat(64), refresh_token: "d".repeat(64), token_type: "Bearer", expires_in: 900 };
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
const unauthorized = () => json({ error: { code: "unauthorized", message: "Sessão expirada" } }, 401);
const fetcher = (callback: (url: string, init: RequestInit) => Promise<Response> | Response) => ((input: string | URL | Request, init?: RequestInit) => callback(String(input), init ?? {})) as typeof fetch;
function memoryStore(initial: Tokens | null = oldTokens) {
  let current = initial;
  let writes = 0;
  let clears = 0;
  const store: TokenStore = {
    async read() { return current; },
    async write(tokens) { current = tokens; writes++; },
    async clear() { current = null; clears++; }
  };
  return { store, get current() { return current; }, get writes() { return writes; }, get clears() { return clears; } };
}
function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

test("serializes concurrent refreshes and retries requests with the one new token pair", async () => {
  const storage = memoryStore();
  const started = deferred<void>();
  const release = deferred<Response>();
  let refreshCount = 0;
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher(async (url, init) => {
    if (url.endsWith("/auth/refresh")) { refreshCount++; started.resolve(); return release.promise; }
    return new Headers(init.headers).get("Authorization") === `Bearer ${oldTokens.access_token}` ? unauthorized() : json({ ok: true });
  }) });
  const requests = [client.request("/me"), client.request("/dashboard"), client.request("/sessions")];
  await started.promise;
  release.resolve(json(newTokens));
  assert.deepEqual(await Promise.all(requests), [{ ok: true }, { ok: true }, { ok: true }]);
  assert.equal(refreshCount, 1);
  assert.equal(storage.writes, 1);
  assert.deepEqual(storage.current, newTokens);
});

test("a late 401 reuses the already renewed pair instead of replaying its old refresh", async () => {
  const storage = memoryStore();
  const lateResponse = deferred<Response>();
  let refreshCount = 0;
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher((url, init) => {
    if (url.endsWith("/auth/refresh")) { refreshCount++; return json(newTokens); }
    const old = new Headers(init.headers).get("Authorization") === `Bearer ${oldTokens.access_token}`;
    if (url.endsWith("?late=1") && old) return lateResponse.promise;
    return old ? unauthorized() : json({ ok: true });
  }) });
  const slow = client.request("/me?late=1");
  assert.deepEqual(await client.request("/me"), { ok: true });
  lateResponse.resolve(unauthorized());
  assert.deepEqual(await slow, { ok: true });
  assert.equal(refreshCount, 1);
});

test("refresh rejection erases stored credentials and reports expiry", async () => {
  const storage = memoryStore();
  let expired = 0;
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, onExpired: () => expired++, fetcher: fetcher(() => unauthorized()) });
  await assert.rejects(client.request("/me"), (error: unknown) => error instanceof ApiError && error.status === 401);
  assert.equal(storage.current, null);
  assert.equal(expired, 1);
});

test("an authenticated request without a session never contacts the API", async () => {
  const storage = memoryStore(null);
  let calls = 0;
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher(() => { calls++; return json({}); }) });
  await assert.rejects(client.request("/me"), (error: unknown) => error instanceof ApiError && error.code === "unauthorized");
  assert.equal(calls, 0);
});

test("passes MFA login credentials only in the request body and stores valid tokens", async () => {
  const storage = memoryStore(null);
  const credentials = { email: "client@example.test", password: "Ficticia-Forte-1234", otp_code: "123456" };
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher((url, init) => {
    assert.equal(url, "https://api.example.test/api/v1/auth/login");
    assert.equal(init.method, "POST");
    assert.equal(new Headers(init.headers).has("Authorization"), false);
    assert.deepEqual(JSON.parse(String(init.body)), credentials);
    return json(newTokens);
  }) });
  await client.login(credentials);
  assert.deepEqual(storage.current, newTokens);
});

test("rejects malformed successful authentication responses", async () => {
  for (const response of [{ access_token: "plain", refresh_token: "value" }, { access_token: "c".repeat(64), refresh_token: "d".repeat(64) }]) {
    const storage = memoryStore(null);
    const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher(() => json(response)) });
    await assert.rejects(client.login({ email: "client@example.test", password: "Ficticia-Forte-1234" }), (error: unknown) => error instanceof ApiError && error.code === "invalid_response");
    assert.equal(storage.current, null);
  }
});

test("retains the same idempotency key and payload across the single auth retry", async () => {
  const storage = memoryStore();
  const seen: { key: string | null; body: string }[] = [];
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher((url, init) => {
    if (url.endsWith("/auth/refresh")) return json(newTokens);
    seen.push({ key: new Headers(init.headers).get("Idempotency-Key"), body: String(init.body) });
    return seen.length === 1 ? unauthorized() : json({ transaction: { id: "transaction-id" } }, 201);
  }) });
  await client.request("/transfers", { method: "POST", idempotencyKey: "unique-operation-123", body: { amount_cents: 100, destination_account_number: "12345678" } });
  assert.equal(seen.length, 2);
  assert.deepEqual(seen[0], seen[1]);
  assert.equal(seen[0].key, "unique-operation-123");
});

test("clears local credentials even when remote logout fails", async () => {
  const storage = memoryStore();
  let expired = 0;
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, onExpired: () => expired++, fetcher: fetcher(() => { throw new Error("offline"); }) });
  await assert.rejects(client.logout(), (error: unknown) => error instanceof ApiError && error.code === "network_error");
  assert.equal(storage.current, null);
  assert.equal(expired, 1);
});

test("an in-flight refresh cannot restore a session after logout", async () => {
  const storage = memoryStore();
  const started = deferred<void>();
  const refreshResponse = deferred<Response>();
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher((url, init) => {
    if (url.endsWith("/auth/logout")) return new Response(null, { status: 204 });
    if (url.endsWith("/auth/refresh")) { started.resolve(); return refreshResponse.promise; }
    return new Headers(init.headers).get("Authorization") === `Bearer ${oldTokens.access_token}` ? unauthorized() : json({ ok: true });
  }) });
  const pending = client.request("/me");
  await started.promise;
  await client.logout();
  refreshResponse.resolve(json(newTokens));
  await assert.rejects(pending);
  assert.equal(storage.current, null);
  assert.equal(storage.writes, 0);
});

test("an old refresh failure cannot erase a newer successful login", async () => {
  const storage = memoryStore();
  const started = deferred<void>();
  const refreshResponse = deferred<Response>();
  let expired = 0;
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, onExpired: () => expired++, fetcher: fetcher((url) => {
    if (url.endsWith("/auth/login")) return json(newTokens);
    if (url.endsWith("/auth/refresh")) { started.resolve(); return refreshResponse.promise; }
    return unauthorized();
  }) });
  const pending = client.request("/me");
  await started.promise;
  await client.login({ email: "client@example.test", password: "Ficticia-Forte-1234" });
  refreshResponse.resolve(unauthorized());
  await assert.rejects(pending);
  assert.deepEqual(storage.current, newTokens);
  assert.equal(expired, 0);
});

test("a delayed secure-store refresh write cannot replace or erase a newer login", async () => {
  const loginTokens: Tokens = { access_token: "e".repeat(64), refresh_token: "f".repeat(64), token_type: "Bearer", expires_in: 900 };
  let current: Tokens | null = oldTokens;
  const writeStarted = deferred<void>();
  const releaseWrite = deferred<void>();
  const store: TokenStore = {
    async read() { return current; },
    async clear() { current = null; },
    async write(tokens) {
      if (tokens.access_token === newTokens.access_token) { writeStarted.resolve(); await releaseWrite.promise; }
      current = tokens;
    }
  };
  const client = createApiClient({ baseUrl: "https://api.example.test", store, fetcher: fetcher((url) => {
    if (url.endsWith("/auth/login")) return json(loginTokens);
    if (url.endsWith("/auth/refresh")) return json(newTokens);
    return unauthorized();
  }) });
  const pendingRefresh = client.request("/me");
  // Attach the rejection listener before another asynchronous mutation invalidates it.
  const rejectedRefresh = assert.rejects(pendingRefresh);
  await writeStarted.promise;
  const login = client.login({ email: "client@example.test", password: "Ficticia-Forte-1234" });
  // Let the newer login proceed as far as its storage mutation queue permits.
  await new Promise<void>(resolve => setImmediate(resolve));
  releaseWrite.resolve();
  await Promise.all([rejectedRefresh, login]);
  assert.deepEqual(current, loginTokens);
});

test("a late response from an older logout cannot erase a newer login", async () => {
  const storage = memoryStore();
  const logoutStarted = deferred<void>();
  const logoutResponse = deferred<Response>();
  let expired = 0;
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, onExpired: () => expired++, fetcher: fetcher((url) => {
    if (url.endsWith("/auth/logout")) { logoutStarted.resolve(); return logoutResponse.promise; }
    if (url.endsWith("/auth/login")) return json(newTokens);
    return json({ ok: true });
  }) });
  const oldLogout = client.logout();
  await logoutStarted.promise;
  await client.login({ email: "client@example.test", password: "Ficticia-Forte-1234" });
  logoutResponse.resolve(new Response(null, { status: 204 }));
  await oldLogout;
  assert.deepEqual(storage.current, newTokens);
  assert.equal(expired, 0);
  assert.deepEqual(await client.request("/me"), { ok: true });
});

test("retries unauthorized requests once and then expires the session", async () => {
  const storage = memoryStore();
  let requestCount = 0;
  let refreshCount = 0;
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher((url) => {
    if (url.endsWith("/auth/refresh")) { refreshCount++; return json(newTokens); }
    requestCount++;
    return unauthorized();
  }) });
  await assert.rejects(client.request("/me"));
  assert.equal(requestCount, 2);
  assert.equal(refreshCount, 1);
  assert.equal(storage.current, null);
});

test("rejects absolute or protocol-relative paths before making a request", async () => {
  const storage = memoryStore();
  let calls = 0;
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher(() => { calls++; return json({}); }) });
  for (const path of ["https://evil.example/collect", "//evil.example", "me", "/https://evil.example", "/../admin", "/%2e%2e/admin", "/a/%2f/b", "/a/%5c/b", "/%ZZ", "/./me", "/x/../me", "/me#secret"]) {
    await assert.rejects(client.request(path), (error: unknown) => error instanceof ApiError && error.code === "invalid_path");
  }
  assert.equal(calls, 0);
});

test("rejects invalid JSON returned with a successful status", async () => {
  const storage = memoryStore();
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher(() => new Response("<html>upstream error</html>", { status: 200 })) });
  await assert.rejects(client.request("/me"), (error: unknown) => error instanceof ApiError && error.code === "invalid_response");
});

test("does not automatically retry an uncertain financial network failure", async () => {
  const storage = memoryStore();
  let attempts = 0;
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, fetcher: fetcher(() => {
    attempts++;
    throw new Error("connection interrupted after submission");
  }) });
  await assert.rejects(client.request("/transfers", { method: "POST", idempotencyKey: "stable-operation-123", body: { amount_cents: 100 } }), (error: unknown) => error instanceof ApiError && error.code === "network_error");
  assert.equal(attempts, 1);
  assert.deepEqual(storage.current, oldTokens);
});

test("aborts stalled network requests at the configured deadline", async () => {
  const storage = memoryStore();
  const client = createApiClient({ baseUrl: "https://api.example.test", store: storage.store, timeoutMs: 5, fetcher: fetcher((_url, init) => new Promise((_resolve, reject) => {
    init.signal?.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
  })) });
  await assert.rejects(client.request("/me"), (error: unknown) => error instanceof ApiError && error.code === "network_error");
});
