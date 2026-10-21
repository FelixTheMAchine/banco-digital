export interface FinancialIntent { scope: string; fingerprint: string; key: string }
export interface IntentStore {
  read(): Promise<FinancialIntent[]>;
  write(intents: FinancialIntent[]): Promise<void>;
  clear(): Promise<void>;
}

export function retainUncertainFailure(error: unknown): boolean {
  const status = error && typeof error === "object" && "status" in error ? error.status : undefined;
  return !Number.isInteger(status) || (status as number) < 400 || (status as number) >= 500;
}

/** Mantém a mesma chave após falha de rede ou reinício, até haver resposta confirmada. */
export function createFinancialIntents(options: { store: IntentStore; fingerprint: (value: string) => Promise<string>; newKey: () => string; retainFailure?: (error: unknown) => boolean }) {
  let changes: Promise<unknown> = Promise.resolve();
  function serial<T>(action: () => Promise<T>): Promise<T> {
    const operation = changes.then(action);
    changes = operation.catch(() => {});
    return operation;
  }
  return {
    async perform<T>(scope: string, payload: unknown, execute: (key: string) => Promise<T>): Promise<T> {
      const fingerprint = await options.fingerprint(JSON.stringify(payload));
      const intent = await serial(async () => {
        const pending = await options.store.read();
        const previous = pending.find(item => item.scope === scope && item.fingerprint === fingerprint);
        if (previous) return previous;
        if (pending.length >= 8) throw new Error("Há operações sem confirmação. Confira o extrato e repita as solicitações pendentes antes de iniciar outra.");
        const next = { scope, fingerprint, key: options.newKey() };
        await options.store.write([...pending, next]);
        return next;
      });
      const remove = () => serial(async () => {
        const remaining = (await options.store.read()).filter(item => item.key !== intent.key);
        if (remaining.length) await options.store.write(remaining);
        else await options.store.clear();
      });
      try {
        const result = await execute(intent.key);
        await remove();
        return result;
      } catch (error) {
        if (options.retainFailure && !options.retainFailure(error)) await remove();
        throw error;
      }
    }
  };
}
