require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require('hardhat-deploy');
require("hardhat-gas-reporter");
require("hardhat-abi-exporter");
require("solidity-coverage");
require('dotenv').config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// REQUIRED TO ENSURE METADATA IS SAVED IN DEPLOYMENTS (because solidity-coverage disable it otherwise)
const { TASK_COMPILE_GET_COMPILER_INPUT, TASK_COMPILE_SOLIDITY_COMPILE } = require("hardhat/builtin-tasks/task-names");
task(TASK_COMPILE_GET_COMPILER_INPUT).setAction(async (_, bre, runSuper) => {
  const input = await runSuper();
  input.settings.metadata.useLiteralContent = bre.network.name !== "coverage";
  return input;
});

const alchemyKey = process.env.ALCHEMY_KEY || "";

function nodeUrl(network) {
  return `https://${network}.g.alchemy.com/v2/${alchemyKey}`;
}

let privateKey = process.env.PK || "";
const accounts = privateKey
  ? [
    privateKey,
    ]
  : undefined;

module.exports = {
  defaultNetwork: "hardhat",
  gasReporter: {
    showTimeSpent: true,
    currency: "USD",
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      // forking: {
      //   url: `https://eth-mainnet.g.alchemy.com/v2/7Hn_ZNe9DF0-yWWywXinW0rAjQzcuPsP`,
      //   blockNumber: 15365590,
      // },
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        }
      },
    },
    local: {
      url: 'http://localhost:8545',
    },
    coverage: {
      url: "http://127.0.0.1:8555",
    },
    mainnet: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      accounts: accounts,
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      accounts: accounts,
      allowUnlimitedContractSize: true
    },
  },
  solidity: {
    version: "0.8.11",
    settings: {
      optimizer: {
        enabled: true,
        runs: 800,
      },
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    coverage: "./coverage",
    coverageJson: "./coverage.json",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 50000,
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};
