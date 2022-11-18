const hre = require("hardhat");
const { ethers, upgrades } = hre;

async function verifyContract(address, ...constructorArguments) {
  await hre.run("verify:verify", {
    address,
    constructorArguments,
  });
}

async function deployContract(name, ...constructorArgs) {
  const factory = await ethers.getContractFactory(name);
  const contract = await factory.deploy(...constructorArgs);
  await contract.deployed();
  return contract;
}

async function deployProxy(name, ...constructorArgs) {
  const factory = await ethers.getContractFactory(name);
  const contract = await upgrades.deployProxy(factory, constructorArgs);
  await contract.deployed();
  return contract;
}

module.exports = {
  verifyContract,
  deployContract,
  deployProxy,
};
