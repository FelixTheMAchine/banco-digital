export const money = (value: number | null | undefined) => new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format((value || 0) / 100);
export function date(value?: string | null) {
  if (!value) return "—";
  const parsed = new Date(value.includes("T") ? value : `${value}T12:00:00`);
  if (!Number.isFinite(parsed.getTime())) return "Data indisponível";
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium", timeStyle: value.includes("T") ? "short" : undefined }).format(parsed);
}
export function cents(value: string): number {
  const input = value.trim();
  if (!/^(?:\d+|\d{1,3}(?:\.\d{3})+)(?:,\d{1,2})?$/.test(input)) throw new Error("Informe um valor como 150,00.");
  const normalized = input.replace(/\./g, "");
  const [whole, fraction = ""] = normalized.split(",");
  const amount = Number(BigInt(whole) * 100n + BigInt(fraction.padEnd(2,"0")));
  if (!Number.isSafeInteger(amount) || amount > 100_000_000) throw new Error("Valor fora do limite da simulação.");
  return amount;
}
export function toDecimal(value: number) { return (value / 100).toFixed(2).replace(".", ","); }
export const statusLabel = (value: string) => ({ active: "Ativa", blocked: "Bloqueada", closed: "Encerrada", pending: "Pendente", pending_review: "Em análise", approved: "Aprovado na simulação", rejected: "Não elegível", reviewed_rejected: "Revisão não aprovada", posted: "Concluída", scheduled: "Agendada", cancelled: "Cancelada", open: "Aberto", reviewed: "Revisado", conservative: "Conservador", moderate: "Moderado", aggressive: "Arrojado" } as Record<string,string>)[value] || value;
