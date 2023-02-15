// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy

  const gpFund = "0xC30791E90749F72Cc4f0d6e5af3D73a0af0207Cc";
  const usdc = "0xE097d6B3100777DC31B34dC2c58fB524C2e76921";
  const bp = 10000;

  const Token = await hre.ethers.getContractFactory("GPToken");
  const token = await Token.deploy();
  await token.deployed();
  console.log("GPToken deployed to:", token.address);

  const Vault = await hre.ethers.getContractFactory("GPVault");
  const vault = await Vault.deploy(gpFund, token.address, usdc, bp);
  await vault.deployed();
  console.log("GPVault deployed to:", vault.address);



  const GP = await hre.ethers.getContractFactory("GPGovernance");
  const gp = await GP.deploy(token.address, 2);
  await gp.deployed;
  console.log("GP deployed to:", gp.address);

  const GPS = await hre.ethers.getContractFactory("GPService");
  const gps = await GPS.deploy(gp.address, vault.address);
  await gps.deployed();
  console.log("GPS deployed to:", gps.address);

  await token.addGovernanceRole(vault.address);
  await vault.addGovernanceRole(gp.address);
  await vault.addGovernanceRole(gps.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
