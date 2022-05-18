// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../libraries/FarmStorage.sol";

contract UpdateStartBlockInit {
  function init(uint256 startBlock) external {
    FarmStorage.Layout storage s = FarmStorage.layout();
    s.startBlock = startBlock;
    for (uint256 i; i < s.poolInfo.length; i++) {
      s.poolInfo[i].lastRewardBlock = startBlock;
    }
  }
}
