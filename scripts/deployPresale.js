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
  // ── Wallets ─────────────────────────────────────────────────────────────
  const presaleWallet = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269"; // holds 10 M $CASH, must approve this contract
  const fundsWallet = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269"; // receives all purchase funds
  const owner = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";

  // ── 1. Deploy CashGames ─────────────────────────────────────────────────
  const cashGamesArgs = [
    "Fake Cash Games",
    "F-CashGames",
    "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269", // houseWallet
    "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269", // stakingRewards
    presaleWallet, // privateSale → presaleWallet
    "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269", // uniswapLiquidity
    "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269", // levelUpRewards
  ];

  console.log("Deploying CashGames...");
  const CashGames = await hre.ethers.deployContract("CashGames", cashGamesArgs);
  await CashGames.waitForDeployment();
  console.log("CashGames deployed to:", CashGames.target);

  // ── 2. Deploy MockUSDC & MockUSDT ───────────────────────────────────────
  console.log("Deploying MockUSDC...");
  const MockUSDC = await hre.ethers.deployContract("MockERC20", [
    "USD Coin",
    "USDC",
    6,
  ]);
  await MockUSDC.waitForDeployment();
  console.log("MockUSDC deployed to:", MockUSDC.target);

  console.log("Deploying MockUSDT...");
  const MockUSDT = await hre.ethers.deployContract("MockERC20", [
    "Tether USD",
    "USDT",
    6,
  ]);
  await MockUSDT.waitForDeployment();
  console.log("MockUSDT deployed to:", MockUSDT.target);

  // ── 3. Deploy Presale ───────────────────────────────────────────────────
  const ethPriceFeed = "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // ETH/USD  (Sepolia)
  const usdcPriceFeed = "0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E"; // USDC/USD (Sepolia)
  const usdtPriceFeed = "0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E"; // no USDT/USD on Sepolia — reuse USDC/USD
  const tokenPrice = 50_000; // $0.05 per token (6-decimal USD)

  const presaleArgs = [
    CashGames.target,
    MockUSDC.target,
    MockUSDT.target,
    ethPriceFeed,
    usdcPriceFeed,
    usdtPriceFeed,
    presaleWallet,
    fundsWallet,
    tokenPrice,
    owner,
  ];

  console.log("Deploying Presale...");
  const Presale = await hre.ethers.deployContract("Presale", presaleArgs);
  await Presale.waitForDeployment();
  console.log("Presale deployed to:", Presale.target);

  // ── 4. Approve Presale to pull 10 M $CASH from presaleWallet ───────────
  const approvalAmount = hre.ethers.parseEther("10000000");
  await CashGames.approve(Presale.target, approvalAmount);
  console.log("Approved Presale to spend 10 M $CASH");

  // ── 5. Verify all contracts (sequential with delay to stay under rate limit)
  const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  await delay(20000);
  await verify(CashGames.target, cashGamesArgs);

  await delay(5000);
  await verify(MockUSDC.target, ["USD Coin", "USDC", 6]);

  await delay(5000);
  await verify(MockUSDT.target, ["Tether USD", "USDT", 6]);

  await delay(5000);
  await verify(Presale.target, presaleArgs);
}

main();
