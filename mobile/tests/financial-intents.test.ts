import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createFinancialIntents, type FinancialIntent, type IntentStore } from "../src/lib/financial-intents.ts";

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>(yes => { resolve = yes; });
  return { promise, resolve };
}
function memoryStore() {
  let value: FinancialIntent[] = [];
  const store: IntentStore = {
    async read() { return value; },
    async write(intents) { value = intents; },
    async clear() { value = []; }
  };
  return { store, get current() { return value; } };
}
const fingerprint = async (value: string) => createHash("sha256").update(value).digest("hex");

test("preserves the idempotency key after an uncertain failure and a manager restart", async () => {
  const storage = memoryStore();
  let sequence = 0;
  const options = { store: storage.store, fingerprint, newKey: () => `operation-${++sequence}` };
  const first = createFinancialIntents(options);
  let interruptedKey = "";
  const payload = { path: "/transfers", body: { amount_cents: 12345, destination_account_number: "123456" } };
  await assert.rejects(first.perform("customer-a", payload, async key => {
    interruptedKey = key;
    throw new Error("connection interrupted after the server received the request");
  }));
  assert.equal(storage.current[0]?.key, interruptedKey);
  const restarted = createFinancialIntents(options);
  const result = await restarted.perform("customer-a", payload, async key => {
    assert.equal(key, interruptedKey);
    return { id: "already-posted-transaction" };
  });
  assert.deepEqual(result, { id: "already-posted-transaction" });
  assert.equal(sequence, 1);
  assert.deepEqual(storage.current, []);
});

test("concurrent identical intents share the persisted key", async () => {
  const storage = memoryStore();
  const release = deferred<void>();
  const bothStarted = deferred<void>();
  const keys: string[] = [];
  let sequence = 0;
  const manager = createFinancialIntents({ store: storage.store, fingerprint, newKey: () => `operation-${++sequence}` });
  const execute = async (key: string) => {
    keys.push(key);
    if (keys.length === 2) bothStarted.resolve();
    await release.promise;
    return "posted";
  };
  const first = manager.perform("customer-a", { amount_cents: 100 }, execute);
  const second = manager.perform("customer-a", { amount_cents: 100 }, execute);
  await bothStarted.promise;
  assert.deepEqual(keys, ["operation-1", "operation-1"]);
  release.resolve();
  assert.deepEqual(await Promise.all([first, second]), ["posted", "posted"]);
  assert.equal(sequence, 1);
  assert.deepEqual(storage.current, []);
});

test("a changed payload gets another key and an older success cannot clear the newer intent", async () => {
  const storage = memoryStore();
  let sequence = 0;
  const manager = createFinancialIntents({ store: storage.store, fingerprint, newKey: () => `operation-${++sequence}` });
  const olderStarted = deferred<void>();
  const newerStarted = deferred<void>();
  const releaseOlder = deferred<void>();
  const releaseNewer = deferred<void>();
  const older = manager.perform("customer-a", { amount_cents: 100 }, async key => {
    assert.equal(key, "operation-1");
    olderStarted.resolve();
    await releaseOlder.promise;
    return "older posted";
  });
  await olderStarted.promise;
  const newer = manager.perform("customer-a", { amount_cents: 200 }, async key => {
    assert.equal(key, "operation-2");
    newerStarted.resolve();
    await releaseNewer.promise;
    return "newer posted";
  });
  await newerStarted.promise;
  releaseOlder.resolve();
  await older;
  assert.deepEqual(storage.current.map(item => item.key), ["operation-2"]);
  releaseNewer.resolve();
  await newer;
  assert.deepEqual(storage.current, []);
});

test("the same payload in a different user scope never reuses another user's key", async () => {
  const storage = memoryStore();
  let sequence = 0;
  const manager = createFinancialIntents({ store: storage.store, fingerprint, newKey: () => `operation-${++sequence}` });
  const payload = { amount_cents: 100 };
  await assert.rejects(manager.perform("customer-a", payload, async () => { throw new Error("offline"); }));
  const previousKey = storage.current[0]?.key;
  await manager.perform("customer-b", payload, async key => {
    assert.notEqual(key, previousKey);
    return "posted";
  });
  assert.equal(sequence, 2);
  assert.deepEqual(storage.current.map(item => item.key), [previousKey]);
});

