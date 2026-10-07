#!/usr/bin/env node
/**
 * Проверка репозитория на утечку секретов (отслеживаемые git файлы + новые неигнорируемые).
 * Ищет: файлы .env*, присваивания приватных ключей (PRIVATE_KEY = "0x<64 hex>"), мнемоники.
 * При находке — exit 1.
 *   node scripts/check-secrets.mjs
 */
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

let files;
try {
  files = execSync("git ls-files --cached --others --exclude-standard", { cwd: ROOT, encoding: "utf8" })
    .split(/\r?\n/)
    .filter(Boolean);
} catch {
  console.error("check-secrets: this folder is not inside a git repository (run `git init` first).");
  process.exit(1);
}

const RULES = [
  { name: "private key assignment", re: /(PRIVATE_KEY|privateKey|private_key|PK)\s*[:=]\s*["'`]?(0x)?[0-9a-fA-F]{64}\b/ },
  { name: "raw 0x-prefixed 32-byte key in .env style", re: /^\s*[A-Z_]*KEY[A-Z_]*\s*=\s*(0x)?[0-9a-fA-F]{64}\s*$/m },
  { name: "mnemonic", re: /\b(mnemonic|seed phrase)\b\s*[:=]\s*["'`][a-z]+(\s+[a-z]+){11,23}["'`]/i },
  { name: "RPC URL with API key", re: /https:\/\/[a-z0-9.-]*(infura\.io|alchemy\.com|quiknode\.pro)\/(v\d\/)?[A-Za-z0-9_-]{20,}/ },
];
const SKIP_EXT = new Set([".png", ".jpg", ".jpeg", ".pdf", ".ico", ".lock"]);

const findings = [];
for (const rel of files) {
  const base = path.basename(rel);
  if (/^\.env(\..*)?$/.test(base) && base !== ".env.example") {
    findings.push(`${rel}: .env file must not be committed`);
    continue;
  }
  if (SKIP_EXT.has(path.extname(rel).toLowerCase()) || rel.endsWith("package-lock.json")) continue;
  let text;
  try {
    text = readFileSync(path.join(ROOT, rel), "utf8");
  } catch {
    continue;
  }
  for (const rule of RULES) {
    if (rule.re.test(text)) findings.push(`${rel}: ${rule.name}`);
  }
}

console.log(`check-secrets: scanned ${files.length} files`);
if (findings.length > 0) {
  console.error("SECRETS FOUND:");
  for (const f of findings) console.error("  - " + f);
  process.exit(1);
}
console.log("OK — no secrets, .env files or mnemonics found");
