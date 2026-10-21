import React, { useEffect, useState } from "react";
import { AppState, Linking, Switch, Text } from "react-native";
import { api } from "../lib/native-api";
import { useAuth } from "../contexts/AuthContext";
import { editableCents, formatCents, parseCents, positiveCents } from "../lib/money";
import { Button, Card, Feedback, Field, Heading, Label, Notice, Page, Row, confirm, useTask } from "../components/ui";

export function ProfileScreen({ navigation }: any) {
  const auth = useAuth(); const task = useTask(); const user = auth.user;
  const [name, setName] = useState(user?.full_name ?? ""); const [phone, setPhone] = useState(user?.phone ?? ""); const [profession, setProfession] = useState(user?.profession ?? ""); const [salary, setSalary] = useState(editableCents(user?.monthly_salary_cents ?? 0)); const [expenses, setExpenses] = useState(editableCents(user?.monthly_expenses_cents ?? 0)); const [other, setOther] = useState(editableCents(user?.other_income_cents ?? 0)); const [debts, setDebts] = useState(editableCents(user?.existing_debts_cents ?? 0)); const [address, setAddress] = useState(user?.address ?? { street: "", number: "", city: "", state: "", postal_code: "" });
  return <Page title="Seu espaço" subtitle="Mantenha seu cadastro e suas preferências em dia."><Card><Row label="E-mail" value={user?.email} /><Row label="CPF" value={user?.cpf} /><Row label="Situação" value={user?.status} /><Field label="Nome completo" value={name} onChangeText={setName} /><Field label="Telefone E.164" value={phone} onChangeText={setPhone} keyboardType="phone-pad" /><Field label="Profissão" value={profession} onChangeText={setProfession} /><Field label="Salário mensal (R$)" value={salary} onChangeText={setSalary} keyboardType="decimal-pad" /><Field label="Outras rendas (R$)" value={other} onChangeText={setOther} keyboardType="decimal-pad" /><Field label="Despesas mensais (R$)" value={expenses} onChangeText={setExpenses} keyboardType="decimal-pad" /><Field label="Saldo das dívidas (R$)" value={debts} onChangeText={setDebts} keyboardType="decimal-pad" />{([['street', 'Rua'], ['number', 'Número'], ['city', 'Cidade'], ['state', 'UF'], ['postal_code', 'CEP']] as const).map(([key, label]) => <Field key={key} label={label} value={address[key]} onChangeText={value => setAddress(current => ({ ...current, [key]: key === "state" ? value.toUpperCase() : value }))} />)}<Feedback task={task} /><Button title="Salvar meus dados" loading={task.busy} onPress={() => void task.run(async () => { await api.request("/me", { method: "PATCH", body: { user: { full_name: name, phone, profession, address, monthly_salary_cents: parseCents(salary), other_income_cents: parseCents(other), monthly_expenses_cents: parseCents(expenses), existing_debts_cents: parseCents(debts) } } }); await auth.reloadUser(); task.setMessage("Cadastro atualizado."); })} /></Card><Card><Button title="Minha conta bancária" secondary onPress={() => navigation.navigate("Account")} /><Button title="Segurança e sessões" secondary onPress={() => navigation.navigate("Security")} /><Button title="Notificações" secondary onPress={() => navigation.navigate("Notifications")} /><Button title="Objetivos financeiros" secondary onPress={() => navigation.navigate("Goals")} /><Button title="Sair com segurança" secondary onPress={() => void task.run(auth.logout)} /><Button title="Desativar meu cadastro" destructive onPress={() => confirm("Desativar seu cadastro?", "Seu acesso e sessões serão revogados. Uma conta com saldo ou movimentações pendentes deve ser tratada antes da desativação.", () => void task.run(async () => { await api.request("/me", { method: "DELETE" }); await auth.logout(); }), true)} /></Card></Page>;
}

