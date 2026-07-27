const hre = require("hardhat");
const { run } = require("hardhat");

async function verify(address, constructorArguments) {
  console.log(
    `verify  ${address} with arguments ${constructorArguments.join(",")}`,
  );
  await run("verify:verify", {
    address,
    constructorArguments,
  });
}

async function main() {
  // ── Token & stablecoin addresses (Arbitrum One) ───────────────────────────────
  const cashToken = "0x629AeA512023C6F0454AB9c16C7c8C20905aF1B7"; // $CASH
  const usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"; // USDC
  const usdt = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"; // USDT

  // ── Chainlink feeds (Arbitrum One) ────────────────────────────────────────────
  const ethPriceFeed = "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612"; // ETH/USD
  const usdcPriceFeed = "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3"; // USDC/USD
  const usdtPriceFeed = "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7"; // USDT/USD
  const _presaleWallet = "0x1C495C54374cfE2CABD6B82ccDEFd8809238b231";
  const _fundsWallet = "0x1C495C54374cfE2CABD6B82ccDEFd8809238b231";
  const _tokenPrice = "10000";
  const _owner = "0x70ae6a6B833a76d497A22a600C8a6896747478d1";

  const Presale = await hre.ethers.deployContract("Presale", [
    cashToken,
    usdc,
    usdt,
    ethPriceFeed,
    usdcPriceFeed,
    usdtPriceFeed,
    _presaleWallet,
    _fundsWallet,
    _tokenPrice,
    _owner,
  ]);

  console.log("Deploying Presale...");

  await Presale.waitForDeployment();

  console.log("Presale deployed to:", Presale.target);

  await new Promise((resolve) => setTimeout(resolve, 20000));

  verify(Presale.target, [
    cashToken,
    usdc,
    usdt,
    ethPriceFeed,
    usdcPriceFeed,
    usdtPriceFeed,
    _presaleWallet,
    _fundsWallet,
    _tokenPrice,
    _owner,
  ]);
}

main();
