"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { ArrowLeftRight, Bell, CircleUserRound, House, Landmark, LogOut, Moon, ReceiptText, ShieldCheck, Sun, TrendingUp, Wallet, ArrowUpRight } from "lucide-react";
import { api, ApiError } from "@/lib/api";
import type { User } from "@/lib/types";
import { Brand, Feedback, Loading } from "./ui";

type AuroraContext = { user: User; updateUser: (user: User) => void };
const Context = createContext<AuroraContext | null>(null);
export function useAurora() {
  const value = useContext(Context);
  if (!value) throw new Error("Perfil indisponível fora da área autenticada.");
  return value;
}
const links = [
  ["/dashboard", "Visão geral", House], ["/minha-conta", "Minha conta", Wallet],
  ["/transferencias", "Transferências", ArrowLeftRight], ["/extrato", "Extrato", ReceiptText],
  ["/emprestimos", "Empréstimos", Landmark], ["/investimentos", "Investimentos", TrendingUp]
] as const;
export function AppShell({ children }: { children: ReactNode }) {
  const router = useRouter(), pathname = usePathname();
  const [user, setUser] = useState<User | null>(null), [error, setError] = useState<string | null>(null), [busy, setBusy] = useState(false), [dark, setDark] = useState(false), [load, setLoad] = useState(0);
  useEffect(() => {
    let alive = true;
    api<{ user: User }>("me").then(data => { if (alive) { setUser(data.user); setError(null); } }).catch(error => {
      if (!alive) return;
      if (error instanceof ApiError && error.status === 401) router.replace("/login");
      else setError(error instanceof Error ? error.message : "Não foi possível carregar sua conta.");
    });
    return () => { alive = false; };
  }, [router, load]);
  useEffect(() => {
    const theme = localStorage.getItem("aurora_theme");
    const preferred = theme ? theme === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches;
    setDark(preferred); document.documentElement.classList.toggle("dark", preferred);
  }, []);
  function toggleTheme() { setDark(value => { document.documentElement.classList.toggle("dark", !value); localStorage.setItem("aurora_theme", value ? "light" : "dark"); return !value; }); }
  async function logout() {
    if (busy) return;
    setBusy(true);
    try { await api("auth/logout", { method: "DELETE" }); router.replace("/login"); }
    catch (error) { setError(error instanceof Error ? error.message : "Não foi possível sair."); }
    finally { setBusy(false); }
  }
  if (!user) return <main style={{ maxWidth: 600, margin: "15vh auto", padding: 24 }}><Brand/>{error ? <><Feedback error={error}/><button className="button" onClick={() => setLoad(value => value + 1)}>Tentar novamente</button><Link href="/login" className="button secondary" style={{ marginLeft: 12 }}>Voltar para o login</Link></> : <Loading/>}</main>;
  const active = (path: string) => pathname === path || (path !== "/dashboard" && pathname.startsWith(path + "/"));
  const admin = pathname.startsWith("/admin");
  return <Context.Provider value={{ user, updateUser: setUser }}><a href="#conteudo" className="skip-link">Pular para o conteúdo</a><div className="app-shell"><aside className="sidebar"><Link href="/dashboard" aria-label="Aurora, início"><Brand/></Link><p className="nav-label">Sua vida financeira</p><nav aria-label="Navegação principal">{links.map(([path, label, Icon]) => <Link key={path} href={path} className={`nav-item ${active(path) ? "active" : ""}`} aria-current={active(path) ? "page" : undefined}><Icon/>{label}</Link>)}</nav><div className="sidebar-bottom"><Link className={`nav-item ${active("/perfil") ? "active" : ""}`} href="/perfil"><CircleUserRound/>Meu perfil</Link><Link className={`nav-item ${active("/seguranca") ? "active" : ""}`} href="/seguranca"><ShieldCheck/>Segurança</Link>{user.role === "admin" && <Link href="/admin" className={`nav-item ${admin ? "active" : ""}`}><Landmark/>Administração<ArrowUpRight size={13}/></Link>}<button className="nav-item" style={{ width: "100%", background: "transparent", border: 0 }} disabled={busy} onClick={() => void logout()}><LogOut/>{busy ? "Saindo…" : "Sair da conta"}</button><div className="simulation-mark">100% dinheiro fictício</div></div></aside><div className="workspace"><header className="topbar"><span className="topbar-title">{admin ? "Administração · Acesso restrito" : "Clareza para o seu presente. Espaço para o futuro."}</span><div className="topbar-actions"><button className="icon-button" aria-label={dark ? "Ativar modo claro" : "Ativar modo escuro"} onClick={toggleTheme}>{dark ? <Sun size={19}/> : <Moon size={19}/>}</button><Link href="/notificacoes" className="icon-button" aria-label="Notificações"><Bell size={20}/></Link><Link href="/perfil" style={{ display: "flex", gap: 10, alignItems: "center" }}><span className="avatar" aria-hidden="true">{user.full_name.split(" ").map(part => part[0]).slice(0, 2).join("")}</span><span className="user-name" style={{ fontSize: 12 }}>{user.full_name.split(" ")[0]}</span></Link></div></header><main id="conteudo" className="content" tabIndex={-1}>{error && <Feedback error={error}/>}<div className={admin ? "admin-area" : undefined}>{children}</div><p className="footer-note">Aurora • Finanças para aprender, decisões para simular.<br/>Ambiente educativo com dinheiro fictício. Sem serviços financeiros reais.</p></main></div><nav className="mobile-nav" aria-label="Navegação no celular">{[links[0], links[2], links[3], links[5]].map(([path, label, Icon]) => <Link href={path} key={path} className={active(path) ? "active" : ""}><Icon/>{label}</Link>)}<Link href="/perfil" className={active("/perfil") || active("/seguranca") ? "active" : ""}><CircleUserRound/>Perfil</Link></nav></div></Context.Provider>;
}
