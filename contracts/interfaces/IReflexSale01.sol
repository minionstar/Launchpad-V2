// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IReflexSale01 {
  struct SaleParams {
    uint256 soft;
    uint256 hard;
    uint256 min;
    uint256 max;
    uint256 presaleRate;
    uint256 listingRate;
    uint256 liquidity;
    uint256 start;
    uint256 end;
    // uint256 unlockTime;
    bool whitelisted;
    bool burn;
    bool privateSale;
    string metaInfo;
  }

  function launched() external view returns (bool);
}
