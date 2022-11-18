const deployReflexSaleImpl = async (hre) => {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  await deploy("ReflexSale01", {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports = deployReflexSaleImpl;
deployReflexSaleImpl.tags = ["ReflexSaleImpl"];