export function SecurityScreen() {
  const auth = useAuth(); const task = useTask(); const [security, setSecurity] = useState<any>(null); const [sessions, setSessions] = useState<any[]>([]); const [password, setPassword] = useState(""); const [code, setCode] = useState(""); const [secret, setSecret] = useState(""); const [enrolling, setEnrolling] = useState(false); const [uri, setUri] = useState(""); const [codes, setCodes] = useState<string[]>([]);
  const load = () => void task.run(async () => { const [state, sessionData] = await Promise.all([api.request("/security"), api.request("/sessions")]); setSecurity(state); setSessions(sessionData.sessions); });
  useEffect(load, []);
  useEffect(() => { const subscription = AppState.addEventListener("change", state => { if (state !== "active") { setSecret(""); setUri(""); setCodes([]); setPassword(""); setCode(""); } }); return () => subscription.remove(); }, []);
  return <Page title="Sua segurança" subtitle="Controle o acesso à sua conta."><Feedback task={task} /><Card><Heading>Desbloqueio no dispositivo</Heading><Label>A biometria protege a abertura local do app. O MFA continua sendo validado pelo servidor.</Label><Switch accessibilityLabel="Desbloqueio biométrico" value={auth.biometricEnabled} onValueChange={enabled => void task.run(async () => auth.setBiometricEnabled(enabled))} /><Notice>Face ID exige um build próprio em iOS. O Expo Go não oferece todos os recursos biométricos.</Notice></Card><Card><Heading>Autenticador de dois fatores</Heading><Row label="MFA" value={security?.mfa_enabled ? "Ativado" : "Desativado"} /><Row label="Códigos de recuperação restantes" value={security?.recovery_codes_remaining ?? "—"} /><Field label="Senha atual (para configurar)" value={password} onChangeText={setPassword} secureTextEntry />{!security?.mfa_enabled ? <Button title="Preparar autenticador" secondary loading={task.busy} onPress={() => void task.run(async () => { const result = await api.request("/security/mfa/enrollment", { method: "POST", body: { password } }); setSecret(result.secret); setUri(result.provisioning_uri); setEnrolling(true); setPassword(""); })} /> : null}{secret ? <><Notice>Cadastre este segredo no seu autenticador. Ele não será salvo pelo app.</Notice><Text selectable style={{ color: "#087E77", fontSize: 18 }}>{secret}</Text><Button title="Abrir autenticador compatível" secondary onPress={() => void task.run(async () => { if (!uri.startsWith("otpauth://totp/")) throw new Error("Endereço de autenticador inválido."); await Linking.openURL(uri); })} /></> : null}<Field label="Código de 6 dígitos" value={code} onChangeText={setCode} keyboardType="number-pad" maxLength={6} />{!security?.mfa_enabled && enrolling ? <Button title="Confirmar e ativar MFA" loading={task.busy} onPress={() => void task.run(async () => { const result = await api.request("/security/mfa/enable", { method: "POST", body: { code } }); setCodes(result.recovery_codes); setEnrolling(false); setSecret(""); setUri(""); setCode(""); load(); })} /> : null}{security?.mfa_enabled ? <><Button title="Confirmar operação de alto risco" secondary loading={task.busy} onPress={() => void task.run(async () => { await api.request("/security/mfa/verify", { method: "POST", body: { code } }); setCode(""); task.setMessage("Confirmação adicional válida por 5 minutos."); })} /><Button title="Desativar MFA" destructive onPress={() => confirm("Desativar MFA?", "Essa ação revoga todas as sessões. Contas administrativas precisam manter o MFA.", () => void task.run(async () => { await api.request("/security/mfa", { method: "DELETE", body: { password, code } }); await auth.logout(); }), true)} /></> : null}{codes.length ? <><Notice>Guarde estes códigos em um local seguro. Cada código só pode ser usado uma vez e esta lista só aparece agora.</Notice>{codes.map(item => <Text selectable key={item} style={{ color: "#087E77", fontFamily: "monospace" }}>{item}</Text>)}<Button title="Já guardei: ocultar códigos" secondary onPress={() => setCodes([])} /></> : null}</Card><Heading>Sessões ativas</Heading>{sessions.map(session => <Card key={session.id}><Row label="Sessão" value={session.current ? "Este dispositivo" : session.id.slice(0, 8)} /><Row label="Criada em" value={new Date(session.created_at).toLocaleString("pt-BR")} /><Row label="Expira em" value={new Date(session.expires_at).toLocaleString("pt-BR")} /><Button title="Revogar sessão" secondary onPress={() => confirm("Revogar sessão?", "O acesso desta sessão será encerrado.", () => void task.run(async () => { await api.request(`/sessions/${session.id}`, { method: "DELETE" }); if (session.current) await auth.logout(); else load(); }))} /></Card>)}</Page>;
}

