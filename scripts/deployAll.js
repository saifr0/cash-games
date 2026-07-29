/**
 * Full-stack deploy script — deploys every contract from scratch in one run.
 *
 * Deploy order:
 *   1. CashGames
 *   2. Claiming
 *   3. Reservoir implementation
 *   4. Reservoir proxy
 *   5. claiming.updateReservoir(proxy)
 *   6. Deploy TeamVesting
 *   7. token.approve(vesting, alloc)
 *   8. vesting.depositToPool()
 *
 * Required env vars:
 *   PRIVATE_KEY_ARB   (or PRIVATE_KEY_MAIN / PRIVATE_KEY_SEPOLIA)
 *   URL_ARB           (RPC endpoint)
 *
 * Optional env vars:
 *   VESTING_OWNER     — defaults to deployer address
 *
 * Usage:
 *   npx hardhat run scripts/deployAll.js --network arbitrum
 *   npx hardhat run scripts/deployAll.js --network localhost
 */

const hre = require("hardhat");
const { ethers } = hre;

// ─── helpers ──────────────────────────────────────────────────────────────────

async function verify(address, constructorArguments) {
  try {
    await hre.run("verify:verify", { address, constructorArguments });
    console.log(`  ✓ verified`);
  } catch (e) {
    if (e.message.toLowerCase().includes("already verified")) {
      console.log(`  ✓ already verified`);
    } else {
      console.error(`  ✗ verification failed: ${e.message}`);
    }
  }
}

function section(title) {
  console.log(`\n${"─".repeat(60)}`);
  console.log(`  ${title}`);
  console.log("─".repeat(60));
}

// ─── main ─────────────────────────────────────────────────────────────────────

