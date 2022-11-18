const deployProxyAdmin = async (hre) => {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  await deploy("ProxyAdmin", {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports = deployProxyAdmin;
deployProxyAdmin.tags = ["ProxyAdmin"];