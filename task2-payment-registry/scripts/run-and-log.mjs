#!/usr/bin/env node
/**
 * Прогоняет все тестовые этапы, сохраняет полный вывод в reports/<stage>.log
 * и формирует reports/TEST_SUMMARY.md (этап, команда, exit code, passed/failed,
 * покрытие OWASP Smart Contract Top 10 (2025) по тегам из комментариев тестов).
 *   node scripts/run-and-log.mjs
 */
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const REPORTS = path.join(ROOT, "reports");
mkdirSync(REPORTS, { recursive: true });

const STAGES = [
  { name: "compile", cmd: "npx hardhat compile" },
  { name: "unit", cmd: "npx hardhat test solidity test/solidity/PaymentOrderRegistry.unit.t.sol" },
  { name: "fuzz", cmd: "npx hardhat test solidity test/solidity/PaymentOrderRegistry.fuzz.t.sol" },
  {
    name: "invariant",
    cmd: "npx hardhat test solidity test/solidity/invariant/PaymentOrderRegistry.invariant.t.sol test/solidity/invariant/PaymentOrderHandler.sol",
  },
  { name: "integration", cmd: "npx hardhat test nodejs" },
];

const OWASP_TITLES = {
  SC01: "Access Control Vulnerabilities",
  SC02: "Price Oracle Manipulation",
  SC03: "Logic Errors",
  SC04: "Lack of Input Validation",
  SC05: "Reentrancy Attacks",
  SC06: "Unchecked External Calls",
  SC07: "Flash Loan Attacks",
  SC08: "Integer Overflow and Underflow",
  SC09: "Insecure Randomness",
  SC10: "Denial of Service (DoS) Attacks",
};
const NOT_APPLICABLE = {
  SC02: "нет оракулов и цен; доверие к off-chain данным ограничено ролью и verifyDocument",
  SC05: "нет внешних вызовов и переводов ETH, CEI; подтверждается Slither в Задании 3",
  SC06: "нет call/delegatecall/send/transfer; подтверждается Slither в Задании 3",
  SC07: "нет балансов/ликвидности; запись требует роли",
  SC09: "соль paymentId — CSPRNG off-chain (scripts/interact.ts, webcrypto.getRandomValues)",
};

const stripAnsi = (s) => s.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");

function run(stage) {
  return new Promise((resolve) => {
    console.log(`\n=== [${stage.name}] ${stage.cmd}\n`);
    const child = spawn(stage.cmd, {
      cwd: ROOT,
      shell: true,
      env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    });
    let out = "";
    child.stdout.on("data", (d) => {
      process.stdout.write(d);
      out += d.toString();
    });
    child.stderr.on("data", (d) => {
      process.stderr.write(d);
      out += d.toString();
    });
    child.on("close", (code) => resolve({ code: code ?? 1, out: stripAnsi(out) }));
  });
}

function parseResults(out) {
  const passing = Number(out.match(/(\d+) passing/)?.[1] ?? 0);
  const failing = Number(out.match(/(\d+) failing/)?.[1] ?? 0);
  const passed = new Set();
  const failed = new Set();
  // Solidity: "testFuzz_X(bytes32,uint128) (runs: 256)" -> "testFuzz_X"; node:test: "<title> (93ms)" -> "<title>"
  const testName = (s) => s.match(/^(\w+)\(/)?.[1] ?? s.replace(/\s+\(\d+(?:\.\d+)?m?s\)$/, "").trim();
  for (const line of out.split(/\r?\n/)) {
    const ok = line.match(/^\s*(?:✔|√)\s+(.+?)\s*$/);
    if (ok) passed.add(testName(ok[1]));
    const bad = line.match(/^\s{2,}\d+\)\s+(.+?)\s*$/);
    if (bad && !bad[1].includes("#")) failed.add(testName(bad[1]));
  }
  return { passing, failing, passed, failed };
}

function walk(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = path.join(dir, f);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}

/** Тег OWASP из комментария над тестом: Solidity `/// ... OWASP SC01:2025` + function, TS `// OWASP ...` + it("..."). */
function collectOwaspTags() {
  const tags = new Map(); // testName -> Set(SCxx)
  for (const file of walk(path.join(ROOT, "test"))) {
    const lines = readFileSync(file, "utf8").split(/\r?\n/);
    let pending = null;
    for (const line of lines) {
      if (/OWASP/.test(line) && /^\s*\/\//.test(line)) {
        pending = [...line.matchAll(/SC(\d{2}):2025/g)].map((m) => `SC${m[1]}`);
        continue;
      }
      const fn = line.match(/function\s+((?:test|invariant)\w*)\s*\(/) ?? line.match(/\bit\(\s*"([^"]+)"/);
      if (fn && pending) {
        tags.set(fn[1], new Set(pending));
        pending = null;
      } else if (line.trim() !== "" && !/^\s*(\/\/|\*)/.test(line)) {
        pending = null;
      }
    }
  }
  return tags;
}

const results = [];
for (const stage of STAGES) {
  const { code, out } = await run(stage);
  writeFileSync(path.join(REPORTS, `${stage.name}.log`), `$ ${stage.cmd}\n\n${out}\nexit code: ${code}\n`);
  results.push({ ...stage, code, ...parseResults(out) });
}

const tags = collectOwaspTags();
const allPassed = new Set(results.flatMap((r) => [...r.passed]));
const allFailed = new Set(results.flatMap((r) => [...r.failed]));

let md = `# TEST SUMMARY — PaymentOrderRegistry (Задание 2)\n\n`;
md += `Сгенерировано: ${new Date().toISOString()} · Node ${process.version} · \`node scripts/run-and-log.mjs\`\n\n`;
md += `## Этапы\n\n| Этап | Команда | Exit code | Passed | Failed | Лог |\n|---|---|---|---|---|---|\n`;
for (const r of results) {
  md += `| ${r.name} | \`${r.cmd}\` | ${r.code} | ${r.name === "compile" ? "—" : r.passing} | ${r.name === "compile" ? "—" : r.failing} | [${r.name}.log](./${r.name}.log) |\n`;
}
md += `\n## Покрытие OWASP Smart Contract Top 10 (2025)\n\n| Категория | Тесты (по тегам в комментариях) | Passed | Failed |\n|---|---|---|---|\n`;
for (const [code, title] of Object.entries(OWASP_TITLES)) {
  const tests = [...tags.entries()].filter(([, s]) => s.has(code)).map(([n]) => n);
  if (tests.length === 0) {
    md += `| ${code}:2025 ${title} | — не применимо: ${NOT_APPLICABLE[code] ?? "нет тестов"} | — | — |\n`;
    continue;
  }
  const p = tests.filter((t) => allPassed.has(t)).length;
  const f = tests.filter((t) => allFailed.has(t)).length;
  md += `| ${code}:2025 ${title} | ${tests.map((t) => `\`${t}\``).join(", ")} | ${p} | ${f} |\n`;
}
const ok = results.every((r) => r.code === 0);
md += `\n**Итог:** ${ok ? "все этапы успешны ✅" : "есть ошибки ❌"}\n`;
writeFileSync(path.join(REPORTS, "TEST_SUMMARY.md"), md);

console.log("\n" + md);
process.exit(ok ? 0 : 1);