export function NotificationsScreen() {
  const task = useTask(); const [items, setItems] = useState<any[]>([]);
  const load = () => void task.run(async () => setItems((await api.request("/notifications")).notifications));
  useEffect(load, []);
  return <Page title="Notificações" onRefresh={load} refreshing={task.busy}><Feedback task={task} />{items.length ? items.map(item => <Card key={item.id}><Heading>{item.title}</Heading><Label>{item.body}</Label><Label muted>{new Date(item.created_at).toLocaleString("pt-BR")}</Label>{!item.read_at ? <Button title="Marcar como lida" secondary onPress={() => void task.run(async () => { await api.request(`/notifications/${item.id}/read`, { method: "PATCH", body: {} }); load(); })} /> : null}</Card>) : <Notice>Você está em dia. Não há notificações.</Notice>}</Page>;
}

export function GoalsScreen() {
  const task = useTask();
  const [items, setItems] = useState<any[]>([]);
  const [editing, setEditing] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [amount, setAmount] = useState("");
  const [targetDate, setTargetDate] = useState("");
  const load = () => void task.run(async () => setItems((await api.request("/financial_goals")).financial_goals));
  useEffect(load, []);
  const clear = () => { setEditing(null); setName(""); setAmount(""); setTargetDate(""); };
  const save = () => void task.run(async () => {
    await api.request(editing ? `/financial_goals/${editing}` : "/financial_goals", {
      method: editing ? "PATCH" : "POST",
      body: { financial_goal: { name, target_cents: positiveCents(amount), target_date: targetDate } }
    });
    clear(); load();
  });
  return <Page title="Seus objetivos">
    <Card>
      <Heading>{editing ? "Editar objetivo" : "Criar objetivo"}</Heading>
      <Field label="Objetivo" value={name} onChangeText={setName} maxLength={120} />
      <Field label="Valor desejado (R$)" value={amount} onChangeText={setAmount} keyboardType="decimal-pad" />
      <Field label="Data alvo (AAAA-MM-DD)" value={targetDate} onChangeText={setTargetDate} />
      <Feedback task={task} />
      <Button title={editing ? "Salvar alterações" : "Criar objetivo"} loading={task.busy} onPress={save} />
      {editing ? <Button title="Cancelar edição" secondary onPress={clear} /> : null}
    </Card>
    {items.map(item => <Card key={item.id}>
      <Heading>{item.name}</Heading>
      <Row label="Meta" value={formatCents(item.target_cents)} />
      <Row label="Data alvo" value={item.target_date} />
      <Row label="Situação" value={({ active: "Em andamento", completed: "Concluído", cancelled: "Cancelado" } as Record<string, string>)[item.status] ?? item.status} />
      <Button title="Editar objetivo" secondary onPress={() => { setEditing(item.id); setName(item.name); setAmount(editableCents(item.target_cents)); setTargetDate(item.target_date); }} />
      <Button title={item.status === "completed" ? "Reabrir objetivo" : "Marcar como concluído"} secondary onPress={() => void task.run(async () => { await api.request(`/financial_goals/${item.id}`, { method: "PATCH", body: { financial_goal: { status: item.status === "completed" ? "active" : "completed" } } }); load(); })} />
      <Button title="Excluir objetivo" destructive onPress={() => confirm("Excluir objetivo?", "Essa ação remove o objetivo, sem movimentar seu saldo.", () => void task.run(async () => { await api.request(`/financial_goals/${item.id}`, { method: "DELETE" }); if (editing === item.id) clear(); load(); }), true)} />
    </Card>)}
  </Page>;
}
