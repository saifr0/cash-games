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
  const name = "CASH-FAKE";
  const symbol = "CASH-FAKE";
  const stakingRewards = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const privateSale = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const uniswapLiquidity = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const levelUpRewards = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const teamVesting = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const teamVesting1 = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const dedicatedWallet = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";

  const CashGames = await hre.ethers.deployContract("CashGames", [
    name,
    symbol,
    stakingRewards,
    privateSale,
    uniswapLiquidity,
    levelUpRewards,
    teamVesting,
    teamVesting1,
    dedicatedWallet,
  ]);

  console.log("Deploying CashGames...");

  await CashGames.waitForDeployment();

  console.log("CashGames deployed to:", CashGames.target);

  await new Promise((resolve) => setTimeout(resolve, 20000));

  verify(CashGames.target, [
    name,
    symbol,
    stakingRewards,
    privateSale,
    uniswapLiquidity,
    levelUpRewards,
    teamVesting,
    teamVesting1,
    dedicatedWallet,
  ]);
}

main();
