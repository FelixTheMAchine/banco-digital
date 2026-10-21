"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { Bell, CheckCheck, KeyRound, LockKeyhole, ShieldCheck, Smartphone, UserRound } from "lucide-react";
import { api } from "@/lib/api";
import { cents, date, money, statusLabel, toDecimal } from "@/lib/format";
import type { Notice, User } from "@/lib/types";
import { Heading } from "./banking";
import { Empty, Feedback, Field, Loading, Modal, useAction, useResource } from "./ui";

async function endLocalSession() {
  try { await api("auth/logout", { method: "DELETE", retry: false }); } catch { /* The BFF also clears expired cookies. */ }
  window.location.assign("/login");
}

export function ProfileView({ user, onUpdated }: { user: User; onUpdated?: (user: User) => void }) {
  const action = useAction();
  const [deactivate, setDeactivate] = useState(false);
  const [confirmation, setConfirmation] = useState("");
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    await action.run(async () => {
      const address = Object.fromEntries(["street", "number", "city", "state", "postal_code"].map(key => [key, String(form.get(key) || "").trim()]));
      const result = await api<{ user: User }>("me", { method: "PATCH", body: { user: {
        full_name: String(form.get("full_name") || "").trim(), phone: String(form.get("phone") || "").trim(),
        profession: String(form.get("profession") || "").trim(), address,
        monthly_salary_cents: cents(String(form.get("monthly_salary") || "")),
        other_income_cents: cents(String(form.get("other_income") || "")),
        monthly_expenses_cents: cents(String(form.get("monthly_expenses") || "")),
        existing_debts_cents: cents(String(form.get("existing_debts") || ""))
      } } });
      onUpdated?.(result.user);
    }, "Cadastro atualizado com sucesso.");
  }
  return <>
    <Heading title="Meu perfil" description="Um cadastro atualizado ajuda você a planejar melhor." />
    <Feedback error={action.error} success={action.success} />
    <div className="grid-2">
      <section className="card">
        <div className="profile-summary"><span className="avatar"><UserRound size={27} /></span><div><h2 style={{ marginBottom: 5 }}>{user.full_name}</h2><small>{user.email}</small></div></div>
        <form onSubmit={save} className="form-grid" key={user.id}>
          <Field label="Nome completo" name="full_name" autoComplete="name" defaultValue={user.full_name} required maxLength={150} className="span-2" />
          <Field label="Telefone com DDI" name="phone" type="tel" autoComplete="tel" defaultValue={user.phone} placeholder="+5511999990000" required />
          <Field label="Profissão" name="profession" defaultValue={user.profession} maxLength={120} required />
          <Field label="Rua" name="street" defaultValue={user.address.street} autoComplete="address-line1" required />
          <Field label="Número" name="number" defaultValue={user.address.number} required />
          <Field label="Cidade" name="city" defaultValue={user.address.city} autoComplete="address-level2" required />
          <Field label="Estado (UF)" name="state" defaultValue={user.address.state} maxLength={2} pattern="[A-Z]{2}" autoComplete="address-level1" required />
          <Field label="CEP (somente números)" name="postal_code" defaultValue={user.address.postal_code} pattern="[0-9]{8}" maxLength={8} autoComplete="postal-code" required />
          <div className="span-2 divider" />
          <Field label="Salário mensal (R$)" name="monthly_salary" defaultValue={toDecimal(user.monthly_salary_cents)} inputMode="decimal" required />
          <Field label="Outras rendas (R$)" name="other_income" defaultValue={toDecimal(user.other_income_cents)} inputMode="decimal" required />
          <Field label="Despesas mensais (R$)" name="monthly_expenses" defaultValue={toDecimal(user.monthly_expenses_cents)} inputMode="decimal" required />
          <Field label="Dívidas existentes (R$)" name="existing_debts" defaultValue={toDecimal(user.existing_debts_cents)} inputMode="decimal" hint="Valor total das dívidas, não a prestação mensal." required />
          <div className="span-2 form-actions"><button className="button" disabled={action.busy}>{action.busy ? "Salvando…" : "Salvar alterações"}</button></div>
        </form>
      </section>
      <div className="stack">
        <section className="card"><h2>Seus dados de identificação</h2><dl className="detail-list"><div><dt>CPF de teste</dt><dd>{user.cpf}</dd></div><div><dt>Nascimento</dt><dd>{date(user.birth_date)}</dd></div><div><dt>E-mail</dt><dd>{user.email}</dd></div><div><dt>Status</dt><dd>{statusLabel(user.status)}</dd></div></dl><p className="muted" style={{ fontSize: 11, lineHeight: 1.8, marginTop: 22 }}>CPF, nascimento e e-mail não podem ser alterados pelo formulário desta simulação. Use somente dados fictícios.</p><Link className="text-link" href="/seguranca">Revisar minha segurança <LockKeyhole size={14} /></Link></section>
        <section className="card"><h2>Seu planejamento</h2><dl className="detail-list"><div><dt>Renda declarada</dt><dd>{money(user.monthly_salary_cents + user.other_income_cents)}</dd></div><div><dt>Despesas / renda</dt><dd>{user.income_commitment_percent}%</dd></div></dl><p className="muted" style={{ fontSize: 11, lineHeight: 1.8, marginTop: 18 }}>Este indicador compara despesas com a renda declarada. A análise de crédito considera também dívidas, prazo e outros fatores internos.</p></section>
        <section className="card"><h2>Desativar meu cadastro</h2><p className="muted" style={{ fontSize: 12, lineHeight: 1.8 }}>A desativação encerra suas sessões e impede novas operações. O histórico contábil e a auditoria são preservados.</p><button className="button secondary" onClick={() => { setDeactivate(true); setConfirmation(""); }}>Revisar desativação</button></section>
      </div>
    </div>
    {deactivate && <Modal title="Desativar seu cadastro?" onClose={() => { if (!action.busy) setDeactivate(false); }}><p className="muted" style={{ lineHeight: 1.8 }}>Você perderá o acesso e todas as suas sessões serão revogadas. Isso não apaga o histórico financeiro fictício nem representa uma solicitação de eliminação de dados.</p><Field label="Digite DESATIVAR para confirmar" value={confirmation} onChange={event => setConfirmation(event.target.value)} autoComplete="off" /><Feedback error={action.error} /><div className="form-actions"><button className="button secondary" disabled={action.busy} onClick={() => setDeactivate(false)}>Voltar</button><button className="button danger" disabled={action.busy || confirmation !== "DESATIVAR"} onClick={() => void action.run(async () => { await api("me", { method: "DELETE" }); await endLocalSession(); })}>Confirmar desativação</button></div></Modal>}
  </>;
}

