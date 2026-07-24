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

  // ── Step 2: Deploy CashGames (mints 23.5 M directly to TeamVesting) ───────
  console.log("\n── Step 2: Deploy CashGames ────────────────────────────────");
  const cashArgs = [
    "Cash Games",
    "CASH",
    OWNER,         // houseWallet      25 M
    OWNER,         // stakingRewards   50 M  (replace with real addresses)
    OWNER,         // privateSale      10 M
    OWNER,         // uniswapLiquidity 10 M
    OWNER,         // levelUpRewards    5 M
    vesting.target, // teamVesting     23.5 M  ← minted directly here
  ];

  const cash = await hre.ethers.deployContract("CashGames", cashArgs);
  await cash.waitForDeployment();
  console.log("  CashGames  :", cash.target);
  console.log("  Vesting balance:", hre.ethers.formatEther(
    await cash.balanceOf(vesting.target)
  ), "CASH (should be 23500000)");

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
