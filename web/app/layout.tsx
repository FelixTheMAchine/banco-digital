import type { Metadata, Viewport } from "next";
import "./globals.css";
export const metadata: Metadata = { title: "Aurora — Seu dinheiro, com clareza", description: "Banco digital educativo com dinheiro fictício. Planeje, simule e conheça sua vida financeira.", robots: { index: false, follow: false } };
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#113d37" };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="pt-BR" suppressHydrationWarning><body>{children}</body></html>;
}
