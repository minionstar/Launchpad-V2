// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IReflexSettings {
  /************************ Sale Settings  ***********************/
  function listingFee() external view returns (uint256);

  function launchingFeeInTokenA() external view returns (uint256);

  function launchingFeeInTokenB() external view returns (uint256);

  function earlyWithdrawPenalty() external view returns (uint256);

  /************************ Setters  ***********************/

  function exchangeRouter() external view returns (address);

  function saleImpl() external view returns (address);

  function proxyAdmin() external view returns (address);

  function treasury() external view returns (address);

  function whitelistImpl() external view returns (address);

  function launch(
    address token,
    uint256 raised,
    uint256 participants
  ) external;

  function validate(
    uint256 soft,
    uint256 hard,
    uint256 liquidity,
    uint256 start,
    uint256 end
  ) external view;

  function isValidSaleUpdateApprover(address approver) external view returns (bool);
}
