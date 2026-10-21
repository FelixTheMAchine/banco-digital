import type { Config } from "tailwindcss";
export default { content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"], darkMode: "class", theme: { extend: { colors: { aurora: { navy: "#101f2d", teal: "#117e72", coral: "#ed825e" } } } }, plugins: [] } satisfies Config;
