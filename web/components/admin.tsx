"use client";

import Link from "next/link";
import { useEffect, useState, type FormEvent } from "react";
import { Download, FileCheck2, ShieldCheck, Users, Wallet } from "lucide-react";
import { api, downloadReport } from "@/lib/api";
import { date, money, statusLabel } from "@/lib/format";
import { Heading } from "./banking";
import { Empty, Feedback, Field, Loading, Modal, Select, useAction, useResource } from "./ui";

type Section = "users" | "accounts" | "transactions" | "security_events" | "loans" | "audit_logs" | "rules" | "exports";
type Row = Record<string, unknown> & { id: string; status?: string };
type Pagination = { page: number; total_pages: number; total_count: number };
type Overview = { users_count: number; accounts_count: number; transactions_count: number; open_security_events_count: number; pending_loans_count: number; total_available_cents: number };
type Confirmation = { path: string; title: string; body: Record<string, unknown>; description: string };
const sections: [Section, string][] = [["users", "Clientes"], ["accounts", "Contas"], ["transactions", "Movimentações"], ["security_events", "Alertas"], ["loans", "Crédito"], ["audit_logs", "Auditoria"], ["rules", "Regras"], ["exports", "Relatórios"]];
const columns: Record<string, [string, string][]> = {
  users: [["full_name", "Cliente"], ["email", "E-mail"], ["cpf", "CPF mascarado"], ["status", "Status"], ["role", "Papel"]],
  accounts: [["number", "Conta"], ["branch", "Agência"], ["available_cents", "Disponível"], ["blocked_cents", "Bloqueado"], ["status", "Status"]],
  transactions: [["kind", "Operação"], ["amount_cents", "Valor"], ["description", "Descrição"], ["created_at", "Data"]],
  security_events: [["kind", "Evento"], ["severity", "Severidade"], ["reasons", "Motivos"], ["status", "Status"], ["created_at", "Data"]],
  loans: [["amount_cents", "Solicitado"], ["installment_cents", "Parcela"], ["term_months", "Meses"], ["status", "Decisão"], ["created_at", "Data"]],
  audit_logs: [["action", "Evento"], ["user_id", "Autor"], ["subject_id", "Recurso"], ["created_at", "Data"]]
};

