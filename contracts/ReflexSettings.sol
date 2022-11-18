// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "contracts/interfaces/uniswap/IUniswapV2Router02.sol";

contract ReflexSettings is Initializable, OwnableUpgradeable {
  using SafeMathUpgradeable for uint256;

  /************************ Sale Settings  ***********************/

  /// @notice The flat fee in BNB (1e18 = 1 BNB)
  uint256 public listingFee;

  /// @notice  The percentage fee for raised funds in the raised token (only applicable for successful sales) (100 = 1%)
  uint256 public launchingFeeInTokenB;

  /// @notice  The percentage fee for raised funds in the partner token (only applicable for successful sales) (100 = 1%)
  uint256 public launchingFeeInTokenA;

  /// @notice  The minimum liquidity percentage (5000 = 50%)
  uint256 public minLiquidityPercentage;

  /// @notice  The ratio of soft cap to hard cap, i.e. 50% means soft cap must be at least 50% of the hard cap
  uint256 public minCapRatio;

  // /// @notice  The minimum amount of time in seconds before liquidity can be unlocked
  // uint256 public minUnlockTimeSeconds;

  /// @notice  The minimum amount of time in seconds a sale has to run for
  uint256 public minSaleTime;

  /// @notice  If set, the maximum amount of time a sale has to run for
  uint256 public maxSaleTime;

  // The early withdraw penalty for users wishing to reclaim deposited BNB/tokens (2 dp precision)
  uint256 public earlyWithdrawPenalty;

  /************************ Stats  ***********************/

  /// @notice Total amount of BNB raised
  uint256 public totalRaised;

  /// @notice Total amount of launched projects
  uint256 public totalProjects;

  /// @notice Total amount of people partcipating
  uint256 public totalParticipants;

  /// @notice List of sales launch status
  mapping(address => bool) public launched;

  /// @notice Reflex Router address
  address public reflexRouter;

  /// @notice The address of the router; this can be pancake or uniswap depending on the network
  IUniswapV2Router02 public exchangeRouter;

  /// @notice Reflex Sale Implementation
  address public saleImpl;

  /// @notice Whitelist Implementation
  address public whitelistImpl;

  /// @notice Proxy admin
  address public proxyAdmin;

  /// @notice Treasury address
  address public treasury;

  /// @notice Sale Update Approver list
  address[] public saleUpdateApprovers;

  /// @notice Approver -> Bool
  mapping(address => bool) public isValidSaleUpdateApprover;

  /**
   * @notice The constructor for the router
   */
  function initialize(
    IUniswapV2Router02 _exchangeRouter,
    address _proxyAdmin,
    address _saleImpl,
    address _whitelistImpl,
    address _treasury
  ) external initializer {
    __Ownable_init();

    exchangeRouter = _exchangeRouter;
    saleImpl = _saleImpl;
    whitelistImpl = _whitelistImpl;
    proxyAdmin = _proxyAdmin;
    treasury = _treasury;

    listingFee = 1e18; // 1 BNB
    launchingFeeInTokenB = 2_50; // 2.5% BNB
    launchingFeeInTokenA = 1_50; // 1.5% Token
    minLiquidityPercentage = 50_00; // 50%
    minCapRatio = 50_00; // 50%
    // minUnlockTimeSeconds = 0;
    minSaleTime = 0 hours;
    maxSaleTime = 0;
    earlyWithdrawPenalty = 10_00; // 10%
  }

  /**
   * @notice Validates the parameters against the data contract
   */
  function validate(
    uint256 soft,
    uint256 hard,
    uint256 liquidity,
    uint256 start,
    uint256 end // uint256 unlockTime
  ) external view {
    require(liquidity >= minLiquidityPercentage, "Liquidity percentage below minimum");
    require(soft.mul(1e5).div(hard).div(10) >= minCapRatio, "Soft cap too low compared to hard cap");
    require(start > block.timestamp, "Sale time cant start in the past!");
    require(end > start, "Sale end has to be in the future from sale start");
    require(maxSaleTime == 0 || end.sub(start) < maxSaleTime, "Sale time too long");
    require(end.sub(start).add(1) >= minSaleTime, "Sale time too short");
    // require(unlockTime >= minUnlockTimeSeconds, "Minimum unlock time is too low");
  }

  /**
   * @notice SETTERS
   */
  function setExchangeRouter(IUniswapV2Router02 _exchangeRouter) external onlyOwner {
    exchangeRouter = _exchangeRouter;
  }

  function setSaleImpl(address _saleImpl) external onlyOwner {
    saleImpl = _saleImpl;
  }

  function setWhitelistImpl(address _whitelistImpl) external onlyOwner {
    whitelistImpl = _whitelistImpl;
  }

  function setReflexRouter(address _reflexRouter) external onlyOwner {
    reflexRouter = _reflexRouter;
  }

  function setProxyAdmin(address _proxyAdmin) external onlyOwner {
    proxyAdmin = _proxyAdmin;
  }

  function setTreasury(address _treasury) external onlyOwner {
    treasury = _treasury;
  }

  function setListingFee(uint256 _listingFee) external onlyOwner {
    listingFee = _listingFee;
  }

  function setLaunchingFeeInTokenB(uint256 _launchingFee) external onlyOwner {
    launchingFeeInTokenB = _launchingFee;
  }

  function setLaunchingFeeInTokenA(uint256 _launchingFee) external onlyOwner {
    launchingFeeInTokenA = _launchingFee;
  }

  function setMinimumLiquidityPercentage(uint256 _liquidityPercentage) external onlyOwner {
    minLiquidityPercentage = _liquidityPercentage;
  }

  function setMinimumCapRatio(uint256 _minimumCapRatio) external onlyOwner {
    minCapRatio = _minimumCapRatio;
  }

  // function setMinimumUnlockTime(uint256 _minimumLiquidityUnlockTime) external onlyOwner {
  //   minUnlockTimeSeconds = _minimumLiquidityUnlockTime;
  // }

  function setMinimumSaleTime(uint256 _minSaleTime) external onlyOwner {
    minSaleTime = _minSaleTime;
  }

  function setMaximumSaleTime(uint256 _maxSaleTime) external onlyOwner {
    maxSaleTime = _maxSaleTime;
  }

  function setTotalRaised(uint256 _amount) external onlyOwner {
    totalRaised = _amount;
  }

  function setTotalProjects(uint256 _amount) external onlyOwner {
    totalProjects = _amount;
  }

  function setTotalParticipants(uint256 _amount) external onlyOwner {
    totalParticipants = _amount;
  }

  /**
   * @notice Reflect launch status
   */
  function launch(
    address sale,
    uint256 raised,
    uint256 participants
  ) external {
    require(_msgSender() == reflexRouter, "Can only be called by the router");
    require(!launched[sale], "You've already called this!");
    launched[sale] = true;

    totalProjects = totalProjects.add(1);
    totalRaised = totalRaised.add(raised);
    totalParticipants = totalParticipants.add(participants);
  }

  function setSaleUpdateApprover(address _approver, bool _allowance) external onlyOwner {
    if (_allowance) {
      bool isNewApprover = true;
      for (uint256 i; i < saleUpdateApprovers.length; i++) {
        if (saleUpdateApprovers[i] == _approver) {
          isNewApprover = false;
          break;
        }
      }

      if (isNewApprover) {
        saleUpdateApprovers.push(_approver);
      }
    }

    isValidSaleUpdateApprover[_approver] = _allowance;
  }
}
