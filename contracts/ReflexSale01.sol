// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "contracts/interfaces/uniswap/IUniswapV2Router02.sol";
import "contracts/interfaces/uniswap/IUniswapV2Factory.sol";
import "contracts/interfaces/IReflexRouter01.sol";
import "contracts/interfaces/IReflexSale01.sol";
import "contracts/interfaces/IERC20Extended.sol";

import "contracts/libraries/TransferHelper.sol";

import "contracts/Whitelist.sol";

import "hardhat/console.sol";

/**
 * @notice A Reflex Sale
 */
contract ReflexSale01 is Initializable, ContextUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using SafeMathUpgradeable for uint256;

  uint256 public constant ACCURACY = 1e10;

  /// @notice The ReflexRouter owner
  address public owner;

  /// @notice The person running the sale
  address public runner;

  /// @notice The ReflexRouter
  IReflexRouter01 public reflexRouter;

  /// @notice The address of the whitelist implementation
  address public whitelistImpl;

  /// @notice The address of the proxy admin
  address public proxyAdmin;

  /// @notice The address of the reflexRouter
  IUniswapV2Router02 public exchangeRouter;

  /// @notice The address of the LP token
  address public lpToken;

  IReflexSale01.SaleParams public saleParams;

  /**
   * @notice Configuration
   */
  address public tokenA; // The token that the sale is selling
  address public tokenB; // The token that the pay to buy sale tokens
  uint256 public softCap; // The soft cap of BNB or tokenB
  uint256 public hardCap; // The hard cap of BNB or tokenB
  uint256 public min; // The minimum amount of contributed BNB or tokenB
  uint256 public max; // The maximum amount of contributed BNB or tokenB
  uint256 public presaleRate; // How many tokenA is given per BNB or tokenB: no decimal consideration e.g. 1e9(= ACCURACY / 10) means 1 tokenB = 0.1 tokenA,
  uint256 public listingRate; // How many tokenA is worth 1 BNB or 1 tokenB when we list: no decimal consideration
  uint256 public liquidity; // What perecentage of raised funds will be allocated for liquidity (100 = 1% - i.e. out of 10,000)
  uint256 public start; // The start date in UNIX seconds of the presale
  uint256 public end; // The end date in UNIX seconds of the presale
  // uint256 public unlockTime; // The time in seconds that the liquidity lock should last
  address public whitelist; // Whitelist contract address
  bool public burn; // Whether or not to burn remaining sale tokens (if false, refunds the sale runner)
  bool public privateSale; // Whether or not the private sale
  string public metaInfo;
  address public treasury; // Treasury address where the fee will be sent

  /**
   * @notice State Settings
   */
  bool public prepared; // True when the sale has been prepared to start by the owner
  bool public launched; // Whether the sale has been finalized and launched; inited to false by default
  bool public canceled; // This sale is canceled

  /**
   * @notice Current Status - These are modified after a sale has been setup and is running
   */
  uint256 public totalTokens; // Total tokens determined for the sale
  uint256 public saleAmount; // How many tokens are on sale
  uint256 public liquidityAmount; // How many tokens are allocated for liquidity
  uint256 public raised; // How much BNB has been raised
  mapping(address => uint256) public _deposited; // A mapping of addresses to the amount of BNB they deposited
  bool public isSaleUpdateApproved; // Whether or not the sale praram update is approved
  bool public isWhitelistEnabled; // Whether or not the whitelist feature is enabled

  /********************** Modifiers **********************/

  /**
   * @notice Checks if the caller is the Reflex owner, Sale owner or the reflexRouter itself
   */
  modifier isAdmin() {
    require(
      address(reflexRouter) == _msgSender() || owner == _msgSender() || runner == _msgSender(),
      "Caller isnt an admin"
    );
    _;
  }

  /**
   * @notice Checks if the sale is running
   */
  modifier isRunning() {
    require(running(), "Sale isn't running!");
    _;
  }

  modifier isSuccessful() {
    require(successful(), "Sale isn't successful!");
    _;
  }

  /**
   * @notice Checks if the sale is finished
   */
  modifier isEnded() {
    require(ended(), "Sale hasnt ended");
    _;
  }

  /**
   * @notice Checks if the sale has been finalized
   */
  modifier isLaunched() {
    require(launched, "Sale hasnt been launched yet");
    _;
  }

  function initialize(
    address _reflexRouter,
    address _owner,
    address _runner,
    address _tokenA,
    address _tokenB,
    address _exchangeRouter,
    address _whitelistImpl,
    address _proxyAdmin,
    // uint256 _unlockTime,
    string memory _metaInfo,
    address _treasury
  ) external initializer {
    __Context_init();

    // Set the onwer of teh sale to be the owner of the deployer
    reflexRouter = IReflexRouter01(_reflexRouter);
    owner = _owner;
    runner = _runner;
    tokenA = _tokenA;
    tokenB = _tokenB;

    // Let the reflexRouter control payments!
    TransferHelper.safeApprove(_tokenA, _reflexRouter, type(uint256).max);

    exchangeRouter = IUniswapV2Router02(_exchangeRouter);
    whitelistImpl = _whitelistImpl;
    proxyAdmin = _proxyAdmin;
    // unlockTime = _unlockTime;
    metaInfo = _metaInfo;
    treasury = _treasury;
  }

  /**
   * @notice Configure a reflex sale
   */
  function configure(IReflexSale01.SaleParams memory params) external isAdmin {
    if (msg.sender == runner) {
      require(isSaleUpdateApproved, "sale update not approved");
      isSaleUpdateApproved = false;
    }

    // store the sale params
    saleParams = params;

    // set the sale params
    softCap = params.soft;
    hardCap = params.hard;
    min = params.min;
    max = params.max;
    presaleRate = params.presaleRate;
    listingRate = params.listingRate;
    if (!params.privateSale) {
      liquidity = params.liquidity;
    }
    start = params.start;
    end = params.end;
    // TODO: Add a way for the runner to specify this
    burn = params.burn;
    privateSale = params.privateSale;

    saleAmount = getTokenAAmount(hardCap, presaleRate);
    if (!privateSale) {
      liquidityAmount = getTokenAAmount(hardCap, listingRate).mul(liquidity).div(1e4);
    }
    totalTokens = saleAmount.add(liquidityAmount);

    if (whitelist == address(0) && params.whitelisted) {
      whitelist = address(new TransparentUpgradeableProxy(whitelistImpl, proxyAdmin, new bytes(0)));
      Whitelist(whitelist).initialize();
      // If the whitelist exists when a new sale is created, enable the whitelist.
      if (address(reflexRouter) == _msgSender()) {
        isWhitelistEnabled = true;
      }
    } else if (whitelist != address(0) && !params.whitelisted) {
      whitelist = address(0);
    }
  }

  /**
   * @notice If the presale isn't running will direct any received payments straight to the reflexRouter
   */
  receive() external payable {
    require(tokenB == address(0));
    _deposit(_msgSender(), msg.value);
  }

  function setSaleUpdateApproved() external {
    require(address(reflexRouter) == _msgSender(), "only reflex router");

    isSaleUpdateApproved = true;
  }

  function deposited() external view returns (uint256) {
    return accountsDeposited(_msgSender());
  }

  function accountsDeposited(address account) public view returns (uint256) {
    return _deposited[account];
  }

  function userTokenAAmount(address account) public view returns (uint256) {
    uint256 userTokenBDeposit = accountsDeposited(account);

    return getTokenAAmount(userTokenBDeposit, presaleRate);
  }

  function setRunner(address _runner) external isAdmin {
    runner = _runner;
  }

  function getRunner() external view returns (address) {
    return runner;
  }

  function isWhitelisted() external view returns (bool) {
    return whitelist != address(0);
  }

  function userWhitelisted() external view returns (bool) {
    return _userWhitelisted(_msgSender());
  }

  function _userWhitelisted(address account) public view returns (bool) {
    if (whitelist != address(0)) {
      return Whitelist(whitelist).isWhitelisted(account);
    } else {
      return false;
    }
  }

  function enableWhitelist() external isAdmin {
    if (!isWhitelistEnabled) {
      isWhitelistEnabled = true;
    }
  }

  function disableWhitelist() external isAdmin {
    if (isWhitelistEnabled) {
      isWhitelistEnabled = false;
    }
  }

  function resetWhitelist() external isAdmin {
    if (whitelist != address(0)) {
      whitelist = address(new TransparentUpgradeableProxy(whitelistImpl, proxyAdmin, new bytes(0)));
      Whitelist(whitelist).initialize();
    }
  }

  function setWhitelist() external isAdmin {
    require(block.timestamp < start, "Sale started");
    require(whitelist == address(0), "There is already a whitelist!");
    whitelist = address(new TransparentUpgradeableProxy(whitelistImpl, proxyAdmin, new bytes(0)));
    Whitelist(whitelist).initialize();
  }

  function removeWhitelist() external isAdmin {
    require(block.timestamp < start, "Sale started");
    require(whitelist != address(0), "There isn't a whitelist set");
    whitelist = address(0);
  }

  function addToWhitelist(address[] memory users) external isAdmin {
    require(block.timestamp < end, "Sale ended");
    Whitelist(whitelist).addToWhitelist(users);
  }

  function removeFromWhitelist(address[] memory addrs) external isAdmin {
    require(block.timestamp < start, "Sale started");
    Whitelist(whitelist).removeFromWhitelist(addrs);
  }

  function cancel() external isAdmin {
    require(!launched, "Sale has launched");
    end = block.timestamp;
    canceled = true;

    reflexRouter.onStatusChange(IReflexRouter01.SaleStatus.Canceled);
  }

  /**
   * @notice For users to deposit into the sale
   * @dev This entitles _msgSender() to (amount * presaleRate) after a successful sale
   */
  function deposit(uint256 amount) external payable {
    if (tokenB == address(0)) {
      _deposit(_msgSender(), msg.value);
    } else {
      TransferHelper.safeTransferFrom(tokenB, msg.sender, address(this), amount);
      _deposit(_msgSender(), amount);
    }
  }

  /**
   * @notice
   */
  function _deposit(address user, uint256 amount) internal {
    require(!canceled, "Sale is canceled");
    require(running(), "Sale isn't running!");
    require(canStart(), "Token balance isn't topped up!");
    require(amount >= min, "Amount must be above min");
    require(amount <= max, "Amount must be below max");

    require(raised.add(amount) <= hardCap, "Cant exceed hard cap");
    require(_deposited[user].add(amount) <= max, "Cant deposit more than the max");
    if (whitelist != address(0) && isWhitelistEnabled) {
      require(Whitelist(whitelist).isWhitelisted(user), "User not whitelisted");
    }

    if (raised < softCap && raised.add(amount) >= softCap) {
      reflexRouter.onStatusChange(IReflexRouter01.SaleStatus.Raised);
    }

    _deposited[user] = _deposited[user].add(amount);
    raised = raised.add(amount);
  }

  /**
   * @notice Finishes the sale, and if successful launches to PancakeSwap
   */
  function finalize() external isAdmin isSuccessful {
    end = block.timestamp;

    // First take the developer cut
    uint256 devTokenB = raised.mul(reflexRouter.launchingFeeInTokenB()).div(1e4);
    uint256 devTokenA = getTokenAAmount(raised, presaleRate).mul(reflexRouter.launchingFeeInTokenA()).div(1e4);
    if (tokenB == address(0)) {
      TransferHelper.safeTransferETH(treasury, devTokenB);
    } else {
      TransferHelper.safeTransfer(tokenB, treasury, devTokenB);
    }
    TransferHelper.safeTransfer(tokenA, treasury, devTokenA);

    uint256 liquidityTokenB;
    if (!privateSale) {
      // Find a percentage (i.e. 50%) of the leftover 99% liquidity
      // Dev fee is cut from the liquidity
      liquidityTokenB = raised.mul(liquidity).div(1e4).sub(devTokenB);
      uint256 tokenAForLiquidity = getTokenAAmount(liquidityTokenB, listingRate);

      // Add the tokens and the BNB to the liquidity pool, satisfying the listing rate as the starting price point
      TransferHelper.safeApprove(tokenA, address(exchangeRouter), tokenAForLiquidity);

      if (tokenB == address(0)) {
        exchangeRouter.addLiquidityETH{value: liquidityTokenB}(
          tokenA,
          tokenAForLiquidity,
          0,
          0,
          _msgSender(),
          block.timestamp.add(300)
        );
        lpToken = IUniswapV2Factory(exchangeRouter.factory()).getPair(tokenA, exchangeRouter.WETH());
      } else {
        TransferHelper.safeApprove(tokenB, address(exchangeRouter), liquidityTokenB);
        exchangeRouter.addLiquidity(
          tokenA,
          tokenB,
          tokenAForLiquidity,
          liquidityTokenB,
          0,
          0,
          _msgSender(),
          block.timestamp.add(300)
        );
        lpToken = IUniswapV2Factory(exchangeRouter.factory()).getPair(tokenA, tokenB);
      }
    }

    // Send the sale runner the reamining BNB/tokens
    if (tokenB == address(0)) {
      TransferHelper.safeTransferETH(_msgSender(), raised.sub(liquidityTokenB).sub(devTokenB));
    } else {
      TransferHelper.safeTransfer(tokenB, _msgSender(), raised.sub(liquidityTokenB).sub(devTokenB));
    }

    // Send the remaining sale tokens
    uint256 soldTokens = getTokenAAmount(raised, presaleRate);
    uint256 remaining = IERC20Upgradeable(tokenA).balanceOf(address(this)) - soldTokens;
    if (!privateSale && burn) {
      TransferHelper.safeTransfer(tokenA, 0x000000000000000000000000000000000000dEaD, remaining);
    } else {
      TransferHelper.safeTransfer(tokenA, msg.sender, remaining);
    }

    launched = true;
    reflexRouter.onStatusChange(IReflexRouter01.SaleStatus.Launched);
  }

  /**
   * @notice For users to withdraw from a sale
   * @dev This entitles _msgSender() to (amount * presaleRate) after a successful sale
   */
  function withdraw() external isEnded {
    require(_deposited[_msgSender()] > 0, "User didnt partake");

    uint256 amount = _deposited[_msgSender()];
    _deposited[_msgSender()] = 0;

    // If the sale was successful, then we give the user their tokens only once the sale has been finalized and launched
    // Otherwise return to them the full amount of BNB/tokens that they pledged for this sale!
    if (successful()) {
      require(launched, "Sale hasnt finalized");
      uint256 tokens = getTokenAAmount(amount, presaleRate);
      TransferHelper.safeTransfer(tokenA, _msgSender(), tokens);
    } else if (failed()) {
      if (tokenB == address(0)) {
        payable(msg.sender).transfer(amount);
      } else {
        IERC20Upgradeable(tokenB).safeTransfer(msg.sender, amount);
      }
    }
  }

  /**
   * @notice For users to withdraw their deposited funds before the sale has been concluded
   * @dev This incurs a tax, where Reflex will take a cut of this tax
   */
  function earlyWithdraw() external {
    require(!canceled, "Sale is canceled");
    require(running(), "Sale isn't running!");
    require(canStart(), "Token balance isn't topped up!");

    uint256 amount = _deposited[msg.sender];
    _deposited[msg.sender] = _deposited[msg.sender] - amount;
    raised = raised.sub(amount);

    // The portion of the deposited tokens that will be taxed
    uint256 taxed = amount.mul(reflexRouter.earlyWithdrawPenalty()).div(1e4);
    uint256 returned = amount.sub(taxed);

    if (tokenB == address(0)) {
      payable(msg.sender).transfer(returned);
      payable(treasury).transfer(taxed);
    } else {
      IERC20Upgradeable(tokenB).safeTransfer(msg.sender, returned);
      IERC20Upgradeable(tokenB).safeTransfer(treasury, taxed);
    }
  }

  /**
   * @notice EMERGENCY USE ONLY: Lets the owner of the sale reclaim any stuck funds
   */
  function reclaim() external isAdmin {
    require(canceled, "Sale hasn't been canceled");
    TransferHelper.safeTransfer(tokenA, runner, IERC20Upgradeable(tokenA).balanceOf(address(this)));
  }

  /**
   * @notice Withdraws BNB from the contract
   */
  function emergencyWithdrawBNB() external payable {
    require(owner == _msgSender(), "Only owner");
    payable(owner).transfer(address(this).balance);
  }

  /**
   * @notice Withdraws tokens that are stuck
   */
  function emergencyWithdrawTokens(address _token) external payable {
    require(owner == _msgSender(), "Only owner");
    TransferHelper.safeTransfer(tokenA, owner, IERC20Upgradeable(tokenA).balanceOf(address(this)));
  }

  function successful() public view returns (bool) {
    return raised >= softCap;
  }

  function running() public view returns (bool) {
    return block.timestamp >= start && block.timestamp < end;
  }

  function ended() public view returns (bool) {
    return block.timestamp >= end || launched;
  }

  function failed() public view returns (bool) {
    return block.timestamp >= end || !successful();
  }

  function canStart() public view returns (bool) {
    return IERC20Upgradeable(tokenA).balanceOf(address(this)) >= totalTokens;
  }

  function getDecimals(address token) internal view returns (uint256) {
    return token == address(0) ? 18 : IERC20Extended(token).decimals();
  }

  function getTokenAAmount(uint256 tokenBAmount, uint256 rateOfTokenAInTokenB) public view returns (uint256) {
    return
      tokenBAmount.mul(rateOfTokenAInTokenB).mul(10**getDecimals(tokenA)).div(ACCURACY).div(10**getDecimals(tokenB));
  }

  function getTokenBAmount(uint256 tokenAAmount, uint256 rateOfTokenAInTokenB) public view returns (uint256) {
    return
      tokenAAmount.mul(ACCURACY).mul(10**getDecimals(tokenB)).div(rateOfTokenAInTokenB).div(10**getDecimals(tokenA));
  }

  function getSaleParams() external view returns (IReflexSale01.SaleParams memory) {
    return saleParams;
  }
}