function cell(key: string, value: unknown) {
  if (value === null || value === undefined || value === "") return "—";
  if (key.endsWith("_cents") && typeof value === "number") return money(value);
  if (key.endsWith("_at") && typeof value === "string") return date(value);
  if (Array.isArray(value)) return value.map(item => String(item)).join(", ");
  if (key === "status") return statusLabel(String(value));
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

export function AdminView() {
  const overview = useResource<{ overview: Overview }>("admin/overview");
  const [section, setSection] = useState<Section>("security_events");
  return <>
    <Heading title="Administração Aurora" description="Revisão controlada, decisões explicáveis e trilha de auditoria."><span className="pill"><ShieldCheck size={14} />Acesso restrito</span></Heading>
    <div className="alert warning">A administração exige papel autorizado, MFA ativo e confirmação adicional nos últimos cinco minutos. <Link className="text-link" href="/seguranca">Confirmar autenticação</Link></div>
    <Feedback error={overview.error} />
    {overview.loading ? <Loading text="Verificando acesso administrativo…" /> : overview.data && <div className="grid-3" style={{ marginBottom: 24 }}>
      <div className="card stat-card"><span className="stat-icon"><Users size={19} /></span><div className="stat-value">{overview.data.overview.users_count}</div><p>Clientes • {overview.data.overview.accounts_count} contas</p></div>
      <div className="card stat-card"><span className="stat-icon"><Wallet size={19} /></span><div className="stat-value">{money(overview.data.overview.total_available_cents)}</div><p>Saldo total fictício • {overview.data.overview.transactions_count} operações</p></div>
      <div className="card stat-card"><span className="stat-icon coral"><FileCheck2 size={19} /></span><div className="stat-value">{overview.data.overview.open_security_events_count}</div><p>Alertas abertos • {overview.data.overview.pending_loans_count} análises de crédito</p></div>
    </div>}
    {overview.data && <><nav className="admin-nav" aria-label="Áreas administrativas">{sections.map(([key, title]) => <button key={key} className={`button small ${section === key ? "" : "secondary"}`} aria-current={section === key ? "page" : undefined} onClick={() => setSection(key)}>{title}</button>)}</nav>
      {section === "rules" ? <RulesView /> : section === "exports" ? <ExportsView /> : <RecordsView section={section} onChanged={overview.reload} />}
    </>}
    <p className="footer-note">Nenhuma ação administrativa permite editar saldos diretamente. Os valores são fictícios e os registros financeiros permanecem imutáveis.</p>
  </>;
}

function RecordsView({ section, onChanged }: { section: Exclude<Section, "rules" | "exports">; onChanged: () => void }) {
  const [page, setPage] = useState(1);
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);
  const action = useAction();
  const resource = useResource<Record<string, unknown>>(`admin/${section}?page=${page}`);
  useEffect(() => { setPage(1); }, [section]);
  const rows = (resource.data?.[section] || []) as Row[];
  const pagination = resource.data?.pagination as Pagination | undefined;
  function accountAction(row: Row, unblock: boolean) {
    setConfirmation({ path: `admin/accounts/${row.id}/${unblock ? "unblock" : "block"}`, body: {}, title: unblock ? "Reativar operações da conta?" : "Bloquear a conta?", description: `Conta ${String(row.number)}. A mudança será registrada na auditoria. ${unblock ? "Confira o motivo original do bloqueio antes de autorizar a reativação." : "O bloqueio impede novas operações e não altera o saldo."}` });
  }
  return <section className="card"><div className="card-heading"><h2>{sections.find(([key]) => key === section)?.[1]}</h2><button className="text-link" onClick={resource.reload} disabled={resource.loading}>Atualizar</button></div><Feedback error={resource.error || action.error} success={action.success} />
    {resource.loading ? <Loading text="Consultando registros…" /> : !rows.length ? <Empty>Nenhum registro encontrado nesta página.</Empty> : <div className="table-wrap"><table><thead><tr>{columns[section].map(([key, label]) => <th key={key}>{label}</th>)}<th>Detalhes e ações</th></tr></thead><tbody>{rows.map(row => <tr key={row.id}>{columns[section].map(([key]) => <td key={key} style={{ maxWidth: 240, overflowWrap: "anywhere" }}>{cell(key, row[key])}</td>)}<td><div style={{ display: "flex", flexDirection: "column", gap: 12, alignItems: "flex-end", minWidth: 100 }}>
      {section === "accounts" && row.status === "active" && <button className="text-link" disabled={action.busy} onClick={() => accountAction(row, false)}>Bloquear</button>}
      {section === "accounts" && row.status === "blocked" && <button className="text-link" disabled={action.busy} onClick={() => accountAction(row, true)}>Desbloquear</button>}
      {section === "security_events" && row.status === "open" && <button className="text-link" disabled={action.busy} onClick={() => setConfirmation({ path: `admin/security_events/${row.id}/review`, body: {}, title: "Registrar revisão do alerta", description: "Explique os achados e as medidas adotadas. Revisar um alerta não desbloqueia automaticamente uma conta." })}>Revisar</button>}
      {section === "loans" && row.status === "pending_review" && <><button className="text-link" disabled={action.busy} onClick={() => setConfirmation({ path: `admin/loans/${row.id}/review`, body: { decision: "approved" }, title: "Aprovar a solicitação simulada?", description: "Revise a análise completa nos detalhes. Esta decisão é apenas demonstrativa: não contrata crédito nem libera saldo." })}>Aprovar simulação</button><button className="text-link" disabled={action.busy} onClick={() => setConfirmation({ path: `admin/loans/${row.id}/review`, body: { decision: "rejected" }, title: "Rejeitar a solicitação simulada?", description: "Informe uma justificativa clara. O cliente poderá consultar a decisão e contestá-la." })}>Rejeitar</button></>}
      <details style={{ textAlign: "left", width: "100%" }}><summary style={{ cursor: "pointer", fontSize: 11, color: "var(--teal)" }}>Ver detalhes</summary><pre className="admin-json">{JSON.stringify(row, null, 2)}</pre></details>
    </div></td></tr>)}</tbody></table></div>}
    <div className="form-actions" style={{ justifyContent: "space-between" }}><small>{pagination?.total_count || 0} registros</small><div style={{ display: "flex", gap: 12, alignItems: "center" }}><button className="button secondary small" disabled={page <= 1 || resource.loading} onClick={() => setPage(value => value - 1)}>Anterior</button><small>Página {page}</small><button className="button secondary small" disabled={resource.loading || page >= (pagination?.total_pages || 1)} onClick={() => setPage(value => value + 1)}>Próxima</button></div></div>
    {confirmation && <Modal title={confirmation.title} onClose={() => { if (!action.busy) setConfirmation(null); }}><p className="muted" style={{ lineHeight: 1.8 }}>{confirmation.description}</p><Feedback error={action.error} /><form className="form-stack" onSubmit={event => { event.preventDefault(); const reason = String(new FormData(event.currentTarget).get("reason") || "").trim(); void action.run(async () => { await api(confirmation.path, { method: "POST", body: { ...confirmation.body, reason } }); setConfirmation(null); resource.reload(); onChanged(); }, "Revisão registrada e auditada."); }}><Field label="Justificativa da revisão"><textarea name="reason" minLength={10} maxLength={1000} rows={4} required placeholder="Descreva os critérios e os motivos da decisão." /></Field><div className="form-actions"><button type="button" className="button secondary" disabled={action.busy} onClick={() => setConfirmation(null)}>Voltar</button><button className="button" disabled={action.busy}>{action.busy ? "Registrando…" : "Confirmar decisão"}</button></div></form></Modal>}
  </section>;
}

