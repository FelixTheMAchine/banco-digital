import Link from "next/link";
export default function NotFound() { return <main className="content"><div className="card"><h1>Página não encontrada.</h1><p className="muted">Continue pelo início da sua conta.</p><Link className="button" href="/dashboard">Voltar ao início</Link></div></main>; }
