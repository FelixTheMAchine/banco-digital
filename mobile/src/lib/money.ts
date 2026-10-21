const MAX_CENTS = 9_000_000_000_000_000n;

/** Entrada BRL em unidades decimais; nenhuma conversão por ponto flutuante. */
export function parseCents(input: string): number {
  const value = input.trim();
  if (value.length > 32 || !/^(?:\d+|\d{1,3}(?:\.\d{3})+)(?:,\d{1,2})?$/.test(value)) {
    throw new Error("Informe um valor como 150,00. Use vírgula para os centavos.");
  }
  const [units, fraction = ""] = value.replace(/\./g, "").split(",");
  const cents = BigInt(units) * 100n + BigInt(fraction.padEnd(2, "0") || "0");
  if (cents > MAX_CENTS) throw new Error("Valor acima do limite permitido.");
  return Number(cents);
}

export function positiveCents(input: string): number {
  const cents = parseCents(input);
  if (cents === 0) throw new Error("O valor precisa ser maior que zero.");
  return cents;
}

export function formatCents(value: number | string | undefined | null): string {
  if (value === undefined || value === null) return "—";
  const source = typeof value === "number" ? (Number.isSafeInteger(value) ? String(value) : "") : value;
  if (!/^-?\d+$/.test(source)) return "—";
  const cents = BigInt(source);
  const absolute = cents < 0n ? -cents : cents;
  const units = (absolute / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `${cents < 0n ? "−" : ""}R$ ${units},${(absolute % 100n).toString().padStart(2, "0")}`;
}

export function editableCents(value: number): string {
  if (!Number.isSafeInteger(value) || value < 0) return "0,00";
  const cents = BigInt(value);
  return `${cents / 100n},${(cents % 100n).toString().padStart(2, "0")}`;
}

export function integerInRange(value: string, min: number, max: number): number {
  if (!/^\d+$/.test(value)) throw new Error(`Informe um número inteiro de ${min} a ${max}.`);
  const result = Number(value);
  if (!Number.isSafeInteger(result) || result < min || result > max) throw new Error(`Informe um número inteiro de ${min} a ${max}.`);
  return result;
}
