/**
 * Vesting Lifecycle Script
 * ─────────────────────────────────────────────────────────────────────────────
 * Deploys: Claiming → Reservoir (proxy) → TeamVesting
 * Then drives the full lifecycle:
 *   1. Mint tokens → TeamVesting     (MockERC20 open mint — works on all nets)
 *   2. deposit()                     (before 1-min cliff)
 *   3. [verify contracts]            (deferred so verification doesn't race cliff)
 *   4. [wait 1 min]
 *   5. withdraw()                    (after cliff — tokens go to Claiming)
 *   6. [wait 1 min cooldown]
 *   7. claimFromClaiming()           (tokens return to TeamVesting)
 *
 * Local:    npx hardhat run scripts/runVestingLifecycle.js
 * Fork:     FORK_ARB=true npx hardhat run scripts/runVestingLifecycle.js
 * Arbitrum: npx hardhat run scripts/runVestingLifecycle.js --network arbitrum
 * ─────────────────────────────────────────────────────────────────────────────
 */

const fs   = require("fs");
const path = require("path");
const hre  = require("hardhat");
const { ethers, network } = hre;

// ── Config ───────────────────────────────────────────────────────────────────
const ARB_CASH_TOKEN = "0x6967267D0dE16bE779258eb9EbC9ADEDa2D393B5"; // MockERC20 on Arbitrum
const ALLOCATION     = ethers.parseEther("23400000");                 // 23.4 M tokens
const CLIFF          = 60;              // 1 minute  (seconds)
const MONTH_DUR      = 60;             // 1 minute  (seconds) — for testing
const COOLDOWN       = 60;             // 1 minute Claiming cooldown (must match contract)

// ── Modes ────────────────────────────────────────────────────────────────────
const isLocalNet = () =>
  (network.name === "hardhat" || network.name === "localhost") &&
  process.env.FORK_ARB !== "true";

const isForkNet = () =>
  (network.name === "hardhat" || network.name === "localhost") &&
  process.env.FORK_ARB === "true";

const isLiveNet = () => !isLocalNet() && !isForkNet();

const canTimeTravel = () => isLocalNet() || isForkNet();

// ── Helpers ──────────────────────────────────────────────────────────────────

function saveToEnv(entries) {
  const envPath = path.resolve(__dirname, "../.env");
  let content = fs.existsSync(envPath) ? fs.readFileSync(envPath, "utf8") : "";

  for (const [key, value] of Object.entries(entries)) {
    const line = `${key}=${value}`;
    const regex = new RegExp(`^${key}=.*$`, "m");
    if (regex.test(content)) {
      content = content.replace(regex, line);
    } else {
      content += (content.endsWith("\n") || content === "" ? "" : "\n") + line + "\n";
    }
  }

  fs.writeFileSync(envPath, content);
  console.log("\n  Saved to .env:");
  for (const [key, value] of Object.entries(entries)) {
    console.log(`    ${key}=${value}`);
  }
}

async function verify(address, constructorArguments) {
  if (!isLiveNet()) return;
  console.log(`\n  Verifying ${address} ...`);
  try {
    await hre.run("verify:verify", { address, constructorArguments });
    console.log("  Verified OK");
  } catch (e) {
    if (e.message.includes("Already Verified") || e.message.includes("already verified")) {
      console.log("  Already verified");
    } else {
      console.warn("  Verification failed:", e.message);
    }
  }
}

const sep = () => console.log("\n" + "─".repeat(60));

async function printBalances(label, token, vestingAddr, reservoirAddr, claimingAddr, ownerAddr) {
  const fmt = (n) => parseFloat(ethers.formatEther(n)).toLocaleString() + " CASH";
  console.log(`\n  Balances — ${label}`);
  console.log("   TeamVesting :", fmt(await token.balanceOf(vestingAddr)));
  console.log("   Reservoir   :", fmt(await token.balanceOf(reservoirAddr)));
  console.log("   Claiming    :", fmt(await token.balanceOf(claimingAddr)));
  console.log("   Owner       :", fmt(await token.balanceOf(ownerAddr)));
}

async function logTx(label, txPromise) {
  process.stdout.write(`\n  > ${label} ... `);
  const tx = await txPromise;
  const receipt = await tx.wait();
  console.log("OK");
  console.log(`    hash : ${tx.hash}`);
  console.log(`    gas  : ${receipt.gasUsed.toString()}`);
  return receipt;
}

