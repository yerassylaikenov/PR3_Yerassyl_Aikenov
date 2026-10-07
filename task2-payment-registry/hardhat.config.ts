import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";

// Secrets (RPC URL, private keys, Etherscan key) are NEVER stored in this repo.
// They are read from the encrypted Hardhat keystore via configVariable(...):
//   npx hardhat keystore set SEPOLIA_RPC_URL
//   npx hardhat keystore set SEPOLIA_PRIVATE_KEY             (admin / deployer)
//   npx hardhat keystore set SEPOLIA_OPERATOR_PRIVATE_KEY    (OPERATOR_ROLE)
//   npx hardhat keystore set SEPOLIA_SETTLEMENT_PRIVATE_KEY  (SETTLEMENT_ROLE)
//   npx hardhat keystore set ETHERSCAN_API_KEY               (optional, for verify)
export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          optimizer: { enabled: true, runs: 200 },
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: { enabled: true, runs: 200 },
        },
      },
    },
  },
  paths: {
    tests: {
      solidity: "./test/solidity",
      nodejs: "./test/nodejs",
    },
  },
  test: {
    solidity: {
      fuzz: {
        runs: 256,
        // fixed seed -> reproducible run during the live demonstration
        seed: "0x5052335f56415249414e545f31",
      },
      invariant: {
        runs: 64,
        depth: 32,
        failOnRevert: false,
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    localhost: {
      type: "http",
      chainType: "l1",
      url: "http://127.0.0.1:8545",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [
        configVariable("SEPOLIA_PRIVATE_KEY"),
        configVariable("SEPOLIA_OPERATOR_PRIVATE_KEY"),
        configVariable("SEPOLIA_SETTLEMENT_PRIVATE_KEY"),
      ],
    },
  },
  verify: {
    etherscan: {
      apiKey: configVariable("ETHERSCAN_API_KEY"),
    },
  },
});
