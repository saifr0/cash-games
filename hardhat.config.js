require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.31",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000,
          },
          evmVersion: "cancun",
        },
      },
    ],
  },

  networks: {
    hardhat: {
      // Set FORK_ARB=true in .env to fork Arbitrum mainnet locally.
      ...(process.env.FORK_ARB === "true" && process.env.URL_ARB
        ? { forking: { url: process.env.URL_ARB }, chainId: 42161 }
        : process.env.URL_SEPOLIA
        ? { forking: { url: process.env.URL_SEPOLIA }, chainId: 11155111 }
        : { chainId: 31337 }),
    },
    mainnet: {
      url: process.env.URL_MAIN || "",
      accounts: process.env.PRIVATE_KEY_MAIN ? [process.env.PRIVATE_KEY_MAIN] : [],
      chainId: 1,
    },
    sepolia: {
      url: process.env.URL_SEPOLIA || "",
      accounts: process.env.PRIVATE_KEY_SEPOLIA ? [process.env.PRIVATE_KEY_SEPOLIA] : [],
    },
    arbitrum: {
      url: process.env.URL_ARB || "",
      accounts: process.env.PRIVATE_KEY_ARB ? [process.env.PRIVATE_KEY_ARB] : [],
      chainId: 42161,
    },
  },

  etherscan: {
    apiKey: process.env.API_KEY,
    customChains: [
      {
        network: "arbitrum",
        chainId: 42161,
        urls: {
          apiURL: "https://api.arbiscan.io/api",
          browserURL: "https://arbiscan.io",
        },
      },
    ],
  },
};
