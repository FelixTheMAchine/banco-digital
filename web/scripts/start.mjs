import { cpSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const server = resolve(".next/standalone/server.js");
if (!existsSync(server)) {
  console.error("Build indisponível. Execute npm run build antes de iniciar.");
  process.exit(1);
}
cpSync(".next/static", ".next/standalone/.next/static", { recursive: true });
if (existsSync("public")) cpSync("public", ".next/standalone/public", { recursive: true });
process.env.HOSTNAME = process.env.WEB_BIND_HOST || "0.0.0.0";
process.env.PORT ||= "3000";
await import(pathToFileURL(server).href);
