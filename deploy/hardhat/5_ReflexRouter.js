const deployReflexRouter = async (hre) => {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  // get contracts
  const settings = await ethers.getContract('ReflexSettings');

  await deploy("ReflexRouter01", {
    from: deployer,
    args: [],
    log: true,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      viaAdminContract: "DefaultProxyAdmin",
      execute: {
        init: {
          methodName: "initialize",
          args: [settings.address],
        },
      },
    },
  });
};
module.exports = deployReflexRouter;
deployReflexRouter.tags = ["deployReflexRouter"];
deployReflexRouter.dependencies = ["ReflexSettings"];
