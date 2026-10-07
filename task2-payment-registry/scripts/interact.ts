/**
 * Сценарий взаимодействия с PaymentOrderRegistry (основной поток из архитектуры, Задание 1).
 *   npx hardhat run scripts/interact.ts --network localhost
 *   npx hardhat run scripts/interact.ts --network sepolia
 *
 * Разделение ролей (мера против угрозы T6 — компрометация admin-ключа):
 *   wallet[0] — admin      : только DEFAULT_ADMIN_ROLE (выдаёт роли, не выполняет операции)
 *   wallet[1] — operator   : только OPERATOR_ROLE (банк-отправитель)
 *   wallet[2] — settlement : только SETTLEMENT_ROLE (расчётный центр)
 * Скрипт идемпотентен: повторный запуск не падает (роли не выдаются повторно, paymentId уникален).
 */
import { webcrypto } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { network } from "hardhat";
import {
  BaseError,
  ContractFunctionRevertedError,
  encodeAbiParameters,
  formatEther,
  keccak256,
  parseEther,
  stringToHex,
  toHex,
  type Address,
  type Hash,
} from "viem";

// ---- константы (Sepolia: пополнение газом оператора и расчётного центра с кошелька admin)
const MIN_ROLE_BALANCE = parseEther("0.002");
const TOP_UP_AMOUNT = parseEther("0.003");
const SEPOLIA_CHAIN_ID = 11155111;

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DOC_1 = path.join(ROOT, "demo-data", "payment-order-0001.xml");
const DOC_2 = path.join(ROOT, "demo-data", "payment-order-0002.xml");
const SENDER_BIC = "DEMOKZKA";
const VALUE_DATE = "2026-10-06";
const STATUS_NAMES = ["None", "Registered", "Executed", "Rejected", "Cancelled"] as const;

type Interaction = {
  run: string;
  step: string;
  function: string;
  from: string;
  txHash: Hash;
  block: number;
  status: string;
};

/** paymentId = keccak256(abi.encode(senderBic, operationRef, valueDate, salt)); salt — CSPRNG (OWASP SC09:2025). */
function makePaymentId(operationRef: string): Hash {
  const salt = toHex(webcrypto.getRandomValues(new Uint8Array(32)));
  return keccak256(
    encodeAbiParameters(
      [{ type: "string" }, { type: "string" }, { type: "string" }, { type: "bytes32" }],
      [SENDER_BIC, operationRef, VALUE_DATE, salt],
    ),
  );
}

const ROLE_NAMES: Record<string, string> = {
  [keccak256(stringToHex("OPERATOR_ROLE"))]: "OPERATOR_ROLE",
  [keccak256(stringToHex("SETTLEMENT_ROLE"))]: "SETTLEMENT_ROLE",
  [toHex(0, { size: 32 })]: "DEFAULT_ADMIN_ROLE",
};

function describeRevert(error: unknown): string {
  if (error instanceof BaseError) {
    const reverted = error.walk((e) => e instanceof ContractFunctionRevertedError);
    if (reverted instanceof ContractFunctionRevertedError && reverted.data?.errorName) {
      const args = (reverted.data.args ?? []).map((a) => ROLE_NAMES[String(a)] ?? String(a)).join(", ");
      return `${reverted.data.errorName}(${args})`;
    }
    return error.shortMessage;
  }
  return String(error);
}

