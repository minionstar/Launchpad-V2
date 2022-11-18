// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "contracts/interfaces/IReflexRouter01.sol";
import "contracts/interfaces/IReflexSale01.sol";
import "contracts/interfaces/IReflexSettings.sol";

import "contracts/ReflexSale01.sol";

import "hardhat/console.sol";

contract ReflexRouter01 is Initializable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using SafeMathUpgradeable for uint256;

  enum SaleStatus {
    Prepared,
    Launched,
    Canceled,
    Raised,
    Failed
  }

  /// @notice Reflex Settings
  IReflexSettings public reflexSettings;

  /// @notice Treasury address
  address public treasury;

  /// @notice A mapping of sale owners to the sales
  mapping(address => ReflexSale01) public sales;

  /// @notice A mapping of wallet addresses to a flag for whether they paid the fee
  mapping(address => bool) public feePaid;

  /// @notice Emitted when a new sale is created
  event SaleCreated(address indexed runner, address indexed sale);

  /// @notice Emitted when a new sale is created
  event StatusChanged(address indexed sale, SaleStatus indexed status);

  /**
   * @notice The initializer for the router
   */
  function initialize(IReflexSettings _settings) external initializer {
    __Ownable_init();

    reflexSettings = _settings;
    treasury = reflexSettings.treasury();
  }

  /**
   * @notice Forward all received BNB to the owner of the Reflex Router
   */
  receive() external payable {}

  function setReflexSettings(IReflexSettings _settings) external onlyOwner {
    reflexSettings = _settings;
  }

  /**
   * @notice Callback from reflex sale for event emission
   */
  function onStatusChange(SaleStatus status) external {
    emit StatusChanged(_msgSender(), status);
  }

  /**
   * @notice Reset fee paid status of an account
   */
  function resetFee(address account) external onlyOwner {
    feePaid[account] = false;
  }

  /**
   * @notice Pay the fee in BNB
   */
  function payFee() external payable {
    uint256 feeAmount = reflexSettings.listingFee();
    require(msg.value == feeAmount, "BNB fee incorrect");

    payable(treasury).transfer(msg.value);
    feePaid[_msgSender()] = true;
  }

  function createSale(
    address token,
    address fundToken,
    IReflexSale01.SaleParams memory saleParams
  ) external payable {
    // Validates the sale config
    reflexSettings.validate(
      saleParams.soft,
      saleParams.hard,
      saleParams.liquidity,
      saleParams.start,
      saleParams.end
      // saleParams.unlockTime,
    );

    // If the person creating teh sale hasn't paid the fee, then this call needs to pay the appropriate BNB.
    if (!feePaid[_msgSender()]) {
      require(msg.value == reflexSettings.listingFee(), "No paying the listing fee");
      payable(treasury).transfer(msg.value);
    }

    ReflexSale01 newSale = ReflexSale01(
      payable(
        address(new TransparentUpgradeableProxy(reflexSettings.saleImpl(), reflexSettings.proxyAdmin(), new bytes(0)))
      )
    );
    newSale.initialize(
      payable(address(this)),
      owner(),
      _msgSender(),
      token,
      fundToken,
      reflexSettings.exchangeRouter(),
      reflexSettings.whitelistImpl(),
      reflexSettings.proxyAdmin(),
      // saleParams.unlockTime,
      saleParams.metaInfo,
      reflexSettings.treasury()
    );
    newSale.configure(saleParams);
    sales[_msgSender()] = newSale;

    // Transfer the tokens from the partner
    IERC20Upgradeable(token).safeTransferFrom(_msgSender(), address(this), newSale.totalTokens());

    // Transfer tokens to the sale contract
    IERC20Upgradeable(token).safeTransfer(address(newSale), IERC20Upgradeable(token).balanceOf(address(this)));

    /// Finally, add a fee back so the user can't just keep creasting new sale for free
    feePaid[_msgSender()] = false;

    // Emit an event
    emit SaleCreated(_msgSender(), address(newSale));
  }

  /**
   * @notice To be called by a sales "finalize()" function only
   */
  function launched(
    address payable _sale,
    uint256 _raised,
    uint256 _participants
  ) external {
    require(address(sales[_msgSender()]) == _sale, "Must be owner of sale");

    ReflexSale01 sale = ReflexSale01(_sale);
    require(sale.launched(), "Sale must have launched!");
    reflexSettings.launch(_sale, _raised, _participants);
  }

  /**
   * @notice Returns the sale of the caller
   */
  function getSale()
    external
    view
    returns (
      address,
      bool,
      address
    )
  {
    return getSaleByOwner(_msgSender());
  }

  /**
   * @notice Returns the sale of a given owner
   */
  function getSaleByOwner(address owner)
    public
    view
    returns (
      address,
      bool,
      address
    )
  {
    return (owner, address(sales[owner]) != address(0), address(sales[owner]));
  }

  /**
   * @notice Returns the listing fee
   */
  function listingFee() external view returns (uint256) {
    return reflexSettings.listingFee();
  }

  /**
   * @notice Returns the launching fee in the raised token
   */
  function launchingFeeInTokenB() external view returns (uint256) {
    return reflexSettings.launchingFeeInTokenB();
  }

  /**
   * @notice Returns the launching fee in the partner token
   */
  function launchingFeeInTokenA() external view returns (uint256) {
    return reflexSettings.launchingFeeInTokenA();
  }

  /**
   * @notice Approve the sale param update of the runner's sale
   */
  function setSaleUpdateApprove(address _runner) external {
    require(reflexSettings.isValidSaleUpdateApprover(msg.sender), "only reflex approver");

    // approve the sale param update
    sales[_runner].setSaleUpdateApproved();
  }

  /**
   * @notice Returns the early withdrawal penalty
   */
  function earlyWithdrawPenalty() external view returns (uint256) {
    return reflexSettings.earlyWithdrawPenalty();
  }

  /**
   * @notice Withdraws BNB from the contract
   */
  function withdrawBNB(uint256 amount) public onlyOwner {
    if (amount == 0) {
      payable(owner()).transfer(address(this).balance);
    } else {
      payable(owner()).transfer(amount);
    }
  }
}
