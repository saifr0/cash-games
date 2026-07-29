/**
 * Vesting Transactions Script
 * ─────────────────────────────────────────────────────────────────────────────
 * Reads deployed contract addresses from .env and drives the full lifecycle:
 *
 *   deposit()           — send tokens from TeamVesting into Reservoir
 *   [wait for cliff]
 *   withdraw()          — pull tokens back via Reservoir → Claiming
 *   [wait for cooldown]
 *   claimFromClaiming() — retrieve tokens from Claiming into TeamVesting
 *
 * Prerequisites:
 *   Run runVestingLifecycle.js first OR manually set these in .env:
 *     VESTING_DEPLOYED_TOKEN
 *     VESTING_DEPLOYED_CLAIMING
 *     VESTING_DEPLOYED_RESERVOIR
 *     VESTING_DEPLOYED_VESTING
 *
 * Commands:
 *   npx hardhat run scripts/runVestingTransactions.js --network arbitrum
 * ─────────────────────────────────────────────────────────────────────────────
 */

require("dotenv").config();
const hre = require("hardhat");
const { ethers, network } = hre;

// ── Read addresses from .env ─────────────────────────────────────────────────

const TOKEN_ADDR    = process.env.VESTING_DEPLOYED_TOKEN;
const CLAIMING_ADDR = process.env.VESTING_DEPLOYED_CLAIMING;
const RESERVOIR_ADDR = process.env.VESTING_DEPLOYED_RESERVOIR;
const VESTING_ADDR  = process.env.VESTING_DEPLOYED_VESTING;

// ── Helpers ──────────────────────────────────────────────────────────────────

const isLocal = () =>
  network.name === "hardhat" || network.name === "localhost";

const isFork = () => isLocal() && process.env.FORK_ARB === "true";

const canTimeTravel = () => isLocal();

const sep = () => console.log("\n" + "─".repeat(60));

async function logTx(label, txPromise) {
  process.stdout.write(`\n  > ${label} ... `);
  const tx = await txPromise;
  const receipt = await tx.wait();
  console.log("OK");
  console.log(`    hash : ${tx.hash}`);
  console.log(`    gas  : ${receipt.gasUsed.toString()}`);
  return receipt;
}

async function printBalances(label, token, vestingAddr, reservoirAddr, claimingAddr, ownerAddr) {
  const fmt = (n) => parseFloat(ethers.formatEther(n)).toLocaleString() + " CASH";
  console.log(`\n  Balances — ${label}`);
  console.log("   TeamVesting :", fmt(await token.balanceOf(vestingAddr)));
  console.log("   Reservoir   :", fmt(await token.balanceOf(reservoirAddr)));
  console.log("   Claiming    :", fmt(await token.balanceOf(claimingAddr)));
  console.log("   Owner       :", fmt(await token.balanceOf(ownerAddr)));
}

