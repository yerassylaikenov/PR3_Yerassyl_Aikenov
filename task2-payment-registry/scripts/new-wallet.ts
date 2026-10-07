/**
 * Генерация нового ТЕСТОВОГО кошелька для Sepolia.
 *   npx hardhat run scripts/new-wallet.ts
 * Ключ печатается один раз и нигде не сохраняется.
 */
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

const privateKey = generatePrivateKey();
const account = privateKeyToAccount(privateKey);

console.log("==================================================================");
console.log(" WARNING: TEST WALLET FOR SEPOLIA ONLY. Never use it on mainnet.");
console.log(" Do NOT save the key to files / git / chats. Put it into the");
console.log(" encrypted Hardhat keystore right away, e.g.:");
console.log("   npx hardhat keystore set SEPOLIA_PRIVATE_KEY");
console.log("==================================================================");
console.log(`address    : ${account.address}`);
console.log(`privateKey : ${privateKey}`);