async function main() {
  const { viem, networkName } = await network.create();
  const publicClient = await viem.getPublicClient();
  const chainId = await publicClient.getChainId();
  const isSepolia = chainId === SEPOLIA_CHAIN_ID;
  const explorerTx = (h: string) => (isSepolia ? `https://sepolia.etherscan.io/tx/${h}` : "");

  // 1. адрес из deployments/<network>.json
  const deploymentsFile = path.join(ROOT, "deployments", `${networkName}.json`);
  let deployment: { address: Address; interactions?: Interaction[]; [k: string]: unknown };
  try {
    deployment = JSON.parse(await readFile(deploymentsFile, "utf8"));
  } catch {
    throw new Error(
      `File deployments/${networkName}.json not found. Run first: npx hardhat run scripts/deploy.ts --network ${networkName}`,
    );
  }
  const code = await publicClient.getCode({ address: deployment.address });
  if (code === undefined || code === "0x") {
    throw new Error(
      `No contract at ${deployment.address} on "${networkName}" (node restarted?). Re-run: npx hardhat run scripts/deploy.ts --network ${networkName}`,
    );
  }

  // 2. три разных кошелька
  const wallets = await viem.getWalletClients();
  if (wallets.length < 3) {
    throw new Error(`Network "${networkName}" must have 3 accounts (admin, operator, settlement); found ${wallets.length}.`);
  }
  const [adminW, operatorW, settlementW] = wallets;
  const admin = adminW.account.address;
  const operator = operatorW.account.address;
  const settlement = settlementW.account.address;

  const registry = await viem.getContractAt("PaymentOrderRegistry", deployment.address);
  const OPERATOR_ROLE = await registry.read.OPERATOR_ROLE();
  const SETTLEMENT_ROLE = await registry.read.SETTLEMENT_ROLE();

  const runId = new Date().toISOString();
  const interactions: Interaction[] = [];

  console.log("=== PaymentOrderRegistry: interaction scenario ===");
  console.log(`network    : ${networkName} (chainId ${chainId})`);
  console.log(`contract   : ${deployment.address}`);
  console.log(`admin      : ${admin}`);
  console.log(`operator   : ${operator}`);
  console.log(`settlement : ${settlement}`);
  console.log("");

  async function send(step: string, fn: string, from: Address, txPromise: Promise<Hash>) {
    const hash = await txPromise;
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const record: Interaction = {
      run: runId,
      step,
      function: fn,
      from,
      txHash: hash,
      block: Number(receipt.blockNumber),
      status: receipt.status,
    };
    interactions.push(record);
    console.log(`[${step}] ${fn}`);
    console.log(`      from ${from}`);
    console.log(`      tx ${hash} | block ${receipt.blockNumber} | ${receipt.status}`);
    if (isSepolia) console.log(`      ${explorerTx(hash)}`);
    if (receipt.status !== "success") throw new Error(`Transaction ${hash} reverted`);
    return receipt;
  }

  // 3. выдача ролей (пропуск, если роль уже есть)
  if (await registry.read.hasRole([OPERATOR_ROLE, operator])) {
    console.log("[3a] grantRole(OPERATOR_ROLE) — skipped, operator already has the role");
  } else {
    await send("3a", "grantRole(OPERATOR_ROLE, operator)", admin,
      registry.write.grantRole([OPERATOR_ROLE, operator], { account: admin }));
  }
  if (await registry.read.hasRole([SETTLEMENT_ROLE, settlement])) {
    console.log("[3b] grantRole(SETTLEMENT_ROLE) — skipped, settlement already has the role");
  } else {
    await send("3b", "grantRole(SETTLEMENT_ROLE, settlement)", admin,
      registry.write.grantRole([SETTLEMENT_ROLE, settlement], { account: admin }));
  }

  // 4. Sepolia: газ оператору и расчётному центру с кошелька admin
  if (isSepolia) {
    for (const [label, addr] of [["operator", operator], ["settlement", settlement]] as const) {
      const bal = await publicClient.getBalance({ address: addr });
      if (bal < MIN_ROLE_BALANCE) {
        console.log(`[4] ${label} balance ${formatEther(bal)} ETH < ${formatEther(MIN_ROLE_BALANCE)} — top-up ${formatEther(TOP_UP_AMOUNT)} ETH`);
        await send("4", `top-up ${label} (${formatEther(TOP_UP_AMOUNT)} ETH)`, admin,
          adminW.sendTransaction({ to: addr, value: TOP_UP_AMOUNT }));
      } else {
        console.log(`[4] ${label} balance ${formatEther(bal)} ETH — top-up not needed`);
      }
    }
  }

  // 5. docHash и paymentId (off-chain)
  const doc1 = await readFile(DOC_1);
  const doc2 = await readFile(DOC_2);
  const docHash1 = keccak256(doc1);
  const docHash2 = keccak256(doc2);
  const opBase = `OP-${Date.now()}`;
  const id1 = makePaymentId(`${opBase}-1`);
  const id2 = makePaymentId(`${opBase}-2`);
  console.log("");
  console.log(`[5] docHash1 = keccak256(payment-order-0001.xml) = ${docHash1}`);
  console.log(`    docHash2 = keccak256(payment-order-0002.xml) = ${docHash2}`);
  console.log(`    paymentId1 = ${id1}`);
  console.log(`    paymentId2 = ${id2}`);
  console.log("");

  // 6. register -> markExecuted
  await send("6a", "registerPayment(id1, docHash1, 12500000000)", operator,
    registry.write.registerPayment([id1, docHash1, 12_500_000_000n], { account: operator }));
  await send("6b", "markExecuted(id1)", settlement,
    registry.write.markExecuted([id1], { account: settlement }));

  // 7. register -> markRejected("AC04")
  await send("7a", "registerPayment(id2, docHash2, 475000000)", operator,
    registry.write.registerPayment([id2, docHash2, 475_000_000n], { account: operator }));
  await send("7b", 'markRejected(id2, "AC04")', settlement,
    registry.write.markRejected([id2, stringToHex("AC04", { size: 32 })], { account: settlement }));

  const p1 = await registry.read.getPayment([id1]);
  const p2 = await registry.read.getPayment([id2]);
  console.log("");
  console.log(`    id1 status = ${STATUS_NAMES[p1.status]}, settledBy = ${p1.settledBy}`);
  console.log(`    id2 status = ${STATUS_NAMES[p2.status]}, settledBy = ${p2.settledBy}`);

  // 8. проверка документа (view, без транзакции)
  const tampered = Buffer.from(doc1.toString("utf8").replace("125000000.00", "925000000.00"), "utf8");
  const okOriginal = await registry.read.verifyDocument([id1, docHash1]);
  const okTampered = await registry.read.verifyDocument([id1, keccak256(tampered)]);
  console.log("");
  console.log(`[8] verifyDocument(id1, original)  = ${okOriginal}   (expected true)`);
  console.log(`    verifyDocument(id1, tampered)  = ${okTampered}  (expected false)`);
  if (okOriginal !== true || okTampered !== false) throw new Error("verifyDocument returned unexpected result");

  // 9. ожидаемые отказы — только симуляция (eth_call), транзакции не отправляются
  console.log("");
  console.log("[9] Access-control checks (simulation only, no tx sent):");
  const checks: Array<[string, () => Promise<unknown>]> = [
    ["markExecuted(id1) from operator (no SETTLEMENT_ROLE)", () =>
      publicClient.simulateContract({ address: registry.address, abi: registry.abi, functionName: "markExecuted", args: [id1], account: operator })],
    ["registerPayment(...) from admin (no OPERATOR_ROLE)", () =>
      publicClient.simulateContract({ address: registry.address, abi: registry.abi, functionName: "registerPayment", args: [makePaymentId(`${opBase}-3`), docHash1, 1n], account: admin })],
  ];
  for (const [label, run] of checks) {
    try {
      await run();
      throw new Error(`UNEXPECTED SUCCESS: ${label}`);
    } catch (error) {
      if (error instanceof Error && error.message.startsWith("UNEXPECTED SUCCESS")) throw error;
      console.log(`    ${label} -> reverted: ${describeRevert(error)}`);
    }
  }

  // проверка разделения ролей
  const adminHasOp = await registry.read.hasRole([OPERATOR_ROLE, admin]);
  const adminHasSt = await registry.read.hasRole([SETTLEMENT_ROLE, admin]);
  console.log("");
  console.log(`Role separation: admin has OPERATOR_ROLE = ${adminHasOp}, SETTLEMENT_ROLE = ${adminHasSt} (expected false/false)`);
  console.log(`totalRegistered = ${await registry.read.totalRegistered()}`);

  // 10. сохранить хеши и вывести markdown-таблицу
  deployment.interactions = [...(deployment.interactions ?? []), ...interactions];
  await writeFile(deploymentsFile, JSON.stringify(deployment, null, 2) + "\n");

  console.log("");
  console.log(`Saved ${interactions.length} interaction tx hashes to deployments/${networkName}.json`);
  console.log("");
  console.log("| Step | Function | From | Tx hash | Block | Status |");
  console.log("|---|---|---|---|---|---|");
  for (const i of interactions) {
    const hashCell = isSepolia ? `[${i.txHash}](${explorerTx(i.txHash)})` : `\`${i.txHash}\``;
    console.log(`| ${i.step} | \`${i.function}\` | \`${i.from}\` | ${hashCell} | ${i.block} | ${i.status} |`);
  }
  console.log("");
  console.log("INTERACTION SCENARIO COMPLETED SUCCESSFULLY");
}

main().catch((error: unknown) => {
  console.error("");
  console.error("INTERACT FAILED:", error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
