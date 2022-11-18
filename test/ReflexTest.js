const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { impersonateForToken, latest, setNextBlockTimestamp, mineBlock } = require("./helper/utils");
const { deployContract, deployProxy } = require("./helper/deployer");

const METAINFO = {
  description: "wow, this is great!",
};

describe("Reflex", () => {
  const soft = ethers.utils.parseUnits("50", 18);
  const hard = ethers.utils.parseUnits("100", 18);
  const min = ethers.utils.parseUnits("1", 18);
  const max = ethers.utils.parseUnits("100", 18);
  const presaleRate = "1000000000";
  const listingRate = "1500000000";
  const liquidity = 9000; // 90% is liquidity

  let owner, alice, bob, tom, approver, treasury;
  let partnerToken, fundTokenAddress, router, settings, fakeUsers;
  let proxyAdmin;

  fundTokenAddress = ethers.constants.AddressZero; // BNB

  const saleParams = {
    soft,
    hard,
    min,
    max,
    presaleRate,
    listingRate,
    liquidity,
    start: 0,
    end: 0,
    whitelisted: true,
    burn: true,
    privateSale: true,
    metaInfo: JSON.stringify(METAINFO),
  };

  async function createSaleContract(startTime, endTime) {
    const listingFee = await settings.listingFee();
    await partnerToken.connect(alice).approve(router.address, ethers.constants.MaxUint256);
    await router
      .connect(alice)
      .createSale(
        partnerToken.address,
        fundTokenAddress,
        { ...saleParams, start: startTime, end: endTime },
        { value: listingFee },
      );
    const salesInfo = await router.connect(alice).getSale();
    return await ethers.getContractAt("ReflexSale01", salesInfo[2]);
  }

  before(async () => {
    [owner, alice, bob, tom, approver, treasury] = await ethers.getSigners();
  });

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    fakeUsers = signers.map((signer, i) => signer.address);

    proxyAdmin = signers[9].address;

    partnerToken = await deployContract("ERC20Mock");
    const saleImpl = await deployContract("ReflexSale01");
    const whitelistImpl = await deployContract("Whitelist");
    settings = await deployProxy(
      "ReflexSettings",
      // "0x10ED43C718714eb63d5aA57B78B54704E256024E",  // BSC
      "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // ETH
      proxyAdmin,
      saleImpl.address,
      whitelistImpl.address,
      treasury.address,
    );
    router = await deployProxy("ReflexRouter01", settings.address);

    await partnerToken.transfer(alice.address, await ethers.utils.parseUnits("1000000000", 9));
  });

  describe("ReflexRouter", () => {
    it("pay fee", async () => {
      const listingFee = await settings.listingFee();

      const aliceBalance0 = await alice.getBalance();
      const treasuryBalance0 = await treasury.getBalance();
      await router.connect(alice).payFee({ value: listingFee });
      const aliceBalance1 = await alice.getBalance();
      const treasuryBalance1 = await treasury.getBalance();

      // alice balance is decreased
      expect(aliceBalance0.sub(aliceBalance1)).to.be.closeTo(listingFee, listingFee.div(1000));

      // treasury balance is decreased
      expect(treasuryBalance1.sub(treasuryBalance0)).to.be.equal(listingFee);
    });

    it("create sale: didn't pay fee", async () => {
      const listingFee = await settings.listingFee();

      await partnerToken.connect(alice).approve(router.address, ethers.constants.MaxUint256);
      const balance0 = await treasury.getBalance();
      await router.connect(alice).createSale(
        partnerToken.address,
        fundTokenAddress,
        {
          ...saleParams,
          start: Math.floor(Date.now() / 1000) + 86400 * 10,
          end: Math.floor(Date.now() / 1000) + +86400 * 10 + 3600,
          whitelisted: false,
        },
        { value: listingFee },
      );
      const balance1 = await treasury.getBalance();

      // treasury balance is increased
      expect(balance1.sub(balance0)).to.equal(listingFee);
      expect(await router.connect(alice).getSale()).to.be.not.equal(ethers.constants.AddressZero);
    });

    it("create sale: paid fee", async () => {
      const listingFee = await settings.listingFee();
      await router.connect(alice).payFee({ value: listingFee });

      await partnerToken.connect(alice).approve(router.address, ethers.constants.MaxUint256);
      await router.connect(alice).createSale(partnerToken.address, ethers.constants.AddressZero, {
        ...saleParams,
        start: Math.floor(Date.now() / 1000) + 86400 * 10,
        end: Math.floor(Date.now() / 1000) + +86400 * 10 + 3600,
        whitelisted: false,
      });
      expect(await router.connect(alice).getSale()).to.be.not.equal(ethers.constants.AddressZero);
    });
  });

  describe("ReflexSale", () => {
    it("cannot add whitelist if sale is ended, cannot remove if sale started", async () => {
      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await sale.connect(alice).addToWhitelist(fakeUsers);

      await setNextBlockTimestamp(startTime);
      await expect(sale.connect(alice).removeFromWhitelist([bob.address])).to.be.revertedWith("Sale started");
      await setNextBlockTimestamp(endTime);
      await expect(sale.connect(alice).addToWhitelist(fakeUsers)).to.be.revertedWith("Sale ended");
    });

    it("deposit: all fails before sale started", async () => {
      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await sale.connect(alice).addToWhitelist(fakeUsers);

      // fails because not fund token
      await expect(
        alice.sendTransaction({
          to: sale.address,
          value: ethers.utils.parseEther("1"),
        }),
      ).to.be.reverted;

      // deposit via function fails
      await expect(sale.connect(bob).deposit(0, { value: ethers.utils.parseEther("1") })).to.be.revertedWith(
        "Sale isn't running!",
      );
    });

    it("deposit: all go to raised after start", async () => {
      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await sale.connect(alice).addToWhitelist(fakeUsers);

      const wl = await ethers.getContractAt("Whitelist", await sale.whitelist());

      const raisedBefore = await sale.raised();
      const routerBalance = await ethers.provider.getBalance(router.address);

      await setNextBlockTimestamp(startTime);

      // deposit via function
      await sale.connect(bob).deposit(0, { value: ethers.utils.parseEther("1") });

      expect(await sale.raised()).to.be.equal(raisedBefore.add(ethers.utils.parseEther("1")));
      expect(await ethers.provider.getBalance(router.address)).to.be.equal(routerBalance);
      expect(await sale._deposited(alice.address)).to.be.equal(0);
      expect(await sale._deposited(bob.address)).to.be.equal(ethers.utils.parseEther("1"));
    });

    it("sale duration", async () => {
      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);

      // should be not running at first
      expect(await sale.running()).to.be.equal(false);
      expect(await sale.ended()).to.be.equal(false);

      // should be running at startTime
      await setNextBlockTimestamp(startTime);
      await mineBlock();
      expect(await sale.running()).to.be.equal(true);
      expect(await sale.ended()).to.be.equal(false);

      // should be ended at endTime
      await setNextBlockTimestamp(endTime);
      await mineBlock();
      expect(await sale.running()).to.be.equal(false);
      expect(await sale.ended()).to.be.equal(true);
    });

    it("sale state", async () => {
      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await sale.connect(alice).addToWhitelist(fakeUsers);

      // not successful at first
      expect(await sale.successful()).to.be.equal(false);

      await setNextBlockTimestamp(startTime);

      // not successful if not enough
      await sale.connect(bob).deposit(0, { value: soft.div(2) });
      expect(await sale.successful()).to.be.equal(false);

      // successful when over soft cap
      await sale.connect(tom).deposit(0, { value: soft.div(2) });
      expect(await sale.successful()).to.be.equal(true);
    });

    it("finalize and launch (privateSale, burn)", async () => {
      saleParams.privateSale = true;
      saleParams.burn = true;

      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await sale.connect(alice).addToWhitelist(fakeUsers);

      const raised = soft;
      await setNextBlockTimestamp(startTime);
      await sale.connect(bob).deposit(0, { value: raised });

      const totalTokens = await sale.totalTokens();
      // 1.5% in TokenA, 2.5% in TokenB devcut
      // liqudity percentage
      const decimalForTokenACalculation = ethers.utils.parseUnits("1", 18 + 10 - (await partnerToken.decimals()));
      const soldTokens = raised.mul(presaleRate).div(decimalForTokenACalculation);
      const devFeeTokenInTokenA = soldTokens.mul(150).div(10000);
      const devFeeTokenInTokenB = raised.mul(250).div(10000);
      const liquidityAmountInTokenB = saleParams.privateSale
        ? 0
        : raised.mul(liquidity).div(1e4).sub(devFeeTokenInTokenB);
      const liquidityAmountInTokenA = saleParams.privateSale
        ? 0
        : liquidityAmountInTokenB.mul(listingRate).div(decimalForTokenACalculation);

      const treasuryBNB0 = await treasury.getBalance();
      const treasuryTokenBalance0 = await partnerToken.balanceOf(treasury.address);
      const aliceTokenBalance0 = await partnerToken.balanceOf(alice.address);
      const deadBalance0 = await partnerToken.balanceOf("0x000000000000000000000000000000000000dEaD");
      await sale.connect(alice).finalize();
      const treasuryBNB1 = await treasury.getBalance();
      const deadBalance1 = await partnerToken.balanceOf("0x000000000000000000000000000000000000dEaD");
      const treasuryTokenBalance1 = await partnerToken.balanceOf(treasury.address);
      const aliceTokenBalance1 = await partnerToken.balanceOf(alice.address);

      // privateSale, burn
      expect(treasuryTokenBalance1.sub(treasuryTokenBalance0)).to.be.equal(devFeeTokenInTokenA);
      expect(aliceTokenBalance1.sub(aliceTokenBalance0)).to.be.equal(
        totalTokens.sub(soldTokens).sub(liquidityAmountInTokenA).sub(devFeeTokenInTokenA),
      );

      // consider decimal diff and listing rate accuracy
      expect(treasuryBNB1.sub(treasuryBNB0))
        .to.be.equal(devFeeTokenInTokenB)
        .to.be.equal(
          treasuryTokenBalance1.sub(treasuryTokenBalance0).mul(1e10).mul(1e9).div(presaleRate).div(150).mul(250),
        );

      const bobToken0 = await partnerToken.balanceOf(bob.address);
      await sale.connect(bob).withdraw();
      const bobToken1 = await partnerToken.balanceOf(bob.address);
      expect(bobToken1.sub(bobToken0)).to.be.equal(soldTokens);
    });

    it("finalize and launch (privateSale, refund)", async () => {
      saleParams.privateSale = true;
      saleParams.burn = false;

      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await sale.connect(alice).addToWhitelist(fakeUsers);

      const raised = soft;
      await setNextBlockTimestamp(startTime);
      await sale.connect(bob).deposit(0, { value: raised });

      const totalTokens = await sale.totalTokens();
      // 1.5% in TokenA, 2.5% in TokenB devcut
      // liqudity percentage
      const decimalForTokenACalculation = ethers.utils.parseUnits("1", 18 + 10 - (await partnerToken.decimals()));
      const soldTokens = raised.mul(presaleRate).div(decimalForTokenACalculation);
      const devFeeTokenInTokenA = soldTokens.mul(150).div(10000);
      const devFeeTokenInTokenB = raised.mul(250).div(10000);
      const liquidityAmountInTokenB = saleParams.privateSale
        ? 0
        : raised.mul(liquidity).div(1e4).sub(devFeeTokenInTokenB);
      const liquidityAmountInTokenA = saleParams.privateSale
        ? 0
        : liquidityAmountInTokenB.mul(listingRate).div(decimalForTokenACalculation);

      const treasuryBNB0 = await treasury.getBalance();
      const treasuryTokenBalance0 = await partnerToken.balanceOf(treasury.address);
      const aliceTokenBalance0 = await partnerToken.balanceOf(alice.address);
      const deadBalance0 = await partnerToken.balanceOf("0x000000000000000000000000000000000000dEaD");
      await sale.connect(alice).finalize();
      const treasuryBNB1 = await treasury.getBalance();
      const deadBalance1 = await partnerToken.balanceOf("0x000000000000000000000000000000000000dEaD");
      const treasuryTokenBalance1 = await partnerToken.balanceOf(treasury.address);
      const aliceTokenBalance1 = await partnerToken.balanceOf(alice.address);

      // privateSale, refund
      // privateSale, burn
      expect(treasuryTokenBalance1.sub(treasuryTokenBalance0)).to.be.equal(devFeeTokenInTokenA);
      expect(aliceTokenBalance1.sub(aliceTokenBalance0)).to.be.equal(
        totalTokens.sub(soldTokens).sub(liquidityAmountInTokenA).sub(devFeeTokenInTokenA),
      );

      // consider decimal diff and listing rate accuracy
      expect(treasuryBNB1.sub(treasuryBNB0))
        .to.be.equal(devFeeTokenInTokenB)
        .to.be.equal(
          treasuryTokenBalance1.sub(treasuryTokenBalance0).mul(1e10).mul(1e9).div(presaleRate).div(150).mul(250),
        );

      const bobToken0 = await partnerToken.balanceOf(bob.address);
      await sale.connect(bob).withdraw();
      const bobToken1 = await partnerToken.balanceOf(bob.address);
      expect(bobToken1.sub(bobToken0)).to.be.equal(soldTokens);
    });

    it("finalize and launch (publicSale, burn)", async () => {
      saleParams.privateSale = false;
      saleParams.burn = true;

      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await sale.connect(alice).addToWhitelist(fakeUsers);

      const raised = soft;
      await setNextBlockTimestamp(startTime);
      await sale.connect(bob).deposit(0, { value: raised });

      const totalTokens = await sale.totalTokens();
      // 1.5% in TokenA, 2.5% in TokenB devcut
      // liqudity percentage
      const decimalForTokenACalculation = ethers.utils.parseUnits("1", 18 + 10 - (await partnerToken.decimals()));
      const soldTokens = raised.mul(presaleRate).div(decimalForTokenACalculation);
      const devFeeTokenInTokenA = soldTokens.mul(150).div(10000);
      const devFeeTokenInTokenB = raised.mul(250).div(10000);
      const liquidityAmountInTokenB = saleParams.privateSale
        ? 0
        : raised.mul(liquidity).div(1e4).sub(devFeeTokenInTokenB);
      const liquidityAmountInTokenA = saleParams.privateSale
        ? 0
        : liquidityAmountInTokenB.mul(listingRate).div(decimalForTokenACalculation);

      const treasuryBNB0 = await treasury.getBalance();
      const treasuryTokenBalance0 = await partnerToken.balanceOf(treasury.address);
      const aliceTokenBalance0 = await partnerToken.balanceOf(alice.address);
      const deadBalance0 = await partnerToken.balanceOf("0x000000000000000000000000000000000000dEaD");
      await sale.connect(alice).finalize();
      const treasuryBNB1 = await treasury.getBalance();
      const deadBalance1 = await partnerToken.balanceOf("0x000000000000000000000000000000000000dEaD");
      const treasuryTokenBalance1 = await partnerToken.balanceOf(treasury.address);
      const aliceTokenBalance1 = await partnerToken.balanceOf(alice.address);

      // publicSale, burn
      expect(treasuryTokenBalance1.sub(treasuryTokenBalance0)).to.be.equal(devFeeTokenInTokenA);
      expect(deadBalance1.sub(deadBalance0)).to.be.equal(
        totalTokens.sub(soldTokens).sub(liquidityAmountInTokenA).sub(devFeeTokenInTokenA),
      );

      // consider decimal diff and listing rate accuracy
      expect(treasuryBNB1.sub(treasuryBNB0))
        .to.be.equal(devFeeTokenInTokenB)
        .to.be.equal(
          treasuryTokenBalance1.sub(treasuryTokenBalance0).mul(1e10).mul(1e9).div(presaleRate).div(150).mul(250),
        );

      const bobToken0 = await partnerToken.balanceOf(bob.address);
      await sale.connect(bob).withdraw();
      const bobToken1 = await partnerToken.balanceOf(bob.address);
      expect(bobToken1.sub(bobToken0)).to.be.equal(soldTokens);
    });

    it("finalize and launch (publicSale, refund)", async () => {
      saleParams.privateSale = false;
      saleParams.burn = false;

      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await sale.connect(alice).addToWhitelist(fakeUsers);

      const raised = soft;
      await setNextBlockTimestamp(startTime);
      await sale.connect(bob).deposit(0, { value: raised });

      const totalTokens = await sale.totalTokens();
      // 1.5% in TokenA, 2.5% in TokenB devcut
      // liqudity percentage
      const decimalForTokenACalculation = ethers.utils.parseUnits("1", 18 + 10 - (await partnerToken.decimals()));
      const soldTokens = raised.mul(presaleRate).div(decimalForTokenACalculation);
      const devFeeTokenInTokenA = soldTokens.mul(150).div(10000);
      const devFeeTokenInTokenB = raised.mul(250).div(10000);
      const liquidityAmountInTokenB = saleParams.privateSale
        ? 0
        : raised.mul(liquidity).div(1e4).sub(devFeeTokenInTokenB);
      const liquidityAmountInTokenA = saleParams.privateSale
        ? 0
        : liquidityAmountInTokenB.mul(listingRate).div(decimalForTokenACalculation);

      const treasuryBNB0 = await treasury.getBalance();
      const treasuryTokenBalance0 = await partnerToken.balanceOf(treasury.address);
      const aliceTokenBalance0 = await partnerToken.balanceOf(alice.address);
      const deadBalance0 = await partnerToken.balanceOf("0x000000000000000000000000000000000000dEaD");
      await sale.connect(alice).finalize();
      const treasuryBNB1 = await treasury.getBalance();
      const deadBalance1 = await partnerToken.balanceOf("0x000000000000000000000000000000000000dEaD");
      const treasuryTokenBalance1 = await partnerToken.balanceOf(treasury.address);
      const aliceTokenBalance1 = await partnerToken.balanceOf(alice.address);

      // publicSale, refund
      expect(treasuryTokenBalance1.sub(treasuryTokenBalance0)).to.be.equal(devFeeTokenInTokenA);
      expect(aliceTokenBalance1.sub(aliceTokenBalance0)).to.be.equal(
        totalTokens.sub(soldTokens).sub(liquidityAmountInTokenA).sub(devFeeTokenInTokenA),
      );

      // consider decimal diff and listing rate accuracy
      expect(treasuryBNB1.sub(treasuryBNB0))
        .to.be.equal(devFeeTokenInTokenB)
        .to.be.equal(
          treasuryTokenBalance1.sub(treasuryTokenBalance0).mul(1e10).mul(1e9).div(presaleRate).div(150).mul(250),
        );

      const bobToken0 = await partnerToken.balanceOf(bob.address);
      await sale.connect(bob).withdraw();
      const bobToken1 = await partnerToken.balanceOf(bob.address);
      expect(bobToken1.sub(bobToken0)).to.be.equal(soldTokens);
    });
  });

  describe("Cancel Sale", async () => {
    it("only admin can cancel the sale", async () => {
      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await expect(sale.connect(bob).cancel()).to.be.revertedWith("Caller isnt an admin");
      await sale.connect(alice).cancel();
    });

    it("cannot deposit if sale is canceled", async () => {
      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await sale.cancel();
      await setNextBlockTimestamp(startTime);
      await mineBlock();

      await expect(sale.connect(bob).deposit(0, { value: ethers.utils.parseEther("1") })).to.be.revertedWith(
        "Sale is canceled",
      );
    });
  });

  describe("Update SaleParms", async () => {
    it("cannot update the SaleParms by the partner", async () => {
      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);
      await expect(sale.connect(alice).configure({ ...saleParams, start: startTime, end: endTime })).to.be.revertedWith(
        "sale update not approved",
      );
    });

    it("can update the SaleParms if the partner is approved by the owner", async () => {
      const startTime = (await latest()).toNumber() + 86400;
      const endTime = startTime + 3600;
      const sale = await createSaleContract(startTime, endTime);

      // approve the SaleParams update
      expect(await settings.isValidSaleUpdateApprover(approver.address)).to.be.false;
      await settings.setSaleUpdateApprover(approver.address, true);
      expect(await settings.isValidSaleUpdateApprover(approver.address)).to.be.true;

      expect(await sale.isSaleUpdateApproved()).to.be.false;
      await router.connect(approver).setSaleUpdateApprove(alice.address);
      expect(await sale.isSaleUpdateApproved()).to.be.true;

      // update SaleParams
      await sale.connect(alice).configure({ ...saleParams, start: startTime + 100, end: endTime });
      expect(await sale.start()).to.be.equal(startTime + 100);
      expect(await sale.end()).to.be.equal(endTime);

      // revert if try to update the sale param again
      await expect(sale.connect(alice).configure({ ...saleParams, start: startTime, end: endTime })).to.be.revertedWith(
        "sale update not approved",
      );
    });
  });
});
