/**
 * Production deploy script — TeamVesting only.
 *
 * Prerequisites (already deployed):
 *   • CashGames token
 *   • Claiming contract
 *   • Reservoir proxy
 *
 * Steps executed:
 *   1. Deploy TeamVesting
 *   2. token.approve(vesting, 23.4M)
 *   3. vesting.depositToPool()
 *   4. Etherscan verification
 *
 * Required .env vars:
 *   PRIVATE_KEY_ARB   — deployer private key
 *   URL_ARB           — Arbitrum RPC URL
 *   API_KEY           — Arbiscan API key (for verification)
 *   VESTING_TOKEN     — CashGames token address
 *   VESTING_POOL      — Reservoir proxy address
 *   VESTING_CLAIMING  — Claiming contract address
 *
 * Optional .env vars:
 *   VESTING_OWNER     — vesting owner address (defaults to deployer)
 *
 * Usage:
 *   npx hardhat run scripts/deployVestingMainnet.js --network arbitrum
 */

const hre = require("hardhat");
const { ethers } = hre;

// ── Production constants ───────────────────────────────────────────────────────
const CLIFF_DURATION = 3 * 365 * 24 * 3600; // 94608000 — 3 years
const MONTH_DURATION = 30 * 24 * 3600; //  2592000 — 30 days
const TEAM_ALLOC = ethers.parseEther("23400000"); // 23.4 M CASH

// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = hre.network.name;

  console.log("══════════════════════════════════════════════════════════════");
  console.log("  TeamVesting — Production Deploy");
  console.log("══════════════════════════════════════════════════════════════");
  const EXPECTED_DEPLOYER = "0xB244Ca6BdE6bB29DDCdaD0Ab9Fd1312C7ce25643";
  if (deployer.address.toLowerCase() !== EXPECTED_DEPLOYER.toLowerCase()) {
    throw new Error(
      `Wrong wallet.\n` +
        `  Expected : ${EXPECTED_DEPLOYER}\n` +
        `  Got      : ${deployer.address}\n` +
        `Check your PRIVATE_KEY_ARB in .env`,
    );
  }

  console.log("  Network  :", network);
  console.log("  Deployer :", deployer.address);
  console.log(
    "  Balance  :",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH",
  );

  // ── Addresses (hardcoded for mainnet) ────────────────────────────────────
  const TOKEN = "0x629AeA512023C6F0454AB9c16C7c8C20905aF1B7";
  const POOL = "0x921eF4f117460275eB8f54823282b9ef159F6815";
  const CLAIMING = "0xFda62b12ACD4adCE40d2b14d3b51BC6623f5f1cd";
  const OWNER = deployer.address; // owner = deployer

  console.log("\n── Addresses ───────────────────────────────────────────────");
  console.log("  Owner    :", OWNER);
  console.log("  Token    :", TOKEN);
  console.log("  Pool     :", POOL);
  console.log("  Claiming :", CLAIMING);

  console.log("\n── Vesting parameters ──────────────────────────────────────");
  console.log("  Cliff      :", CLIFF_DURATION, "seconds (3 years)");
  console.log("  Month      :", MONTH_DURATION, "seconds (30 days)");
  console.log("  Allocation :", ethers.formatEther(TEAM_ALLOC), "CASH");
  console.log("  Monthly    :", ethers.formatEther(TEAM_ALLOC / 24n), "CASH");

  // ── Owner (deployer) token balance check ─────────────────────────────────
  const token = await ethers.getContractAt("CashGames", TOKEN);
  const ownerBal = await token.balanceOf(deployer.address);
  console.log("\n  Owner CASH balance :", ethers.formatEther(ownerBal));

  if (ownerBal < TEAM_ALLOC) {
    throw new Error(
      `Insufficient balance.\n` +
        `  Have : ${ethers.formatEther(ownerBal)} CASH\n` +
        `  Need : ${ethers.formatEther(TEAM_ALLOC)} CASH`,
    );
  }

  // ── Step 1 / 4 — Deploy TeamVesting ──────────────────────────────────────
  console.log("\n── Step 1 / 4 — Deploy TeamVesting ─────────────────────────");
  const constructorArgs = [
    OWNER,
    TOKEN,
    POOL,
    CLAIMING,
    CLIFF_DURATION,
    MONTH_DURATION,
    TEAM_ALLOC,
  ];

  const vesting = await ethers.deployContract("TeamVesting", constructorArgs);
  await vesting.waitForDeployment();
  console.log("  TeamVesting :", vesting.target);
  console.log("  tx          :", vesting.deploymentTransaction().hash);

  // ── Step 2 / 4 — Owner approves vesting to pull tokens ───────────────────
  console.log("\n── Step 2 / 4 — token.approve(vesting, 23.4M)  [owner] ─────");
  const approveTx = await token
    .connect(deployer)
    .approve(vesting.target, TEAM_ALLOC);
  await approveTx.wait();
  console.log("  tx :", approveTx.hash);

  // ── Step 3 / 4 — Owner calls depositToPool ───────────────────────────────
  console.log("\n── Step 3 / 4 — vesting.depositToPool()  [owner] ───────────");
  const vestingContract = await ethers.getContractAt(
    "TeamVesting",
    vesting.target,
  );
  const depositTx = await vestingContract.connect(deployer).depositToPool();
  await depositTx.wait();
  console.log("  tx              :", depositTx.hash);
  console.log("  depositedToPool :", await vesting.depositedToPool());

  // ── Step 4 / 4 — Verify on Arbiscan ──────────────────────────────────────
  console.log("\n── Step 4 / 4 — Etherscan Verification ─────────────────────");
  console.log("  Waiting 20s for block explorer to index...");
  await new Promise((r) => setTimeout(r, 20_000));

  try {
    await hre.run("verify:verify", {
      address: vesting.target,
      constructorArguments: constructorArgs,
    });
    console.log("  ✓ Verified");
  } catch (e) {
    if (e.message.toLowerCase().includes("already verified")) {
      console.log("  ✓ Already verified");
    } else {
      console.error("  ✗ Verification failed:", e.message);
    }
  }

  // ── Summary ───────────────────────────────────────────────────────────────
  const block = await ethers.provider.getBlock("latest");
  const cliffEndsAt = new Date(
    (block.timestamp + CLIFF_DURATION) * 1000,
  ).toISOString();

  console.log(
    "\n══════════════════════════════════════════════════════════════",
  );
  console.log("  TeamVesting    :", vesting.target);
  console.log("  Owner          :", await vesting.owner());
  console.log("  Token          :", await vesting.token());
  console.log("  Pool           :", await vesting.pool());
  console.log("  Claiming       :", await vesting.claiming());
  console.log(
    "  Total alloc    :",
    ethers.formatEther(await vesting.totalAllocation()),
    "CASH",
  );
  console.log(
    "  Monthly amount :",
    ethers.formatEther(await vesting.monthlyAmount()),
    "CASH",
  );
  console.log("  Cliff ends at  :", cliffEndsAt);
  console.log("  Deposited      :", await vesting.depositedToPool());
  console.log("══════════════════════════════════════════════════════════════");
  console.log("\n  Post-cliff lifecycle:");
  console.log(
    "    1. vesting.withdraw()                 — after cliff elapses (3 years)",
  );
  console.log("    2. (wait 7-day Claiming cooldown)");
  console.log(
    "    3. vesting.claimFromClaiming(<index>) — check index via The Graph",
  );
  console.log(
    "    4. vesting.claim()                    — call monthly to receive CASH",
  );
  console.log("══════════════════════════════════════════════════════════════");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
