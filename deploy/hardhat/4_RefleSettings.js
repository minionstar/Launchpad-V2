const { config: dotenvConfig } = require("dotenv");
const path = require("path");

dotenvConfig({ path: path.resolve(__dirname, "../.env") });

const deployReflexSettings = async (hre) => {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  const proxyAdmin = await ethers.getContract('ProxyAdmin');
  const saleImpl = await ethers.getContract('ReflexSale01');
  const whitelistImpl = await ethers.getContract('Whitelist');

  // Settings
  //  0x10ED43C718714eb63d5aA57B78B54704E256024E  (PcS V2 Mainnet)
  //  0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3  (PcS V2 Testnet)
  const pancakeRouter          = '0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3';
  
  // // Contract Default Settings
  // const HOUR_SECONDS = 3600;
  // const listingFee             = ethers.utils.parseUnits("1", 18);    // The flat fee in BNB (1e18 = 1 BNB)
  // const launchingFeeInTokenB   = 250;                                  // The percentage of fees returned to the router owner for successful sales (250 = 2.5%)
  // const launchingFeeInTokenA   = 150;                                  // The percentage of fees returned to the router owner for successful sales (150 = 1.5%)
  // const minLiquidityPercentage = 5000;                                 // The minimum liquidity percentage (5000 = 50%)
  // const minCapRatio            = 5000;                                 // The ratio of soft cap to hard cap, i.e. 50% means soft cap must be at least 50% of the hard cap (5000 = 50%)
  // const minSaleTime            = 1 * HOUR_SECONDS;                     // The minimum amount of time a sale has to run for
  // const maxSaleTime            = 0;                   
  // const earlyWithdrawPenalty   = 1000;                                 // 1000 = 10%

  await deploy("ReflexSettings", {
    from: deployer,
    args: [],
    log: true,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      viaAdminContract: "DefaultProxyAdmin",
      execute: {
        init: {
          methodName: "initialize",
          args: [pancakeRouter, proxyAdmin.address, saleImpl.address, whitelistImpl.address, process.env.TREASURY_ADDRESS],
        },
      },
    },
  });
};
module.exports = deployReflexSettings;
deployReflexSettings.tags = ["ReflexSettings"];
deployReflexSettings.dependencies = ["ProxyAdmin", "ReflexSaleImpl", "WhitelistImpl"];
