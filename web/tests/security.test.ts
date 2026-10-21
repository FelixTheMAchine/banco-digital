import test from "node:test";
import assert from "node:assert/strict";
import { cookieSecurity, limitedBody, permittedPath, ProxyInputError, validMutationOrigin } from "../lib/proxy-security";
import { cents, date } from "../lib/format";

test("proxy refuses path traversal, absolute URLs and encoded route injection", () => {
  for (const path of [["..", "me"], ["https:", "evil.test"], ["%2e%2e"], ["auth/login?x=1"], ["a\\b"]]) assert.equal(permittedPath(path), null);
  assert.equal(permittedPath(["transactions", "a-b-c", "receipt"]), "transactions/a-b-c/receipt");
  assert.equal(permittedPath(["admin", "exports.xlsx"]), "admin/exports.xlsx");
});

test("mutation needs exact origin and CSRF header even when fetch metadata is absent", () => {
  const origin = "https://banco.example.test";
  assert.equal(validMutationOrigin(origin, origin, "1", "same-origin"), true);
  for (const candidate of [null, "null", "https://evil.test", origin + ".evil.test", origin + "/"]) assert.equal(validMutationOrigin(candidate, origin, "1", null), false);
  assert.equal(validMutationOrigin(origin, origin, null, "same-origin"), false);
  assert.equal(validMutationOrigin(origin, origin, "1", "cross-site"), false);
});

test("production cookies require HTTPS except an explicit local development override", () => {
  assert.equal(cookieSecurity(true, undefined, "https://banco.example.test"), true);
  assert.equal(cookieSecurity(true, undefined, "http://banco.example.test"), null);
  assert.equal(cookieSecurity(true, "false", "https://banco.example.test"), null);
  assert.equal(cookieSecurity(true, "false", "http://localhost:3000"), false);
  assert.equal(cookieSecurity(true, "false", "http://localhost.evil.test:3000"), null);
  assert.equal(cookieSecurity(false, undefined, "https://localhost:3000"), true);
});

test("chunked bodies are stopped at the limit without trusting Content-Length", async () => {
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({ start(controller) { controller.enqueue(new Uint8Array(16384)); controller.enqueue(new Uint8Array(16385)); }, cancel() { cancelled = true; } });
  await assert.rejects(() => limitedBody(stream), error => error instanceof ProxyInputError && error.status === 413);
  assert.equal(cancelled, true);
});

test("proxy accepts bounded UTF-8 and rejects malformed encoding without crashing", async () => {
  const text = '{"nome":"João"}';
  assert.equal(await limitedBody(new Response(text).body), text);
  const invalid = new ReadableStream<Uint8Array>({ start(controller) { controller.enqueue(new Uint8Array([0xc3, 0x28])); controller.close(); } });
  await assert.rejects(() => limitedBody(invalid), error => error instanceof ProxyInputError && error.status === 400);
});

test("money parsing preserves cents and rejects ambiguous separators or unsafe values", () => {
  assert.equal(cents("1.234,56"), 123456);
  assert.equal(cents("0,01"), 1);
  assert.equal(cents("0"), 0);
  for (const value of ["-1,00", "1.2", "1e6", "0,001", "NaN", "100000000000000000000,00", "1 000,00"]) assert.throws(() => cents(value));
});

test("invalid server dates display a controlled fallback", () => {
  assert.equal(date("not-a-date"), "Data indisponível");
  assert.equal(date(null), "—");
});