test("refuses to submit money if the intent cannot be saved durably first", async () => {
  let submitted = false;
  const manager = createFinancialIntents({
    store: { async read() { return []; }, async write() { throw new Error("secure storage unavailable"); }, async clear() {} },
    fingerprint,
    newKey: () => "operation-1"
  });
  await assert.rejects(manager.perform("customer-a", { amount_cents: 100 }, async () => { submitted = true; }));
  assert.equal(submitted, false);
});

test("different uncertain operations retain independent keys when the first payload is retried", async () => {
  const storage = memoryStore();
  let sequence = 0;
  const options = { store: storage.store, fingerprint, newKey: () => `operation-${++sequence}` };
  const original = createFinancialIntents(options);
  for (const amount_cents of [100, 200]) {
    await assert.rejects(original.perform("customer-a", { amount_cents }, async () => { throw new Error("connection interrupted"); }));
  }
  assert.deepEqual(storage.current.map(item => item.key), ["operation-1", "operation-2"]);
  const restarted = createFinancialIntents(options);
  await restarted.perform("customer-a", { amount_cents: 100 }, async key => {
    assert.equal(key, "operation-1");
    return "first already posted";
  });
  assert.deepEqual(storage.current.map(item => item.key), ["operation-2"]);
  await restarted.perform("customer-a", { amount_cents: 200 }, async key => {
    assert.equal(key, "operation-2");
    return "second already posted";
  });
  assert.equal(sequence, 2);
  assert.deepEqual(storage.current, []);
});

test("a full pending queue blocks new intents without dropping unresolved operation keys", async () => {
  const storage = memoryStore();
  let sequence = 0;
  const manager = createFinancialIntents({ store: storage.store, fingerprint, newKey: () => `operation-${++sequence}` });
  for (let amount_cents = 1; amount_cents <= 8; amount_cents++) {
    await assert.rejects(manager.perform("customer-a", { amount_cents }, async () => { throw new Error("offline"); }));
  }
  const keys = storage.current.map(item => item.key);
  let submitted = false;
  await assert.rejects(manager.perform("customer-a", { amount_cents: 9 }, async () => { submitted = true; }), /operações sem confirmação/);
  assert.equal(submitted, false);
  assert.equal(sequence, 8);
  assert.deepEqual(storage.current.map(item => item.key), keys);
  await manager.perform("customer-a", { amount_cents: 1 }, async key => {
    assert.equal(key, "operation-1");
    return "already posted";
  });
  assert.deepEqual(storage.current.map(item => item.key), keys.slice(1));
});

test("a confirmed client rejection releases only its failed intent", async () => {
  const storage = memoryStore();
  let sequence = 0;
  const manager = createFinancialIntents({
    store: storage.store, fingerprint, newKey: () => `operation-${++sequence}`,
    retainFailure: error => (error as { status?: number }).status !== 422
  });
  await assert.rejects(manager.perform("customer-a", { amount_cents: 100 }, async () => { throw new Error("unknown connection result"); }));
  await assert.rejects(manager.perform("customer-a", { amount_cents: 200 }, async () => { throw Object.assign(new Error("insufficient balance"), { status: 422 }); }));
  assert.deepEqual(storage.current.map(item => item.key), ["operation-1"]);
});

test("uncertain server failures keep their key for a safe retry", async () => {
  const storage = memoryStore();
  let sequence = 0;
  const manager = createFinancialIntents({
    store: storage.store, fingerprint, newKey: () => `operation-${++sequence}`,
    retainFailure: error => (error as { status?: number }).status === 0 || ((error as { status?: number }).status ?? 500) >= 500
  });
  await assert.rejects(manager.perform("customer-a", { amount_cents: 100 }, async () => { throw Object.assign(new Error("upstream unavailable"), { status: 503 }); }));
  await manager.perform("customer-a", { amount_cents: 100 }, async key => {
    assert.equal(key, "operation-1");
    return "posted once";
  });
  assert.equal(sequence, 1);
  assert.deepEqual(storage.current, []);
});
