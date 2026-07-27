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
  const name = "$CASH";
  const symbol = "$CASH";
  const stakingRewards = "0x921eF4f117460275eB8f54823282b9ef159F6815";
  const privateSale = "0x1C495C54374cfE2CABD6B82ccDEFd8809238b231";
  const uniswapLiquidity = "0xa72564252A6e3BD4d9C0621ce4E415130D777B26";
  const levelUpRewards = "0xdD9E784aDCF3616178099ca0198489094C75F0f1";
  const teamVesting = "0xB244Ca6BdE6bB29DDCdaD0Ab9Fd1312C7ce25643";
  const teamVesting1 = "0x8DF2c30D46c3309685F1e5961E6001A1B8F818Dc";
  const dedicatedWallet = "0xBDBe17B48F08FcDCd9D31F9171b39a161Bd7E688";

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
