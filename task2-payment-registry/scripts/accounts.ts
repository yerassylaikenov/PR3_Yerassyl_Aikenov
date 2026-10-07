/**
 * Показывает адреса и балансы кошельков сети (транзакции не отправляет).
 *   npx hardhat run scripts/accounts.ts --network sepolia
 * wallet[0] = admin (его пополнять через faucet), wallet[1] = operator, wallet[2] = settlement.
 */
import { network } from "hardhat";
import { formatEther } from "viem";

const LABELS = ["admin (SEPOLIA_PRIVATE_KEY)", "operator (SEPOLIA_OPERATOR_PRIVATE_KEY)", "settlement (SEPOLIA_SETTLEMENT_PRIVATE_KEY)"];

async function main() {
  const { viem, networkName } = await network.create();
  const publicClient = await viem.getPublicClient();
  const chainId = await publicClient.getChainId();
  const wallets = await viem.getWalletClients();

  console.log(`network: ${networkName} (chainId ${chainId})`);
  const seen = new Set<string>();
  for (const [i, w] of wallets.slice(0, 3).entries()) {
    const addr = w.account.address;
    const bal = await publicClient.getBalance({ address: addr });
    console.log(`[${i}] ${LABELS[i] ?? "account"}: ${addr}  balance ${formatEther(bal)} ETH`);
    if (seen.has(addr.toLowerCase())) console.log("    WARNING: same address as another role — use 3 DIFFERENT keys");
    seen.add(addr.toLowerCase());
  }
  if (wallets.length < 3) console.log(`WARNING: only ${wallets.length} account(s) configured, 3 required`);
}

main().catch((error: unknown) => {
  console.error("ACCOUNTS FAILED:", error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