async function waitForTimestamp(target) {
  if (canTimeTravel()) {
    const block = await ethers.provider.getBlock("latest");
    const delta = Number(target) - block.timestamp;
    if (delta > 0) {
      await network.provider.send("evm_increaseTime", [delta + 2]);
      await network.provider.send("evm_mine");
      const mode = isForkNet() ? "fork" : "local";
      console.log(`\n  [${mode}] Skipped ${delta}s forward.`);
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
  const [deployer] = await ethers.getSigners();
  const owner = deployer.address;

  // ── STEP 0: Resolve token address ─────────────────────────────────────────
  let CASH_TOKEN = ARB_CASH_TOKEN;
  let token;

  if (isLocalNet()) {
    sep();
    console.log("STEP 0 — Deploy MockERC20 (local network)");
    const MockFactory = await ethers.getContractFactory("MockERC20");
    const mockToken = await MockFactory.deploy("CashGames", "CASH", 18);
    await mockToken.waitForDeployment();
    CASH_TOKEN = await mockToken.getAddress();
    token = mockToken;
    console.log("  MockERC20 deployed:", CASH_TOKEN);
  } else {
    token = await ethers.getContractAt("MockERC20", CASH_TOKEN);
  }

  const mode = isLocalNet() ? "LOCAL" : isForkNet() ? "FORK (Arbitrum)" : "LIVE (Arbitrum)";

  sep();
  console.log("VESTING LIFECYCLE SCRIPT");
  console.log("─".repeat(60));
  console.log("  Mode      :", mode);
  console.log("  Network   :", network.name);
  console.log("  Deployer  :", owner);
  console.log("  CASH token:", CASH_TOKEN);
  console.log("  Allocation:", ethers.formatEther(ALLOCATION), "CASH");
  console.log("  Cliff     :", CLIFF, "seconds (1 min)");
  console.log("  Cooldown  :", COOLDOWN, "seconds (1 min)");
  console.log("  Verify    :", isLiveNet() ? "YES (deferred to after deposit)" : "NO (skipped)");

  // ── STEP 1: Deploy Claiming ────────────────────────────────────────────────
  sep();
  console.log("STEP 1 — Deploy Claiming");

  const ClaimingFactory = await ethers.getContractFactory("Claiming");
  const claiming = await ClaimingFactory.deploy(owner, CASH_TOKEN);
  await claiming.waitForDeployment();
  const claimingAddr = await claiming.getAddress();
  console.log("  Claiming deployed :", claimingAddr);

  // ── STEP 2: Deploy Reservoir (impl + proxy) ───────────────────────────────
  sep();
  console.log("STEP 2 — Deploy Reservoir (impl + ERC1967Proxy)");

  const ReservoirFactory = await ethers.getContractFactory("Reservoir");
  const reservoirImpl = await ReservoirFactory.deploy();
  await reservoirImpl.waitForDeployment();
  const reservoirImplAddr = await reservoirImpl.getAddress();
  console.log("  Impl deployed     :", reservoirImplAddr);

  const initData = ReservoirFactory.interface.encodeFunctionData("initialize", [
    [CASH_TOKEN],
    owner,
    claimingAddr,
  ]);
  const ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
  const proxy = await ProxyFactory.deploy(reservoirImplAddr, initData);
  await proxy.waitForDeployment();
  const reservoirAddr = await proxy.getAddress();
  const reservoir = ReservoirFactory.attach(reservoirAddr);
  console.log("  Proxy deployed    :", reservoirAddr);

  await logTx(
    "claiming.updateReservoir(reservoir)",
    claiming.updateReservoir(reservoirAddr)
  );
  console.log("  Reservoir is now authorised in Claiming");

  // ── STEP 3: Deploy TeamVesting ─────────────────────────────────────────────
  sep();
  console.log("STEP 3 — Deploy TeamVesting");
  console.log("  cliff     :", CLIFF, "seconds — vesting starts 1 min after deploy");

  const vestingArgs = [owner, CASH_TOKEN, reservoirAddr, CLIFF, MONTH_DUR, ALLOCATION];
  const VestingFactory = await ethers.getContractFactory("TeamVesting");
  const vesting = await VestingFactory.deploy(...vestingArgs);
  await vesting.waitForDeployment();
  const vestingAddr = await vesting.getAddress();
  const vestingStart = await vesting.vestingStart();
  console.log("  TeamVesting       :", vestingAddr);
  console.log("  vestingStart      :", vestingStart.toString(), `(${new Date(Number(vestingStart) * 1000).toISOString()})`);

  // ── STEP 4: Fund TeamVesting with tokens ─────────────────────────────────
  sep();

  if (isLocalNet()) {
    console.log("STEP 4 — Mint", ethers.formatEther(ALLOCATION), "CASH to TeamVesting (local MockERC20)");
    await logTx(
      `token.mint(vesting, ${ethers.formatEther(ALLOCATION)} CASH)`,
      token.mint(vestingAddr, ALLOCATION)
    );
  } else {
    // On fork / live: deployer holds all tokens — transfer directly.
    console.log("STEP 4 — Transfer", ethers.formatEther(ALLOCATION), "CASH to TeamVesting");
    console.log("  (from deployer", owner, ")");
    const deployerBal = await token.balanceOf(owner);
    if (deployerBal < ALLOCATION) {
      console.error(`\n  ERROR: Deployer only has ${ethers.formatEther(deployerBal)} CASH.`);
      console.error(`  Need ${ethers.formatEther(ALLOCATION)} CASH. Please fund the deployer wallet first.`);
      process.exitCode = 1;
      return;
    }
    await logTx(
      `token.transfer(vesting, ${ethers.formatEther(ALLOCATION)} CASH)`,
      token.transfer(vestingAddr, ALLOCATION)
    );
  }

  await printBalances("after mint", token, vestingAddr, reservoirAddr, claimingAddr, owner);

  // ── STEP 5: Deposit (before cliff) ────────────────────────────────────────
  sep();
  console.log("STEP 5 — Deposit all tokens into Reservoir (cliff has NOT elapsed yet)");

  await logTx(
    `vesting.deposit(${ethers.formatEther(ALLOCATION)} CASH)`,
    vesting.deposit(ALLOCATION)
  );

  const shares = await reservoir.balanceOf(CASH_TOKEN, vestingAddr);
  console.log("  Shares in Reservoir:", shares.toString());
  await printBalances("after deposit", token, vestingAddr, reservoirAddr, claimingAddr, owner);

  // ── STEP 6: Verify contracts (commented out — already verified) ──────────
  // if (isLiveNet()) {
  //   sep();
  //   console.log("STEP 6 — Verify contracts on Arbiscan (cliff ticking in background)");
  //   await verify(claimingAddr,      [owner, CASH_TOKEN]);
  //   await verify(reservoirImplAddr, []);
  //   await verify(reservoirAddr,     [reservoirImplAddr, initData]);
  //   await verify(vestingAddr,       vestingArgs);
  // }

  // ── STEP 7: Wait for cliff ────────────────────────────────────────────────
  sep();
  console.log("STEP 7 — Wait for cliff (vestingStart =", vestingStart.toString() + ")");
  await waitForTimestamp(vestingStart);

  const blockAfterCliff = await ethers.provider.getBlock("latest");
  console.log("  block.timestamp :", blockAfterCliff.timestamp);
  console.log("  vestingStart    :", vestingStart.toString());
  console.log("  Cliff elapsed   :", blockAfterCliff.timestamp >= Number(vestingStart) ? "YES" : "NO");

  // ── STEP 8: Withdraw from Reservoir ───────────────────────────────────────
  sep();
  console.log("STEP 8 — Withdraw from Reservoir (tokens route to Claiming)");

  const withdrawable = await reservoir.convertToAssets(CASH_TOKEN, shares);
  console.log("  Withdrawable    :", ethers.formatEther(withdrawable), "CASH");

  await logTx(
    `vesting.withdraw(${ethers.formatEther(withdrawable)} CASH)`,
    vesting.withdraw(withdrawable)
  );

  await printBalances("after withdraw", token, vestingAddr, reservoirAddr, claimingAddr, owner);
  console.log("\n  Tokens are now in Claiming with a pending request for TeamVesting.");

  // ── STEP 9: Wait for Claiming cooldown ────────────────────────────────────
  sep();
  console.log("STEP 9 — Wait for Claiming cooldown to elapse (1 minute)");

  const [, claimRequestTime] = await claiming.getRequest(0);
  console.log("  Cooldown ends at :", claimRequestTime.toString(), `(${new Date(Number(claimRequestTime) * 1000).toISOString()})`);
  await waitForTimestamp(claimRequestTime);

  // ── STEP 10: claimFromClaiming ────────────────────────────────────────────
  sep();
  console.log("STEP 10 — Pull tokens back into TeamVesting via claimFromClaiming");

  await logTx(
    "vesting.claimFromClaiming(claiming, 0)",
    vesting.claimFromClaiming(claimingAddr, 0)
  );

  await printBalances("after claimFromClaiming", token, vestingAddr, reservoirAddr, claimingAddr, owner);

  // ── SAVE + SUMMARY ────────────────────────────────────────────────────────
  saveToEnv({
    VESTING_DEPLOYED_TOKEN:     CASH_TOKEN,
    VESTING_DEPLOYED_CLAIMING:  claimingAddr,
    VESTING_DEPLOYED_RESERVOIR: reservoirAddr,
    VESTING_DEPLOYED_VESTING:   vestingAddr,
  });

  sep();
  console.log("SUMMARY");
  console.log("─".repeat(60));
  console.log("  Claiming    :", claimingAddr);
  console.log("  Reservoir   :", reservoirAddr);
  console.log("  TeamVesting :", vestingAddr);
  console.log("");
  console.log("  Lifecycle complete:");
  console.log("   [1] Minted 1M CASH to TeamVesting");
  console.log("   [2] Deposited into Reservoir before cliff");
  console.log("   [3] Withdrew from Reservoir after cliff");
  console.log("   [4] Claimed back to TeamVesting after cooldown");
  console.log("");
  console.log("  TeamVesting now holds:", ethers.formatEther(
    await token.balanceOf(vestingAddr)
  ), "CASH — ready for monthly vesting via vesting.claim()");
  sep();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
