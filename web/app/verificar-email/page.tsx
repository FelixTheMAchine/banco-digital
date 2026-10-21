import { Suspense } from "react";
import { AuthScreen } from "@/components/auth-screen";
export default function Page(){return <Suspense fallback={<main className="loading">Carregando…</main>}><AuthScreen mode="verify"/></Suspense>}
