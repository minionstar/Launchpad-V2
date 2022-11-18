// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IReflexRouter01 {
  enum SaleStatus {
    Prepared,
    Launched,
    Canceled,
    Raised,
    Failed
  }

  function onStatusChange(SaleStatus status) external;

  // Reflex interface
  function launchingFeeInTokenA() external view returns (uint256);

  function launchingFeeInTokenB() external view returns (uint256);

  function earlyWithdrawPenalty() external view returns (uint256);
}