type SecurityStatus = { mfa_enabled: boolean; recovery_codes_remaining: number; mfa_verified_until: string | null; active_sessions: number; role: string };
type Session = { id: string; created_at: string; last_used_at: string | null; expires_at: string; current: boolean };
type SecurityDialog = "enrollment" | "enable" | "step-up" | "disable" | "recovery" | null;

export function SecurityView() {
  const status = useResource<SecurityStatus>("security"), sessions = useResource<{ sessions: Session[] }>("sessions"), action = useAction();
  const [dialog, setDialog] = useState<SecurityDialog>(null);
  const [enrollment, setEnrollment] = useState<{ secret: string; provisioning_uri: string } | null>(null);
  const [codes, setCodes] = useState<string[]>([]);
  const [revoke, setRevoke] = useState<Session | null>(null);
  const router = useRouter();
  const reload = () => { status.reload(); sessions.reload(); };
  const close = () => { if (!action.busy) { setDialog(null); setEnrollment(null); setCodes([]); action.setError(null); } };
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const password = String(data.get("password") || "");
    const code = String(data.get("code") || "").trim();
    const recovery = String(data.get("recovery_code") || "").trim();
    await action.run(async () => {
      if (dialog === "enrollment") {
        const result = await api<{ secret: string; provisioning_uri: string }>("security/mfa/enrollment", { method: "POST", body: { password } });
        setEnrollment(result); setDialog("enable");
      } else if (dialog === "enable") {
        const result = await api<{ recovery_codes: string[] }>("security/mfa/enable", { method: "POST", body: { code } });
        setEnrollment(null); setCodes(result.recovery_codes); setDialog("recovery"); reload();
      } else if (dialog === "step-up") {
        await api("security/mfa/verify", { method: "POST", body: recovery ? { recovery_code: recovery } : { code } });
        setDialog(null); reload(); action.setSuccess("Confirmação adicional válida por cinco minutos.");
      } else if (dialog === "disable") {
        await api("security/mfa", { method: "DELETE", body: { password, ...(recovery ? { recovery_code: recovery } : { code }) } });
        await endLocalSession();
      }
    });
  }
  if (status.loading) return <Loading text="Verificando sua segurança…" />;
  return <>
    <Heading title="Sua segurança" description="Mais controle para proteger cada acesso e cada escolha." />
    <Feedback error={status.error || action.error} success={action.success} />
    <div className="grid-2">
      <section className="card"><div className="card-heading"><h2>Autenticação em duas etapas</h2><ShieldCheck color="var(--teal)" size={23} /></div><div className="switch-line"><div><h3>Aplicativo autenticador</h3><p>Um código temporário além da sua senha.</p></div><span className="pill">{status.data?.mfa_enabled ? "Ativada" : "Não ativada"}</span></div>{status.data?.mfa_enabled ? <><p className="muted" style={{ lineHeight: 1.8, fontSize: 12, marginTop: 18 }}>Códigos de recuperação restantes: <strong>{status.data.recovery_codes_remaining}</strong>. Cada código pode ser usado uma única vez.</p><p className="muted" style={{ fontSize: 12 }}>Confirmação adicional até: {date(status.data.mfa_verified_until)}.</p><div className="form-actions"><button className="button" onClick={() => { action.setError(null); setDialog("step-up"); }}>Confirmar código agora</button>{status.data.role !== "admin" && <button className="button secondary" onClick={() => { action.setError(null); setDialog("disable"); }}>Desativar MFA</button>}</div>{status.data.role === "admin" && <p className="footer-note">A autenticação multifator é obrigatória para administradores.</p>}</> : <><p className="muted" style={{ fontSize: 12, lineHeight: 1.8, marginTop: 18 }}>Ative com um aplicativo compatível com TOTP. Operações de maior valor e a administração exigem uma confirmação recente.</p><button className="button" disabled={!status.data} onClick={() => { action.setError(null); setDialog("enrollment"); }}>Ativar autenticação <KeyRound size={14} /></button></>}</section>
      <section className="card"><h2>Boas práticas para seu acesso</h2><ul className="list-clean"><li>Use uma senha exclusiva e mantenha seu autenticador protegido.</li><li>Guarde os códigos de recuperação fora deste navegador.</li><li>Nunca compartilhe códigos, senhas ou links de recuperação.</li><li>Revogue sessões que você não reconhece.</li></ul><p className="alert warning" style={{ marginTop: 22, marginBottom: 0 }}>O projeto usa apenas dinheiro fictício. A segurança ainda exige auditoria independente antes de qualquer uso de produção.</p></section>
    </div>
    <section className="card" style={{ marginTop: 24 }}><div className="card-heading"><h2>Sessões ativas</h2><Smartphone size={21} color="var(--teal)" /></div><Feedback error={sessions.error} />{sessions.loading ? <Loading text="Carregando sessões…" /> : !sessions.data?.sessions.length ? <Empty>Nenhuma sessão disponível.</Empty> : sessions.data.sessions.map(session => <div className="switch-line" key={session.id}><div><h3>{session.current ? "Esta sessão" : "Outro acesso"} <small style={{ fontWeight: 400 }}>• {session.id.slice(0, 8)}</small></h3><p>Iniciada em {date(session.created_at)}<br />Última atividade: {date(session.last_used_at)}<br />Expira em {date(session.expires_at)}</p></div><button className="button secondary small" disabled={action.busy} onClick={() => setRevoke(session)}>Encerrar</button></div>)}</section>
    {dialog && <Modal title={{ enrollment: "Confirme sua senha", enable: "Configure o autenticador", "step-up": "Confirmação adicional", disable: "Desativar a autenticação?", recovery: "Guarde seus códigos de recuperação" }[dialog]} onClose={close}>
      <Feedback error={action.error} />
      {dialog === "recovery" ? <><p className="muted" style={{ lineHeight: 1.8 }}>Estes códigos são exibidos somente agora. Guarde-os em um local privado. Cada um substitui um código temporário uma única vez.</p><div className="recovery-codes">{codes.map(code => <code key={code}>{code}</code>)}</div><div className="form-actions"><button className="button" onClick={close}>Guardei meus códigos</button></div></> : <form onSubmit={submit} className="form-stack" key={dialog}>
        {dialog === "enable" && enrollment && <><p className="muted" style={{ lineHeight: 1.8 }}>No seu aplicativo autenticador, adicione uma chave de configuração TOTP. Depois informe o código de seis dígitos.</p><Field label="Chave de configuração"><code className="code">{enrollment.secret}</code></Field><details><summary style={{ fontSize: 12, cursor: "pointer" }}>Ver endereço de configuração</summary><p className="code">{enrollment.provisioning_uri}</p></details><p className="muted" style={{ fontSize: 11 }}>A configuração pendente expira em dez minutos. Não compartilhe esta chave.</p></>}
        {(dialog === "enrollment" || dialog === "disable") && <Field label="Senha atual" name="password" type="password" autoComplete="current-password" minLength={12} maxLength={128} required />}
        {dialog === "disable" && <p className="alert warning">Todas as sessões serão encerradas. Uma conta administrativa não pode desativar o segundo fator.</p>}
        {dialog !== "enrollment" && <Field label="Código do autenticador" name="code" autoComplete="one-time-code" inputMode="numeric" pattern="[0-9]{6}" maxLength={6} required={dialog === "enable"} placeholder="000000" />}
        {(dialog === "step-up" || dialog === "disable") && <Field label="Ou código de recuperação" name="recovery_code" autoComplete="off" maxLength={16} pattern="[0-9a-f]{16}" hint="Use apenas um dos campos. O código de recuperação será consumido." />}
        <div className="form-actions"><button className="button secondary" type="button" disabled={action.busy} onClick={close}>Voltar</button><button className={`button${dialog === "disable" ? " danger" : ""}`} disabled={action.busy}>{action.busy ? "Verificando…" : dialog === "enrollment" ? "Continuar" : dialog === "disable" ? "Confirmar desativação" : "Confirmar código"}</button></div>
      </form>}
    </Modal>}
    {revoke && <Modal title="Encerrar esta sessão?" onClose={() => { if (!action.busy) setRevoke(null); }}><Feedback error={action.error} /><p className="muted" style={{ lineHeight: 1.8 }}>{revoke.current ? "Você está encerrando o acesso deste navegador e voltará para o login." : "O acesso selecionado será revogado. Para voltar a entrar, será necessário autenticar novamente."}</p><div className="form-actions"><button className="button secondary" disabled={action.busy} onClick={() => setRevoke(null)}>Voltar</button><button className="button danger" disabled={action.busy} onClick={() => void action.run(async () => { await api(`sessions/${revoke.id}`, { method: "DELETE" }); const current = revoke.current; setRevoke(null); reload(); if (current) { await endLocalSession(); router.replace("/login"); } }, "Sessão encerrada.")}>Confirmar encerramento</button></div></Modal>}
  </>;
}

export function NotificationsView() {
  const resource = useResource<{ notifications: Notice[] }>("notifications"), action = useAction();
  return <><Heading title="Notificações" description="Atualizações importantes sobre sua conta de demonstração." /><Feedback error={resource.error || action.error} /><section className="card">{resource.loading ? <Loading text="Carregando notificações…" /> : !resource.data?.notifications.length ? <Empty>Você está em dia. Novas notificações aparecerão aqui.</Empty> : resource.data.notifications.map(notice => <article className={`notice${notice.read_at ? "" : " unread"}`} key={notice.id}><span className="transaction-icon"><Bell size={18} /></span><div style={{ flex: 1 }}><h3>{notice.title}</h3><p>{notice.body}</p><small>{date(notice.created_at)}</small></div>{!notice.read_at && <button className="icon-button" aria-label={`Marcar como lida: ${notice.title}`} disabled={action.busy} onClick={() => void action.run(async () => { await api(`notifications/${notice.id}/read`, { method: "PATCH", body: {} }); resource.reload(); })}><CheckCheck size={18} /></button>}</article>)}</section></>;
}
