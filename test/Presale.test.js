const { expect } = require("chai");
const { ethers } = require("hardhat");

// ── Sepolia Chainlink price feeds ───────────────────────────────────────────
const ETH_FEED  = "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // ETH/USD
const USDC_FEED = "0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E"; // USDC/USD

// $0.05 per token (6-decimal USD)
const TOKEN_PRICE = 50_000n;
const MAX_TOKENS  = ethers.parseEther("10000000");

describe("Presale — Sepolia fork", function () {
  this.timeout(120_000);

  let presale, cashGames, mockUSDC, mockUSDT;
  let owner, fundsWallet, buyer;

  before(async function () {
    [owner, fundsWallet, buyer] = await ethers.getSigners();

    // ── Deploy mock stablecoins ─────────────────────────────────────────
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockUSDC = await MockERC20.deploy("USD Coin", "USDC", 6);
    mockUSDT = await MockERC20.deploy("Tether USD", "USDT", 6);

    // ── Mint 10 000 USDC and 10 000 USDT to buyer ──────────────────────
    await mockUSDC.mint(buyer.address, 10_000n * 10n ** 6n);
    await mockUSDT.mint(buyer.address, 10_000n * 10n ** 6n);

    // ── Deploy CashGames; owner receives privateSale allocation ────────
    const CashGames = await ethers.getContractFactory("CashGames");
    cashGames = await CashGames.deploy(
      "$CASH", "$CASH",
      owner.address,  // houseWallet       25 M
      owner.address,  // stakingRewards    50 M
      owner.address,  // privateSale       10 M  ← presaleWallet
      owner.address,  // uniswapLiquidity  10 M
      owner.address   // levelUpRewards     5 M
    );

    // ── Deploy Presale with Sepolia price feeds ─────────────────────────
    const Presale = await ethers.getContractFactory("Presale");
    presale = await Presale.deploy(
      await cashGames.getAddress(),
      await mockUSDC.getAddress(),
      await mockUSDT.getAddress(),
      ETH_FEED,
      USDC_FEED,
      owner.address,        // presaleWallet
      fundsWallet.address,
      TOKEN_PRICE,
      owner.address
    );

    // ── Approve presale to pull tokens from presaleWallet (owner) ──────
    await cashGames.approve(await presale.getAddress(), MAX_TOKENS);
  });

  // ── buyWithETH ─────────────────────────────────────────────────────────
  it("buyWithETH: buyer receives CG tokens, fundsWallet receives ETH", async function () {
    const ethIn = ethers.parseEther("1");

    const cgBefore    = await cashGames.balanceOf(buyer.address);
    const fundsBefore = await ethers.provider.getBalance(fundsWallet.address);

    const tx = await presale.connect(buyer).buyWithETH({ value: ethIn });
    const receipt = await tx.wait();

    const cgAfter    = await cashGames.balanceOf(buyer.address);
    const fundsAfter = await ethers.provider.getBalance(fundsWallet.address);

    const cgReceived = cgAfter - cgBefore;
    expect(cgReceived).to.be.gt(0n, "buyer should receive CG tokens");
    expect(fundsAfter - fundsBefore).to.equal(ethIn, "fundsWallet should receive exact ETH");

    const event = receipt.logs.find(
      (l) => l.fragment && l.fragment.name === "TokensPurchased"
    );
    expect(event).to.not.be.undefined;

    console.log(`  buyWithETH: 1 ETH → ${ethers.formatEther(cgReceived)} $CASH`);
  });

  // ── buyWithToken (USDC) ─────────────────────────────────────────────────
  it("buyWithToken (USDC): buyer receives CG tokens, fundsWallet receives USDC", async function () {
    const usdcIn = 1_000n * 10n ** 6n;

    await mockUSDC.connect(buyer).approve(await presale.getAddress(), usdcIn);

    const cgBefore    = await cashGames.balanceOf(buyer.address);
    const fundsBefore = await mockUSDC.balanceOf(fundsWallet.address);

    const tx = await presale.connect(buyer).buyWithToken(await mockUSDC.getAddress(), usdcIn);
    const receipt = await tx.wait();

    const cgAfter    = await cashGames.balanceOf(buyer.address);
    const fundsAfter = await mockUSDC.balanceOf(fundsWallet.address);

    const cgReceived = cgAfter - cgBefore;
    expect(cgReceived).to.be.gt(0n, "buyer should receive CG tokens");
    expect(fundsAfter - fundsBefore).to.equal(usdcIn, "fundsWallet should receive exact USDC");

    const event = receipt.logs.find(
      (l) => l.fragment && l.fragment.name === "TokensPurchased"
    );
    expect(event).to.not.be.undefined;

    console.log(`  buyWithToken USDC: 1 000 USDC → ${ethers.formatEther(cgReceived)} $CASH`);
  });

  // ── buyWithToken (USDT) ─────────────────────────────────────────────────
  it("buyWithToken (USDT): buyer receives CG tokens, fundsWallet receives USDT", async function () {
    const usdtIn = 1_000n * 10n ** 6n;

    await mockUSDT.connect(buyer).approve(await presale.getAddress(), usdtIn);

    const cgBefore    = await cashGames.balanceOf(buyer.address);
    const fundsBefore = await mockUSDT.balanceOf(fundsWallet.address);

    const tx = await presale.connect(buyer).buyWithToken(await mockUSDT.getAddress(), usdtIn);
    const receipt = await tx.wait();

    const cgAfter    = await cashGames.balanceOf(buyer.address);
    const fundsAfter = await mockUSDT.balanceOf(fundsWallet.address);

    const cgReceived = cgAfter - cgBefore;
    expect(cgReceived).to.be.gt(0n, "buyer should receive CG tokens");
    expect(fundsAfter - fundsBefore).to.equal(usdtIn, "fundsWallet should receive exact USDT");

    const event = receipt.logs.find(
      (l) => l.fragment && l.fragment.name === "TokensPurchased"
    );
    expect(event).to.not.be.undefined;

    console.log(`  buyWithToken USDT: 1 000 USDT → ${ethers.formatEther(cgReceived)} $CASH`);
  });

  // ── Guard: plain ETH send reverts ──────────────────────────────────────
  it("plain ETH send reverts with AccidentalETHSend", async function () {
    await expect(
      buyer.sendTransaction({ to: await presale.getAddress(), value: ethers.parseEther("1") })
    ).to.be.revertedWithCustomError(presale, "AccidentalETHSend");
  });

  // ── Guard: unsupported token reverts ───────────────────────────────────
  it("buyWithToken with unknown token reverts with UnsupportedToken", async function () {
    await expect(
      presale.connect(buyer).buyWithToken(ethers.ZeroAddress, 1_000n * 10n ** 6n)
    ).to.be.revertedWithCustomError(presale, "UnsupportedToken");
  });
});
