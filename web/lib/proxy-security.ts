export function permittedPath(parts: string[]): string | null {
  if (!parts.length || parts.length > 8 || parts.some(p => !/^[a-zA-Z0-9_-]+(?:\.xlsx)?$/.test(p))) return null;
  const path = parts.join("/");
  return path.length <= 250 ? path : null;
}
export function validMutationOrigin(origin: string | null, expected: string, csrf: string | null, fetchSite: string | null): boolean {
  return origin === expected && csrf === "1" && fetchSite !== "cross-site";
}
export function validIdempotencyKey(value: string): boolean {
  return /^[a-zA-Z0-9_-]{8,128}$/.test(value);
}

export function cookieSecurity(production: boolean, override: string | undefined, expectedOrigin: string): boolean | null {
  let origin: URL;
  try { origin = new URL(expectedOrigin); } catch { return null; }
  if (!["http:", "https:"].includes(origin.protocol) || origin.origin !== expectedOrigin) return null;
  const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(origin.hostname);
  if (production && origin.protocol !== "https:" && !loopback) return null;
  if (override === "false") return origin.protocol === "http:" && loopback ? false : null;
  return production || origin.protocol === "https:";
}

export class ProxyInputError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}

export async function limitedBody(stream: ReadableStream<Uint8Array> | null, maxBytes = 32768): Promise<string> {
  if (!stream) return "";
  const reader = stream.getReader(), chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maxBytes) {
        await reader.cancel();
        throw new ProxyInputError(413, "payload_too_large", "Requisição muito grande.");
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return new TextDecoder("utf-8", { fatal: true }).decode(bytes); }
  catch { throw new ProxyInputError(400, "invalid_request", "Conteúdo inválido."); }
}