function RulesView() {
  return <div className="stack"><div className="alert warning">As regras afetam apenas simulações. Informe valores inteiros em centavos e taxas decimais como texto, conforme a configuração existente. Não são permitidas expressões ou código.</div><RuleEditor type="financial_rules" title="Limites financeiros e antifraude" /><RuleEditor type="credit_rules" title="Elegibilidade e taxas fictícias de crédito" /></div>;
}

function RuleEditor({ type, title }: { type: "financial_rules" | "credit_rules"; title: string }) {
  const resource = useResource<Record<string, unknown>>(`admin/${type}`), action = useAction();
  const [text, setText] = useState(""), [pending, setPending] = useState<Record<string, unknown> | null>(null);
  useEffect(() => {
    if (!resource.data) return;
    if (type === "credit_rules") {
      const rule = resource.data.credit_rule as { config?: Record<string, unknown> } | undefined;
      setText(JSON.stringify(rule?.config || {}, null, 2));
    } else {
      const rows = (resource.data.financial_rules || []) as { key: string; value: number }[];
      const values = { ...(resource.data.defaults as Record<string, number> || {}), ...Object.fromEntries(rows.map(row => [row.key, row.value])) };
      setText(JSON.stringify(values, null, 2));
    }
  }, [resource.data, type]);
  function review(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    try {
      const value: unknown = JSON.parse(text);
      if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Informe um objeto JSON válido.");
      setPending(value as Record<string, unknown>); action.setError(null);
    } catch (error) { action.setError(error instanceof Error ? error.message : "Configuração inválida."); }
  }
  return <section className="card"><div className="card-heading"><h2>{title}</h2><span className="tag">Alteração auditável</span></div><Feedback error={resource.error || action.error} success={action.success} />{resource.loading ? <Loading text="Carregando regras…" /> : resource.data && <form onSubmit={review}><Field label="Configuração JSON"><textarea value={text} onChange={event => setText(event.target.value)} rows={12} style={{ fontFamily: "ui-monospace, monospace", fontSize: 12 }} spellCheck={false} required /></Field><div className="form-actions"><button className="button" disabled={action.busy}>Revisar alterações</button><button type="button" className="button secondary" disabled={action.busy} onClick={resource.reload}>Restaurar valores atuais</button></div></form>}
    {pending && <Modal title="Confirmar atualização das regras?" onClose={() => { if (!action.busy) setPending(null); }}><p className="muted" style={{ lineHeight: 1.8 }}>Confira a configuração. O backend validará os campos e limites permitidos. As análises de crédito antigas preservam a versão de regras que originou cada decisão.</p><pre className="admin-json">{JSON.stringify(pending, null, 2)}</pre><Feedback error={action.error} /><div className="form-actions"><button className="button secondary" disabled={action.busy} onClick={() => setPending(null)}>Voltar</button><button className="button" disabled={action.busy} onClick={() => void action.run(async () => { await api(`admin/${type}`, { method: "PATCH", body: { [type === "financial_rules" ? "rules" : "config"]: pending } }); setPending(null); resource.reload(); }, "Regras atualizadas e auditadas.")}>Confirmar atualização</button></div></Modal>}
  </section>;
}

