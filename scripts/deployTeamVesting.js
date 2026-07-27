const hre = require("hardhat");

async function main() {
  // ── Config ────────────────────────────────────────────────────────────────
  const BENEFICIARY = process.env.VESTING_BENEFICIARY;
  const OWNER       = process.env.VESTING_OWNER;

  if (!BENEFICIARY || !OWNER) {
    throw new Error("Set VESTING_BENEFICIARY and VESTING_OWNER in .env");
  }

  // ── Durations (test values) ───────────────────────────────────────────────
  // Production : cliffDuration = 3 * 365 * 24 * 3600  (3 years)
  //              monthDuration = 30 * 24 * 3600         (30 days)
  const cliffDuration   = 10 * 60;    // 10 minutes  (testing)
  const monthDuration   =  1 * 3600;  //  1 hour     (testing)
  const totalAllocation = hre.ethers.parseEther("23400000"); // 23.4 M tokens (23.5 M − 100 k dedicated wallet)

  // ── Step 1: Deploy TeamVesting (no token address yet) ─────────────────────
  console.log("\n── Step 1: Deploy TeamVesting ──────────────────────────────");
  console.log("  Beneficiary:", BENEFICIARY);
  console.log("  Owner      :", OWNER);
  console.log("  Cliff      :", cliffDuration, "seconds (10 min)");
  console.log("  Month      :", monthDuration,  "seconds (1 h)");
  console.log("  Allocation :", hre.ethers.formatEther(totalAllocation), "tokens");

  const vesting = await hre.ethers.deployContract("TeamVesting", [
    BENEFICIARY,
    OWNER,
    cliffDuration,
    monthDuration,
    totalAllocation,
  ]);
  await vesting.waitForDeployment();
  console.log("  TeamVesting:", vesting.target);

  const block = await hre.ethers.provider.getBlock("latest");
  const vestingOpensAt = new Date((block.timestamp + cliffDuration) * 1000).toISOString();
  console.log("  Vesting opens at:", vestingOpensAt);

  // ── Step 2: Deploy CashGames ─────────────────────────────────────────────
  const TEAM_VESTING_1 = process.env.TEAM_VESTING_1; // second vesting wallet
  if (!TEAM_VESTING_1) throw new Error("Set TEAM_VESTING_1 in .env");

  console.log("\n── Step 2: Deploy CashGames ────────────────────────────────");
  const cashArgs = [
    "$CASH",                                         // name
    "$CASH",                                         // symbol
    "0x921eF4f117460275eB8f54823282b9ef159F6815",   // stakingRewards   50 M
    "0x1C495C54374cfE2CABD6B82ccDEFd8809238b231",   // privateSale      10 M
    "0xa72564252A6e3BD4d9C0621ce4E415130D777B26",   // uniswapLiquidity 10 M
    "0xdD9E784aDCF3616178099ca0198489094C75F0f1",   // levelUpRewards    5 M
    vesting.target,                                  // teamVesting      23.4 M ← minted here
    TEAM_VESTING_1,                                  // teamVesting1      1.5 M
    "0xBDBe17B48F08FcDCd9D31F9171b39a161Bd7E688",   // dedicatedWallet   0.1 M
  ];

  const cash = await hre.ethers.deployContract("CashGames", cashArgs);
  await cash.waitForDeployment();
  console.log("  CashGames  :", cash.target);
  console.log("  Vesting balance:", hre.ethers.formatEther(
    await cash.balanceOf(vesting.target)
  ), "CASH (should be 23400000)");

  // ── Step 3: Wire the token address into TeamVesting ────────────────────────
  console.log("\n── Step 3: setToken on TeamVesting ─────────────────────────");
  const [signer] = await hre.ethers.getSigners();
  const vestingWithSigner = vesting.connect(signer);
  const tx = await vestingWithSigner.setToken(cash.target);
  await tx.wait();
  console.log("  setToken tx:", tx.hash);
  console.log("  Token set  :", await vesting.token());

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n── Done ────────────────────────────────────────────────────");
  console.log("  TeamVesting :", vesting.target);
  console.log("  CashGames   :", cash.target);
  console.log("  Vesting opens:", vestingOpensAt);
  console.log("  Beneficiary can call claim() after the cliff lifts.");
}

main().catch((err) => { console.error(err); process.exit(1); });
