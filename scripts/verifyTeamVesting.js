const { run } = require("hardhat");
const hre = require("hardhat");

async function main() {
  const CONTRACT = "0xc57Df9832d7dC95F116Dac617b32c8DdBCD3ea81";

  const BENEFICIARY = process.env.VESTING_BENEFICIARY;
  const OWNER       = process.env.VESTING_OWNER;

  if (!BENEFICIARY || !OWNER) {
    throw new Error("Set VESTING_BENEFICIARY and VESTING_OWNER in .env");
  }

  // Must match exactly what was passed in deployTeamVesting.js
  const cliffDuration   = 10 * 60;                           // 600
  const monthDuration   =  1 * 3600;                        // 3600
  const totalAllocation = hre.ethers.parseEther("23400000"); // 23400000000000000000000000

  const constructorArgs = [
    BENEFICIARY,
    OWNER,
    cliffDuration,
    monthDuration,
    totalAllocation,
  ];

  console.log("Verifying TeamVesting at", CONTRACT);
  console.log("Constructor args:", constructorArgs);

  await run("verify:verify", {
    address: CONTRACT,
    constructorArguments: constructorArgs,
  });

  console.log("Verified successfully.");
}

main().catch((err) => { console.error(err); process.exit(1); });