async function main() {
  const [deployer] = await ethers.getSigners();
  const network    = hre.network.name;
  const IS_PROD    = network === "arbitrum" || network === "mainnet";
  const IS_LOCAL   = network === "hardhat"  || network === "localhost";

  section("Environment");
  console.log("  Network   :", network);
  console.log("  Deployer  :", deployer.address);
  console.log("  Balance   :", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  // ── Config ─────────────────────────────────────────────────────────────────
  const OWNER = process.env.VESTING_OWNER || deployer.address;

  // TODO: switch to production values before mainnet launch
  //   CLIFF_DURATION = 3 * 365 * 24 * 3600  (94608000 — 3 years)
  //   MONTH_DURATION = 30 * 24 * 3600        (2592000  — 30 days)
  const CLIFF_DURATION = 10 * 60;   // 600       — 10 minutes
  const MONTH_DURATION =  2 * 60;   // 120       — 2 minutes

  const TEAM_ALLOC = ethers.parseEther("23400000"); // 23.4 M CASH

  // CashGames constructor — all allocation wallets.
  // teamVesting slot → deployer so the 23.4 M lands in deployer's wallet;
  // TeamVesting will safeTransferFrom(deployer) in its own constructor.
  const CASH_GAMES_ARGS = {
    name:             "Cash Games",
    symbol:           "CASH",
    stakingRewards:   deployer.address, // replace with real wallet on mainnet
    privateSale:      deployer.address,
    uniswapLiquidity: deployer.address,
    levelUpRewards:   deployer.address,
    teamVesting:      deployer.address, // ← 23.4 M goes here (deployer)
    teamVesting1:     deployer.address,
    dedicatedWallet:  deployer.address,
  };

  section("Config");
  console.log("  Owner          :", OWNER);
  console.log("  Cliff duration :", CLIFF_DURATION, "s (10 min)");
  console.log("  Month duration :", MONTH_DURATION,  "s (2 min)");
  console.log("  Team alloc     :", ethers.formatEther(TEAM_ALLOC), "CASH");

  // ── Step 1: CashGames ──────────────────────────────────────────────────────
  section("Step 1 / 8 — Deploy CashGames");
  const cashGames = await ethers.deployContract("CashGames", [
    CASH_GAMES_ARGS.name,
    CASH_GAMES_ARGS.symbol,
    CASH_GAMES_ARGS.stakingRewards,
    CASH_GAMES_ARGS.privateSale,
    CASH_GAMES_ARGS.uniswapLiquidity,
    CASH_GAMES_ARGS.levelUpRewards,
    CASH_GAMES_ARGS.teamVesting,
    CASH_GAMES_ARGS.teamVesting1,
    CASH_GAMES_ARGS.dedicatedWallet,
  ]);
  await cashGames.waitForDeployment();
  console.log("  CashGames :", cashGames.target);

  const token = await ethers.getContractAt("CashGames", cashGames.target);
  const deployerBal = await token.balanceOf(deployer.address);
  console.log("  Deployer CASH balance :", ethers.formatEther(deployerBal));
  if (deployerBal < TEAM_ALLOC) {
    throw new Error(
      `Deployer only has ${ethers.formatEther(deployerBal)} CASH — expected >= ${ethers.formatEther(TEAM_ALLOC)}`
    );
  }

  // ── Step 2: Claiming ───────────────────────────────────────────────────────
  section("Step 2 / 8 — Deploy Claiming");
  const claiming = await ethers.deployContract("Claiming", [OWNER, cashGames.target]);
  await claiming.waitForDeployment();
  console.log("  Claiming :", claiming.target);

  // ── Step 3: Reservoir implementation ──────────────────────────────────────
  section("Step 3 / 8 — Deploy Reservoir implementation");
  const ReservoirFactory = await ethers.getContractFactory("Reservoir");
  const reservoirImpl    = await ReservoirFactory.deploy();
  await reservoirImpl.waitForDeployment();
  console.log("  Reservoir impl :", reservoirImpl.target);

  // ── Step 4: Reservoir proxy ────────────────────────────────────────────────
  section("Step 4 / 8 — Deploy Reservoir proxy");
  const initData = ReservoirFactory.interface.encodeFunctionData("initialize", [
    [cashGames.target], // accepted asset list
    OWNER,
    claiming.target,
  ]);

  const ProxyFactory   = await ethers.getContractFactory(
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
  );
  const reservoirProxy = await ProxyFactory.deploy(reservoirImpl.target, initData);
  await reservoirProxy.waitForDeployment();
  console.log("  Reservoir proxy :", reservoirProxy.target);

  // ── Step 5: Wire Claiming → Reservoir ─────────────────────────────────────
  section("Step 5 / 8 — claiming.updateReservoir(proxy)");
  const updateTx = await claiming.updateReservoir(reservoirProxy.target);
  await updateTx.wait();
  console.log("  claiming.reservoir :", await claiming.reservoir());

  // ── Step 6: Deploy TeamVesting ─────────────────────────────────────────────
  section("Step 6 / 8 — Deploy TeamVesting");
  const vesting = await ethers.deployContract("TeamVesting", [
    OWNER,
    cashGames.target,
    reservoirProxy.target,
    claiming.target,
    CLIFF_DURATION,
    MONTH_DURATION,
    TEAM_ALLOC,
  ]);
  await vesting.waitForDeployment();
  console.log("  TeamVesting :", vesting.target);

  // ── Step 7: Approve TeamVesting to pull allocation ─────────────────────────
  section("Step 7 / 8 — token.approve(vesting, TEAM_ALLOC)");
  const approveTx = await token.approve(vesting.target, TEAM_ALLOC);
  await approveTx.wait();
  console.log("  Approved", ethers.formatEther(TEAM_ALLOC), "CASH for", vesting.target);

  // ── Step 8: depositToPool ──────────────────────────────────────────────────
  section("Step 8 / 8 — vesting.depositToPool()");
  const depositTx = await vesting.depositToPool();
  await depositTx.wait();
  console.log("  Tokens deposited into Reservoir ✓");

  // ── Etherscan verification ─────────────────────────────────────────────────
  if (!IS_LOCAL) {
    section("Etherscan verification (waiting 20s for indexing)");
    await new Promise((r) => setTimeout(r, 20_000));

    const cashGamesArgs = [
      CASH_GAMES_ARGS.name,
      CASH_GAMES_ARGS.symbol,
      CASH_GAMES_ARGS.stakingRewards,
      CASH_GAMES_ARGS.privateSale,
      CASH_GAMES_ARGS.uniswapLiquidity,
      CASH_GAMES_ARGS.levelUpRewards,
      CASH_GAMES_ARGS.teamVesting,
      CASH_GAMES_ARGS.teamVesting1,
      CASH_GAMES_ARGS.dedicatedWallet,
    ];
    const vestingArgs = [
      OWNER,
      cashGames.target,
      reservoirProxy.target,
      claiming.target,
      CLIFF_DURATION,
      MONTH_DURATION,
      TEAM_ALLOC,
    ];

    const contracts = [
      { name: "CashGames",          address: cashGames.target,     args: cashGamesArgs },
      { name: "Claiming",           address: claiming.target,      args: [OWNER, cashGames.target] },
      { name: "Reservoir (impl)",   address: reservoirImpl.target, args: [] },
      { name: "Reservoir (proxy)",  address: reservoirProxy.target, args: [reservoirImpl.target, initData] },
      { name: "TeamVesting",        address: vesting.target,       args: vestingArgs },
    ];

    for (const { name, address, args } of contracts) {
      console.log(`\n  Verifying ${name} at ${address} ...`);
      await verify(address, args);
    }
  }

  // ── Final summary ──────────────────────────────────────────────────────────
  const block       = await ethers.provider.getBlock("latest");
  const cliffEndsAt = new Date((block.timestamp + CLIFF_DURATION) * 1000).toISOString();

  section("Deployment Summary");
  console.log("  CashGames (token)   :", cashGames.target);
  console.log("  Claiming            :", claiming.target);
  console.log("  Reservoir impl      :", reservoirImpl.target);
  console.log("  Reservoir proxy     :", reservoirProxy.target);
  console.log("  TeamVesting         :", vesting.target);
  console.log("─".repeat(60));
  console.log("  Owner               :", OWNER);
  console.log("  Monthly amount      :", ethers.formatEther(await vesting.monthlyAmount()), "CASH");
  console.log("  Deposited to pool   :", await vesting.depositedToPool());
  console.log("  Cliff ends at       :", cliffEndsAt);
  console.log("─".repeat(60));
  console.log("\n  Post-cliff lifecycle:");
  console.log("    1. vesting.withdraw()                    — initiates Reservoir → Claiming redemption");
  console.log("    2. (wait 1-min Claiming cooldown)");
  console.log("    3. vesting.claimFromClaiming(<index>)    — pulls tokens into TeamVesting, sets monthlyAmount");
  console.log("    4. vesting.claim()                       — sends each monthly tranche to owner");
  console.log("─".repeat(60));
}

main().catch((err) => { console.error(err); process.exit(1); });
