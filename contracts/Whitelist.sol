// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Whitelist is Initializable, OwnableUpgradeable {
  /// @notice Count of users participating in whitelisting
  uint256 public totalUsers;

  // Users list
  address[] internal userlist;
  mapping(address => uint256) internal indexOf;
  mapping(address => bool) internal inserted;

  /// @notice An event emitted when a user is added or removed. True: Added, False: Removed
  event AddedOrRemoved(bool added, address indexed user, uint256 timestamp);

  function initialize() external initializer {
    __Ownable_init();
  }

  /**
   * @notice Return the number of users
   */
  function usersCount() external view returns (uint256) {
    return userlist.length;
  }

  /**
   * @notice Add users to white list
   * @dev Only owner can do this operation
   * @param users List of user data
   */
  function addToWhitelist(address[] memory users) external onlyOwner {
    for (uint256 i = 0; i < users.length; i++) {
      address user = users[i];

      if (inserted[user] == false) {
        inserted[user] = true;
        indexOf[user] = userlist.length;
        userlist.push(user);
      }

      emit AddedOrRemoved(true, user, block.timestamp);
    }
    totalUsers = userlist.length;
  }

  /**
   * @notice Remove from white lsit
   * @dev Only owner can do this operation
   * @param addrs addresses to be removed
   */
  function removeFromWhitelist(address[] memory addrs) external onlyOwner {
    for (uint256 i = 0; i < addrs.length; i++) {
      // Ignore for non-existing users
      if (inserted[addrs[i]] == true) {
        delete inserted[addrs[i]];

        uint256 index = indexOf[addrs[i]];
        uint256 lastIndex = userlist.length - 1;
        address lastUser = userlist[lastIndex];

        indexOf[lastUser] = index;
        delete indexOf[addrs[i]];

        userlist[index] = lastUser;
        userlist.pop();

        emit AddedOrRemoved(false, addrs[i], block.timestamp);
      }
    }
    totalUsers = userlist.length;
  }

  /**
   * @notice Return whitelisted user info
   * @param _user user wallet address
   * @return user wallet, kyc status, max allocation
   */
  function isWhitelisted(address _user) external view returns (bool) {
    return inserted[_user];
  }
}
