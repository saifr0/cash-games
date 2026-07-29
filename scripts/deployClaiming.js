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
  const owner = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const asset = "0x6967267D0dE16bE779258eb9EbC9ADEDa2D393B5";

  const Claiming = await hre.ethers.deployContract("Claiming", [owner, asset]);

  console.log("Deploying Claiming...");

  await Claiming.waitForDeployment();

  console.log("Claiming deployed to:", Claiming.target);

  await new Promise((resolve) => setTimeout(resolve, 20000));

  verify(Claiming.target, [owner, asset]);
}

main();
