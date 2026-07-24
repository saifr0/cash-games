const hre = require("hardhat");
const { run } = require("hardhat");

// ── Arbitrum One Chainlink price feeds ────────────────────────────────────────
// ETH/USD  — 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612  (24h heartbeat)
// USDC/USD — 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3  (24h heartbeat)
// USDT/USD — 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7  (24h heartbeat)
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
    // "Already verified" is not a fatal error
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
  console.log("Deployer  :", deployer.address);
  console.log(
    "Balance   :",
    hre.ethers.formatEther(
      await hre.ethers.provider.getBalance(deployer.address),
    ),
    "ETH\n",
  );

  // ── Wallets ────────────────────────────────────────────────────────────────
  // Change these before deploying if you want separate wallets.
  const presaleWallet = deployer.address; // holds 10 M $FCASH, must approve presale contract
  const fundsWallet = deployer.address; // receives all purchase funds
  const owner = deployer.address;

  // ── 1. Deploy Fake Cash Games token ────────────────────────────────────────
  const fakeCashArgs = [
    "Fake Cash Games", // name
    "$FCASH", // symbol
    deployer.address, // houseWallet     (25 M)
    "0x5DA60bEf555244263833a21EEb872Ed11A0AA62c", // stakingRewards  (50 M)
    presaleWallet, // privateSale     (10 M) → presale allocation
    deployer.address, // uniswapLiquidity(10 M)
    deployer.address, // levelUpRewards  ( 5 M)
  ];

  // console.log("Deploying Fake Cash Games ($FCASH) …");
  // const FakeCash = await hre.ethers.deployContract("CashGames", fakeCashArgs);
  // await FakeCash.waitForDeployment();
  // console.log("FakeCash deployed to :", FakeCash.target);

  // // ── 2. Deploy Mock USDC ────────────────────────────────────────────────────
  // console.log("\nDeploying Mock USDC …");
  // const MockUSDC = await hre.ethers.deployContract("MockERC20", [
  //   "Mock USD Coin",
  //   "USDC",
  //   6,
  // ]);
  // await MockUSDC.waitForDeployment();
  // console.log("MockUSDC deployed to :", MockUSDC.target);

  // // ── 3. Deploy Mock USDT ────────────────────────────────────────────────────
  // console.log("\nDeploying Mock USDT …");
  // const MockUSDT = await hre.ethers.deployContract("MockERC20", [
  //   "Mock Tether USD",
  //   "USDT",
  //   6,
  // ]);
  // await MockUSDT.waitForDeployment();
  // console.log("MockUSDT deployed to :", MockUSDT.target);

  // ── 4. Deploy Presale ──────────────────────────────────────────────────────
  // Arbitrum One Chainlink feeds (all 24h heartbeat).
  const ethPriceFeed = "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612"; // ETH/USD  Arb One
  const usdcPriceFeed = "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3"; // USDC/USD Arb One
  const usdtPriceFeed = "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7"; // USDT/USD Arb One
  const tokenPrice = 10_000; // $0.05 per token (6-decimal USD)

  const presaleArgs = [
    "0xEb435353f3629340df75437AEA83C6C6455e43d6",
    "0x6A8d8Fb8a160E2b836717b52Dd80641f53AFEF2b",
    "0x6E50aAC7aa166Ff3e245983B2bd906a086847E1B",
    ethPriceFeed,
    usdcPriceFeed,
    usdtPriceFeed,
    presaleWallet,
    fundsWallet,
    tokenPrice,
    owner,
  ];

  // console.log("\nDeploying Presale …");
  // const Presale = await hre.ethers.deployContract("Presale", presaleArgs);
  // await Presale.waitForDeployment();
  // console.log("Presale deployed to  :", Presale.target);

  // // ── 5. Update staleness to match Arbitrum 24h feed heartbeat ──────────────
  // // Default priceFeedStaleness is 1h — too tight for Arb ETH/USD (24h heartbeat).
  // console.log(
  //   "\nUpdating priceFeedStaleness to 25h (24h heartbeat + 1h buffer) …",
  // );
  // const tx1 = await Presale.setPriceFeedStaleness(25 * 3600);
  // await tx1.wait();
  // console.log("priceFeedStaleness updated ✓");

  // // ── 6. Approve Presale to pull 10 M $FCASH from presaleWallet ─────────────
  // const approvalAmount = hre.ethers.parseEther("10000000");
  // console.log("\nApproving Presale to spend 10 M $FCASH …");
  // const tx2 = await FakeCash.approve(Presale.target, approvalAmount);
  // await tx2.wait();
  // console.log("Approval done ✓");

  // // ── Summary ────────────────────────────────────────────────────────────────
  // console.log("\n────────────────────────────────────────────────────");
  // console.log("DEPLOYMENT SUMMARY (Arbitrum One)");
  // console.log("────────────────────────────────────────────────────");
  // console.log("FakeCash  ($FCASH) :", FakeCash.target);
  // console.log("MockUSDC  (USDC)   :", MockUSDC.target);
  // console.log("MockUSDT  (USDT)   :", MockUSDT.target);
  // console.log("Presale            :", Presale.target);
  // console.log("────────────────────────────────────────────────────\n");

  // ── 7. Verify on Arbiscan ──────────────────────────────────────────────────
  // Arbiscan rate-limit: wait between submissions.
  console.log("Waiting 30s before verification …");
  await delay(30_000);

  await verify("0xEb435353f3629340df75437AEA83C6C6455e43d6", fakeCashArgs);
  await delay(10_000);

  await verify("0x6A8d8Fb8a160E2b836717b52Dd80641f53AFEF2b", [
    "Mock USD Coin",
    "USDC",
    6,
  ]);
  await delay(10_000);

  await verify("0x6E50aAC7aa166Ff3e245983B2bd906a086847E1B", [
    "Mock Tether USD",
    "USDT",
    6,
  ]);
  await delay(10_000);

  await verify("0x28149106058F0e23C93672Def291fA634dE4bD1A", presaleArgs);

  console.log("\nAll done.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
