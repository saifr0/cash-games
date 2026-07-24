const hre = require("hardhat");

const MOCK_USDC = "0x6A8d8Fb8a160E2b836717b52Dd80641f53AFEF2b";
const MOCK_USDT = "0x6E50aAC7aa166Ff3e245983B2bd906a086847E1B";
const RECIPIENT = "0xE8E03830B1505F8AC6804a438bdc7B6e4e96BefD";
const AMOUNT    = hre.ethers.parseUnits("100000", 6); // 100,000 (6 decimals)

async function main() {
  const [signer] = await hre.ethers.getSigners();
  console.log("Signer:", signer.address);

  const abi = ["function mint(address to, uint256 amount) external"];

  const usdc = new hre.ethers.Contract(MOCK_USDC, abi, signer);
  const usdt = new hre.ethers.Contract(MOCK_USDT, abi, signer);

  console.log("Minting 100,000 USDC...");
  const tx1 = await usdc.mint(RECIPIENT, AMOUNT);
  await tx1.wait();
  console.log("  USDC tx:", tx1.hash);

  console.log("Minting 100,000 USDT...");
  const tx2 = await usdt.mint(RECIPIENT, AMOUNT);
  await tx2.wait();
  console.log("  USDT tx:", tx2.hash);

  console.log("Done. 100,000 USDC + 100,000 USDT minted to", RECIPIENT);
}

main().catch((err) => { console.error(err); process.exit(1); });