async function waitUntilTimestamp(target) {
  if (canTimeTravel()) {
    const block = await ethers.provider.getBlock("latest");
    const delta = Number(target) - block.timestamp;
    if (delta > 0) {
      await network.provider.send("evm_increaseTime", [delta + 2]);
      await network.provider.send("evm_mine");
      console.log(`\n  [local] Skipped ${delta}s to reach vestingStart.`);
    }
    return;
  }

  console.log(`\n  Waiting for block.timestamp >= ${target} ...`);
  while (true) {
    const block = await ethers.provider.getBlock("latest");
    if (block.timestamp >= Number(target)) break;
    const left = Number(target) - block.timestamp;
    process.stdout.write(`\r  ${left}s remaining ...   `);
    await new Promise((r) => setTimeout(r, 4000));
  }
  console.log("\n  Time reached.");
}

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  // ── Validate env ────────────────────────────────────────────────────────────
  if (!TOKEN_ADDR || !CLAIMING_ADDR || !RESERVOIR_ADDR || !VESTING_ADDR) {
    console.error("\n  ERROR: Missing addresses in .env. Run runVestingLifecycle.js first.");
    console.error("  Required:");
    console.error("    VESTING_DEPLOYED_TOKEN");
    console.error("    VESTING_DEPLOYED_CLAIMING");
    console.error("    VESTING_DEPLOYED_RESERVOIR");
    console.error("    VESTING_DEPLOYED_VESTING");
    process.exitCode = 1;
    return;
  }

  const [deployer] = await ethers.getSigners();
  const owner = deployer.address;

  // ── Attach contracts ─────────────────────────────────────────────────────────
  const token    = await ethers.getContractAt("MockERC20",   TOKEN_ADDR);
  const claiming = await ethers.getContractAt("Claiming",    CLAIMING_ADDR);
  const reservoir = await ethers.getContractAt("Reservoir",  RESERVOIR_ADDR);
  const vesting  = await ethers.getContractAt("TeamVesting", VESTING_ADDR);

  const vestingStart = await vesting.vestingStart();
  const monthlyAmt   = await vesting.monthlyAmount();
  const monthsClaimed = await vesting.monthsClaimed();

  sep();
  console.log("VESTING TRANSACTIONS SCRIPT");
  console.log("─".repeat(60));
  console.log("  Network    :", network.name);
  console.log("  Owner      :", owner);
  console.log("  Token      :", TOKEN_ADDR);
  console.log("  Claiming   :", CLAIMING_ADDR);
  console.log("  Reservoir  :", RESERVOIR_ADDR);
  console.log("  TeamVesting:", VESTING_ADDR);
  console.log("  vestingStart :", vestingStart.toString(), `(${new Date(Number(vestingStart) * 1000).toISOString()})`);
  console.log("  monthsClaimed:", monthsClaimed.toString(), "/", (await vesting.VESTING_MONTHS()).toString());

  await printBalances("current state", token, VESTING_ADDR, RESERVOIR_ADDR, CLAIMING_ADDR, owner);

  const now = (await ethers.provider.getBlock("latest")).timestamp;

  // ── STEP 1: Deposit (only if before cliff) ────────────────────────────────
  sep();
  console.log("STEP 1 — Deposit tokens into Reservoir");

  const vestingBalance = await token.balanceOf(VESTING_ADDR);

  if (now >= Number(vestingStart)) {
    console.log("  Cliff already elapsed — deposit window closed. Skipping.");
  } else if (vestingBalance === 0n) {
    console.log("  TeamVesting has no tokens to deposit. Skipping.");
  } else {
    console.log("  Available to deposit :", ethers.formatEther(vestingBalance), "CASH");
    await logTx(
      `vesting.deposit(${ethers.formatEther(vestingBalance)} CASH)`,
      vesting.deposit(vestingBalance)
    );
    await printBalances("after deposit", token, VESTING_ADDR, RESERVOIR_ADDR, CLAIMING_ADDR, owner);
  }

  // ── STEP 2: Wait for cliff ────────────────────────────────────────────────
  sep();
  console.log("STEP 2 — Wait for cliff (vestingStart =", vestingStart.toString() + ")");

  const nowAfterDeposit = (await ethers.provider.getBlock("latest")).timestamp;
  if (nowAfterDeposit < Number(vestingStart)) {
    await waitUntilTimestamp(vestingStart);
  } else {
    console.log("  Cliff already elapsed.");
  }

  // ── STEP 3: Withdraw from Reservoir ──────────────────────────────────────
  sep();
  console.log("STEP 3 — Withdraw from Reservoir");

  const shares = await reservoir.balanceOf(TOKEN_ADDR, VESTING_ADDR);

  if (shares === 0n) {
    console.log("  No shares in Reservoir. Skipping withdraw.");
  } else {
    const withdrawable = await reservoir.convertToAssets(TOKEN_ADDR, shares);
    console.log("  Shares              :", shares.toString());
    console.log("  Withdrawable        :", ethers.formatEther(withdrawable), "CASH");

    await logTx(
      `vesting.withdraw(${ethers.formatEther(withdrawable)} CASH)`,
      vesting.withdraw(withdrawable)
    );
    await printBalances("after withdraw", token, VESTING_ADDR, RESERVOIR_ADDR, CLAIMING_ADDR, owner);
    console.log("\n  Tokens are in Claiming. Waiting for cooldown...");
  }

  // ── STEP 4: Wait for Claiming cooldown ───────────────────────────────────
  sep();
  console.log("STEP 4 — Wait for Claiming cooldown");

  const claimingBalance = await token.balanceOf(CLAIMING_ADDR);
  if (claimingBalance > 0n) {
    // Read the claimRequestTime from the pending request (index 0 for TeamVesting)
    const [, claimRequestTime] = await claiming.getRequest(0);
    const nowBeforeCooldown = (await ethers.provider.getBlock("latest")).timestamp;

    if (nowBeforeCooldown < Number(claimRequestTime)) {
      console.log("  Cooldown ends at :", claimRequestTime.toString());
      await waitUntilTimestamp(claimRequestTime);
    } else {
      console.log("  Cooldown already elapsed.");
    }
  } else {
    console.log("  No pending claim in Claiming. Skipping cooldown wait.");
  }

  // ── STEP 5: claimFromClaiming ─────────────────────────────────────────────
  sep();
  console.log("STEP 5 — Pull tokens back into TeamVesting via claimFromClaiming");

  const claimingBalanceNow = await token.balanceOf(CLAIMING_ADDR);
  if (claimingBalanceNow === 0n) {
    console.log("  Claiming is empty. Skipping.");
  } else {
    await logTx(
      "vesting.claimFromClaiming(claiming, 0)",
      vesting.claimFromClaiming(CLAIMING_ADDR, 0)
    );
    await printBalances("after claimFromClaiming", token, VESTING_ADDR, RESERVOIR_ADDR, CLAIMING_ADDR, owner);
  }

  // ── SUMMARY ───────────────────────────────────────────────────────────────
  sep();
  console.log("DONE");
  console.log("─".repeat(60));
  console.log("  TeamVesting holds :", ethers.formatEther(await token.balanceOf(VESTING_ADDR)), "CASH");
  console.log("  Months claimed    :", (await vesting.monthsClaimed()).toString());
  console.log("  Monthly amount    :", ethers.formatEther(monthlyAmt), "CASH");
  console.log("  Next: call vesting.claim() after each 30-day tranche unlocks.");
  sep();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
