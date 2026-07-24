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
  // const name = "$CASH";
  // const symbol = "$CASH";

  const houseWallet = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const stakingRewards = "";
  const privateSale = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const uniswapLiquidity = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const levelUpRewards = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";

  const CashGames = await hre.ethers.deployContract("CashGames", [
    name,
    symbol,
    houseWallet,
    stakingRewards,
    privateSale,
    uniswapLiquidity,
    levelUpRewards,
  ]);

  console.log("Deploying CashGames...");
  await CashGames.waitForDeployment();
  console.log("CashGames deployed to:", CashGames.target);

  await new Promise((resolve) => setTimeout(resolve, 20000));
  verify(CashGames.target, [
    name,
    symbol,
    houseWallet,
    stakingRewards,
    privateSale,
    uniswapLiquidity,
    levelUpRewards,
  ]);
}

main();