function ExportsView() {
  const action = useAction();
  const [pending, setPending] = useState<URLSearchParams | null>(null);
  return <section className="card"><div className="card-heading"><h2>Relatórios em Excel</h2><Download size={20} color="var(--teal)" /></div><p className="muted" style={{ fontSize: 12, lineHeight: 1.8 }}>Selecione o relatório e o período de criação dos registros. A exportação exige confirmação recente de MFA, contém apenas os campos permitidos e é registrada na auditoria. O limite é de 5.000 linhas por arquivo.</p><Feedback error={action.error} success={action.success} /><form className="form-grid" onSubmit={event => { event.preventDefault(); const form = new FormData(event.currentTarget); const params = new URLSearchParams({ kind: String(form.get("kind")) }); for (const key of ["from", "to"]) { const value = String(form.get(key) || ""); if (value) params.set(key, value); } setPending(params); }}><Select label="Relatório" name="kind" required><option value="accounts">Contas e saldos</option><option value="transactions">Movimentações</option><option value="loans">Empréstimos simulados</option><option value="loan_analyses">Resultados das análises</option><option value="investment_profiles">Perfis de investimento</option><option value="financial_report">Relatório financeiro</option></Select><div /><Field label="Criados a partir de" type="date" name="from" /><Field label="Criados até" type="date" name="to" /><div className="span-2 form-actions"><button className="button" disabled={action.busy}>Revisar exportação <Download size={14} /></button></div></form>
    {pending && <Modal title="Exportar dados administrativos?" onClose={() => { if (!action.busy) setPending(null); }}><p className="muted" style={{ lineHeight: 1.8 }}>O arquivo contém dados cadastrais ou financeiros fictícios. Mantenha-o em um local privado e siga a política de retenção. Senhas, tokens e segredos de MFA não são exportados.</p><dl className="detail-list"><div><dt>Relatório</dt><dd>{pending.get("kind")}</dd></div><div><dt>Período</dt><dd>{pending.get("from") || "Início"} a {pending.get("to") || "Hoje"}</dd></div></dl><Feedback error={action.error} /><div className="form-actions"><button className="button secondary" disabled={action.busy} onClick={() => setPending(null)}>Voltar</button><button className="button" disabled={action.busy} onClick={() => void action.run(async () => { await downloadReport(`admin/exports.xlsx?${pending.toString()}`); setPending(null); }, "Relatório exportado. A ação foi registrada.")}>{action.busy ? "Gerando…" : "Confirmar exportação"}</button></div></Modal>}
  </section>;
}
