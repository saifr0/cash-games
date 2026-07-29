const hre = require("hardhat");
const { ethers } = hre;

/**
 * Standalone TeamVesting deploy script.
 * Use this when CashGames, Claiming, and Reservoir are already deployed.
 * For a full-stack deploy (all contracts from scratch), use deployAll.js.
 *
 * Steps:
 *   1. Deploy TeamVesting
 *   2. token.approve(vesting, alloc)
 *   3. vesting.depositToPool()
 *
 * Required env vars:
 *   VESTING_TOKEN    — CashGames token address
 *   VESTING_POOL     — Reservoir proxy address
 *   VESTING_CLAIMING — Claiming contract address
 *
 * Optional env vars:
 *   VESTING_OWNER    — defaults to deployer address
 */
async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer :", deployer.address);
  console.log("Network  :", hre.network.name);

  // ── Config ────────────────────────────────────────────────────────────────
  const OWNER    = process.env.VESTING_OWNER    || deployer.address;
  const TOKEN    = process.env.VESTING_TOKEN;
  const POOL     = process.env.VESTING_POOL;
  const CLAIMING = process.env.VESTING_CLAIMING;

  if (!TOKEN || !POOL || !CLAIMING) {
    throw new Error("Missing env vars — set VESTING_TOKEN, VESTING_POOL, VESTING_CLAIMING");
  }

  // TODO: switch to production values before mainnet launch
  //   CLIFF_DURATION = 3 * 365 * 24 * 3600  (94608000 — 3 years)
  //   MONTH_DURATION = 30 * 24 * 3600        (2592000  — 30 days)
  const CLIFF_DURATION = 10 * 60;  // 600  — 10 minutes
  const MONTH_DURATION =  2 * 60;  // 120  — 2 minutes

  const TEAM_ALLOC = ethers.parseEther("23400000"); // 23.4 M tokens

  console.log("\n── Config ──────────────────────────────────────────────────");
  console.log("  Owner      :", OWNER);
  console.log("  Token      :", TOKEN);
  console.log("  Pool       :", POOL);
  console.log("  Claiming   :", CLAIMING);
  console.log("  Cliff      :", CLIFF_DURATION, "seconds (10 min)");
  console.log("  Month      :", MONTH_DURATION,  "seconds (2 min)");
  console.log("  Allocation :", ethers.formatEther(TEAM_ALLOC), "CASH");

  // ── Step 1: Deploy TeamVesting ────────────────────────────────────────────
  console.log("\nStep 1 / 3 — Deploying TeamVesting...");
  const vesting = await ethers.deployContract("TeamVesting", [
    OWNER,
    TOKEN,
    POOL,
    CLAIMING,
    CLIFF_DURATION,
    MONTH_DURATION,
    TEAM_ALLOC,
  ]);
  await vesting.waitForDeployment();
  console.log("  TeamVesting :", vesting.target);

  // ── Step 2: Approve ───────────────────────────────────────────────────────
  console.log("\nStep 2 / 3 — token.approve(vesting, TEAM_ALLOC)...");
  const token = await ethers.getContractAt("CashGames", TOKEN);

  const deployerBalance = await token.balanceOf(deployer.address);
  if (deployerBalance < TEAM_ALLOC) {
    throw new Error(
      `Deployer has ${ethers.formatEther(deployerBalance)} CASH — needs ${ethers.formatEther(TEAM_ALLOC)}`
    );
  }

  const approveTx = await token.approve(vesting.target, TEAM_ALLOC);
  await approveTx.wait();
  console.log("  Approved. tx:", approveTx.hash);

  // ── Step 3: depositToPool ─────────────────────────────────────────────────
  console.log("\nStep 3 / 3 — vesting.depositToPool()...");
  const depositTx = await vesting.depositToPool();
  await depositTx.wait();
  console.log("  Tokens deposited into Reservoir ✓");

  // ── Verify ────────────────────────────────────────────────────────────────
  if (!["hardhat", "localhost"].includes(hre.network.name)) {
    console.log("\nWaiting 20s for block explorer to index...");
    await new Promise((r) => setTimeout(r, 20_000));

    console.log("Verifying TeamVesting...");
    try {
      await hre.run("verify:verify", {
        address: vesting.target,
        constructorArguments: [OWNER, TOKEN, POOL, CLAIMING, CLIFF_DURATION, MONTH_DURATION, TEAM_ALLOC],
      });
      console.log("  Verified.");
    } catch (e) {
      if (e.message.includes("Already Verified")) {
        console.log("  Already verified.");
      } else {
        console.error("  Verification failed:", e.message);
      }
    }
  }

  // ── Summary ───────────────────────────────────────────────────────────────
  const block       = await ethers.provider.getBlock("latest");
  const cliffEndsAt = new Date((block.timestamp + CLIFF_DURATION) * 1000).toISOString();

  console.log("\n══════════════════════════════════════════════════════════════");
  console.log("  TeamVesting     :", vesting.target);
  console.log("  Token           :", await vesting.token());
  console.log("  Pool            :", await vesting.pool());
  console.log("  Claiming        :", await vesting.claiming());
  console.log("  Monthly amount  :", ethers.formatEther(await vesting.monthlyAmount()), "CASH");
  console.log("  Deposited       :", await vesting.depositedToPool());
  console.log("  Cliff ends at   :", cliffEndsAt);
  console.log("══════════════════════════════════════════════════════════════");
  console.log("\nPost-cliff lifecycle:");
  console.log("  1. vesting.withdraw()                 — initiates Reservoir → Claiming redemption");
  console.log("  2. (wait 1-min Claiming cooldown)");
  console.log("  3. vesting.claimFromClaiming(<index>) — pulls tokens into TeamVesting");
  console.log("  4. vesting.claim()                    — sends each monthly tranche to owner");
}

main().catch((err) => { console.error(err); process.exit(1); });
