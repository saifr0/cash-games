const hre = require("hardhat");
const { run } = require("hardhat");

// ── Arbitrum One addresses ─────────────────────────────────────────────────────
// $CASH token  : deployed via deployTeamVesting.js
// USDC         : 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
// USDT         : 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
// ETH/USD feed : 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612  (24h heartbeat)
// USDC/USD feed: 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3  (24h heartbeat)
// USDT/USD feed: 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7  (24h heartbeat)
//
// Required .env vars:
//   PRIVATE_KEY_ARB      — deployer private key
//   URL_ARB              — Arbitrum RPC URL
//   API_KEY              — Arbiscan API key
//   FUNDS_WALLET         — wallet that receives all sale proceeds
//   PRESALE_OWNER        — admin wallet (can pause, update price, etc.)
//
// Run:
//   npx hardhat run scripts/deployPresaleArb.js --network arbitrum

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

async function verify(address, constructorArguments) {
  console.log(`\nVerifying ${address} …`);
  try {
    await run("verify:verify", { address, constructorArguments });
    console.log("Verified ✓");
  } catch (e) {
    if (
      e.message.includes("Already Verified") ||
      e.message.includes("already verified")
    ) {
      console.log("Already verified ✓");
    } else {
      console.error("Verification failed:", e.message);
    }
  }
}

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer :", deployer.address);
  console.log(
    "Balance  :",
    hre.ethers.formatEther(
      await hre.ethers.provider.getBalance(deployer.address)
    ),
    "ETH\n"
  );

  // ── Wallets ──────────────────────────────────────────────────────────────────
  const fundsWallet   = process.env.FUNDS_WALLET;
  const owner         = process.env.PRESALE_OWNER;
  // privateSale wallet from token deployment — holds 10 M $CASH and must approve Presale
  const presaleWallet = "0x1C495C54374cfE2CABD6B82ccDEFd8809238b231";

  if (!fundsWallet || !owner) {
    throw new Error("Set FUNDS_WALLET and PRESALE_OWNER in .env");
  }

  // ── Token & stablecoin addresses (Arbitrum One) ───────────────────────────────
  const cashToken = "0xEb435353f3629340df75437AEA83C6C6455e43d6"; // $CASH
  const usdc      = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"; // USDC
  const usdt      = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"; // USDT

  // ── Chainlink feeds (Arbitrum One) ────────────────────────────────────────────
  const ethPriceFeed  = "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612"; // ETH/USD
  const usdcPriceFeed = "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3"; // USDC/USD
  const usdtPriceFeed = "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7"; // USDT/USD

  // ── Token price ───────────────────────────────────────────────────────────────
  // 6-decimal USD: 50_000 = $0.05 per token
  const tokenPrice = 50_000;

  // ── 1. Deploy Presale ─────────────────────────────────────────────────────────
  const presaleArgs = [
    cashToken,
    usdc,
    usdt,
    ethPriceFeed,
    usdcPriceFeed,
    usdtPriceFeed,
    presaleWallet,
    fundsWallet,
    tokenPrice,
    owner,
  ];

  console.log("Deploying Presale …");
  console.log("  $CASH       :", cashToken);
  console.log("  presaleWallet:", presaleWallet);
  console.log("  fundsWallet  :", fundsWallet);
  console.log("  owner        :", owner);
  console.log("  tokenPrice   :", tokenPrice, "($0.05 per token)");

  const Presale = await hre.ethers.deployContract("Presale", presaleArgs);
  await Presale.waitForDeployment();
  console.log("\nPresale deployed to:", Presale.target);

  // ── 2. Update staleness to match Arbitrum 24h feed heartbeat ─────────────────
  // Default priceFeedStaleness is 1h — too tight for Arb feeds (24h heartbeat).
  console.log("\nUpdating feed staleness to 25h …");
  const tx1 = await Presale.setPriceFeedStaleness(25 * 3600);
  await tx1.wait();
  const tx2 = await Presale.setStablecoinFeedStaleness(25 * 3600);
  await tx2.wait();
  console.log("Feed staleness updated ✓");

  // ── 3. Summary ────────────────────────────────────────────────────────────────
  console.log("\n────────────────────────────────────────────────────");
  console.log("DEPLOYMENT SUMMARY (Arbitrum One)");
  console.log("────────────────────────────────────────────────────");
  console.log("$CASH token  :", cashToken);
  console.log("Presale      :", Presale.target);
  console.log("fundsWallet  :", fundsWallet);
  console.log("tokenPrice   : $0.05");
  console.log("────────────────────────────────────────────────────");
  console.log("\nNEXT STEP: approve Presale to spend 10 M $CASH");
  console.log("  From wallet :", presaleWallet);
  console.log("  Spender     :", Presale.target);
  console.log("  Amount      : 10,000,000 tokens (10000000000000000000000000)");

  // ── 4. Verify on Arbiscan ─────────────────────────────────────────────────────
  console.log("\nWaiting 30s before verification …");
  await delay(30_000);
  await verify(Presale.target, presaleArgs);

  console.log("\nAll done.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
