/**
 * Развёртывание PaymentOrderRegistry.
 *   npx hardhat run scripts/deploy.ts --network localhost
 *   npx hardhat run scripts/deploy.ts --network sepolia
 *
 * wallet[0] = admin / deployer (получает только DEFAULT_ADMIN_ROLE).
 * Результат записывается в deployments/<network>.json (только публичные данные).
 */
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { network } from "hardhat";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DEPLOYMENTS_DIR = path.join(ROOT, "deployments");
const SEPOLIA_CHAIN_ID = 11155111;

async function main() {
  const { viem, networkName } = await network.create();
  const publicClient = await viem.getPublicClient();
  const wallets = await viem.getWalletClients();
  if (wallets.length === 0) {
    throw new Error(`No accounts configured for network "${networkName}".`);
  }
  const admin = wallets[0].account.address;
  const chainId = await publicClient.getChainId();

  console.log("=== Deploy PaymentOrderRegistry ===");
  console.log(`network : ${networkName}`);
  console.log(`chainId : ${chainId}`);
  console.log(`admin   : ${admin}  (deployer, DEFAULT_ADMIN_ROLE only)`);
  console.log(`balance : ${Number(await publicClient.getBalance({ address: admin })) / 1e18} ETH`);

  const { contract, deploymentTransaction } = await viem.sendDeploymentTransaction(
    "PaymentOrderRegistry",
    [admin],
    { client: { wallet: wallets[0] } },
  );
  console.log(`deploy tx sent: ${deploymentTransaction.hash} - waiting for receipt...`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash: deploymentTransaction.hash });
  if (receipt.status !== "success") {
    throw new Error(`Deployment transaction reverted: ${deploymentTransaction.hash}`);
  }

  const result = {
    network: networkName,
    chainId,
    contract: "PaymentOrderRegistry",
    address: contract.address,
    admin,
    deployTxHash: deploymentTransaction.hash,
    blockNumber: Number(receipt.blockNumber),
    gasUsed: receipt.gasUsed.toString(),
    deployedAt: new Date().toISOString(),
    interactions: [] as unknown[],
  };

  await mkdir(DEPLOYMENTS_DIR, { recursive: true });
  const outFile = path.join(DEPLOYMENTS_DIR, `${networkName}.json`);
  await writeFile(outFile, JSON.stringify(result, null, 2) + "\n");

  console.log("");
  console.log(`contract address : ${contract.address}`);
  console.log(`deploy tx hash   : ${deploymentTransaction.hash}`);
  console.log(`block            : ${receipt.blockNumber}`);
  console.log(`gasUsed          : ${receipt.gasUsed}`);
  console.log(`saved to         : deployments/${networkName}.json`);

  if (chainId === SEPOLIA_CHAIN_ID) {
    console.log("");
    console.log(`Etherscan contract : https://sepolia.etherscan.io/address/${contract.address}`);
    console.log(`Etherscan deploy tx: https://sepolia.etherscan.io/tx/${deploymentTransaction.hash}`);
    console.log(`Verify (optional)  : npx hardhat verify --network sepolia ${contract.address} ${admin}`);
  }
  console.log("");
  console.log(`Next: npx hardhat run scripts/interact.ts --network ${networkName}`);
}

main().catch((error: unknown) => {
  console.error("");
  console.error("DEPLOY FAILED:", error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
