// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
  constructor() ERC20("ERC2Mock", "ERC20Mock") {
    _mint(msg.sender, 10**30);
  }

  function decimals() public pure override returns (uint8) {
    return 9;
  }
}
