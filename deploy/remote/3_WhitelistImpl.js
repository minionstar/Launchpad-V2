const deployWhitelistImpl = async (hre) => {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  await deploy("Whitelist", {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports = deployWhitelistImpl;
deployWhitelistImpl.tags = ["WhitelistImpl"];