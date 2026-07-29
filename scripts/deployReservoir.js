const hre = require("hardhat");
const { run, ethers } = require("hardhat");

async function verify(address, constructorArguments) {
  console.log(`verify  ${address} with arguments ${JSON.stringify(constructorArguments)}`);
  await run("verify:verify", {
    address,
    constructorArguments,
  });
}

async function main() {
  // ===== CONFIG =====
  const assetsList = [
    "0x6967267D0dE16bE779258eb9EbC9ADEDa2D393B5",
  ];
  const initialOwner = "0x12eF0F1C99D8FD50fFd37cCd12B09Ef7f1213269";
  const claiming    = "0x4B8b2F3C990895975A458d5afA8fe97B70955543";

  // 1. Deploy implementation
  const ReservoirFactory = await ethers.getContractFactory("Reservoir");
  console.log("Deploying Reservoir implementation...");
  const impl = await ReservoirFactory.deploy();
  await impl.waitForDeployment();
  console.log("Reservoir implementation deployed to:", impl.target);

  // 2. Encode initializer call
  const initData = ReservoirFactory.interface.encodeFunctionData("initialize", [
    assetsList,
    initialOwner,
    claiming,
  ]);

  // 3. Deploy ERC1967Proxy(implementation, initData)
  const ProxyFactory = await ethers.getContractFactory(
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
  );
  console.log("Deploying Reservoir proxy...");
  const proxy = await ProxyFactory.deploy(impl.target, initData);
  await proxy.waitForDeployment();
  console.log("Reservoir proxy deployed to:", proxy.target);

  // 4. Wait for block explorer to index the contracts
  console.log("Waiting 20s before verification...");
  await new Promise((resolve) => setTimeout(resolve, 20000));

  // 5. Verify implementation (no constructor args — _disableInitializers is called)
  await verify(impl.target, []);

  // 6. Verify proxy (constructor args: implementation address + encoded init calldata)
  await verify(proxy.target, [impl.target, initData]);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
