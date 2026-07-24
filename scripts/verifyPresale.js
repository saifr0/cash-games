const { run } = require("hardhat");

async function main() {
  // ── Fill in from deployment logs ────────────────────────────────────────
  const presaleAddress = "0x8BB67f1a846C633816D760Ef1145f7354D58E50A";
  const cashGamesAddress  = "0x038658fD3f33ac4Cbd7A09F9461EA11e99D50E02";
  const mockUSDCAddress   = "0xc932ec8079C417907aCB831106AB305929D2B271";
  const mockUSDTAddress   = "0x4aA227922ae240Ced3fb50195058218cF2Bb9135";

  const args = [
    cashGamesAddress,
    mockUSDCAddress,
    mockUSDTAddress,
    "0x694AA1769357215DE4FAC081bf1f309aDC325306", // ETH/USD feed  (Sepolia)
    "0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E", // USDC/USD feed (Sepolia)
    "0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E", // USDT/USD feed (Sepolia — reused USDC/USD, no USDT feed on Sepolia)
    "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269", // presaleWallet
    "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269", // fundsWallet
    50_000,                                         // tokenPrice
    "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269", // owner
  ];

  console.log("Verifying Presale at", presaleAddress);
  await run("verify:verify", {
    address: presaleAddress,
    constructorArguments: args,
  });
}

main();
