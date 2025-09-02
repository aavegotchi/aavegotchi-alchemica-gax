pragma solidity 0.8.13;

import "./TestSetupFarm.t.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract FarmTest is TestSetupFarm {
  using Strings for uint256;

  function testInit() public {
    assertEq(farm.startBlock(), startBlock);
    assertEq(address(farm.rewardToken()), address(rewardToken));
  }

  function testAdd(uint256 numTokens) public {
    vm.assume(numTokens > 0 && numTokens <= 20);
    uint256 totalAllocPoint;

    //Only owner check
    vm.prank(address(user1));
    vm.expectRevert("LibDiamond: Must be contract owner");
    farm.add(1, lpTokens[0], true);

    for (uint256 i = 0; i < numTokens; i++) {
      farm.add(i, lpTokens[i], true);
      totalAllocPoint += i;
    }
    assertEq(farm.totalAllocPoint(), totalAllocPoint);
    assertEq(farm.poolLength(), numTokens);
    for (uint256 i = 0; i < numTokens; i++) {
      PoolInfo memory poolInfo = farm.poolInfo(i);
      assertEq(address(poolInfo.lpToken), address(lpTokens[i]));
      assertEq(poolInfo.allocPoint, i);
      assertEq(poolInfo.lastRewardBlock, startBlock);
      assertEq(poolInfo.accERC20PerShare, 0);
    }

    vm.expectRevert("add: LP token already added");
    farm.add(1, lpTokens[0], true);
  }

  function testSet() public {
    farm.add(1, lpTokens[0], true);

    //Only owner check
    vm.prank(address(user1));
    vm.expectRevert("LibDiamond: Must be contract owner");
    farm.set(0, 10, true);

    farm.set(0, 10, true);
    assertEq(address(farm.poolInfo(0).lpToken), address(lpTokens[0]));
    assertEq(farm.poolInfo(0).allocPoint, 10);
    assertEq(farm.poolInfo(0).lastRewardBlock, startBlock);
    assertEq(farm.poolInfo(0).accERC20PerShare, 0);
  }

  // Testing for proper deposit amounts only
  // Harvest amounts tested in testHarvest
  function testDeposit(uint256 amount) public {
    vm.assume(amount > 0 && amount <= 1e50);

    farm.add(1, lpTokens[0], true);

    lpTokens[0].mint(address(user1), amount);
    vm.prank(address(user1));
    lpTokens[0].approve(address(farm), amount);
    vm.prank(address(user1));
    farm.deposit(0, amount);

    farm.updatePool(0);

    vm.prank(address(user1));
    farm.deposit(0, 0);

    assertEq(farm.userInfo(0, address(user1)).amount, amount);
    assertEq(farm.userInfo(0, address(user1)).rewardDebt, 0);
  }

  function testWithdraw(uint256 amount) public {
    vm.assume(amount > 0 && amount <= 1e50);

    farm.add(1, lpTokens[0], true);

    lpTokens[0].mint(address(user1), amount);
    vm.prank(address(user1));
    lpTokens[0].approve(address(farm), amount);
    vm.prank(address(user1));
    farm.deposit(0, amount);

    farm.updatePool(0);

    vm.prank(address(user1));
    farm.withdraw(0, amount);

    assertEq(farm.userInfo(0, address(user1)).amount, 0);
    assertEq(farm.userInfo(0, address(user1)).rewardDebt, 0);
    assertEq(lpTokens[0].balanceOf(address(user1)), amount);
    assertEq(lpTokens[0].balanceOf(address(farm)), 0);
  }

  function testPending(uint128 _amount, uint8 numTokens) public {
    uint256 amount = _amount;
    vm.assume(amount > 0 && amount <= 1e30);
    vm.assume(numTokens > 0 && numTokens <= 20);

    vm.roll(startBlock);

    for (uint256 i = 0; i < numTokens; i++) {
      farm.add(1, lpTokens[i], true);
      lpTokens[i].mint(address(user1), amount);
      vm.prank(address(user1));
      lpTokens[i].approve(address(farm), amount);
      vm.prank(address(user1));
      farm.deposit(i, amount);
    }

    for (uint256 i; i < 100; i++) {
      vm.roll(block.number + i);

      uint256 pending;
      uint256 expectedTotalPending;
      uint256 blocksPassed = block.number - startBlock;
      uint256 k;
      for (; k < blocksPassed / farm.decayPeriod(); k++) {
        expectedTotalPending += farm.rewardPerBlock(k) * 38000 * 365;
      }
      expectedTotalPending +=
        farm.rewardPerBlock(k) *
        (blocksPassed % farm.decayPeriod());
      assertEq(farm.totalPending(), expectedTotalPending, "eq1");
      for (uint256 j = 0; j < numTokens; j++) {
        uint256 expectedPending = expectedTotalPending / numTokens;
        uint256 roundingTolerance = expectedPending / 100;
        assertLe(
          farm.pending(j, address(user1)),
          expectedPending,
          string(
            abi.encodePacked("le1, i: ", i.toString(), " j: ", j.toString())
          )
        );
        assertGe(
          farm.pending(j, address(user1)),
          expectedPending >= roundingTolerance
            ? expectedPending - roundingTolerance
            : 0,
          string(
            abi.encodePacked("ge1, i: ", i.toString(), " j: ", j.toString())
          )
        );
        assertGe(farm.pending(j, address(user1)), pending, "ge2");
        pending = farm.pending(j, address(user1));
      }
    }
  }

  //we need to make sure that the totalPending does not increase after emissions is paused
  function testPauseEmissions(uint256 amount, uint8 numTokens) public {
    vm.assume(amount > 0 && amount <= 1e30);
    vm.assume(numTokens > 0 && numTokens <= 5);

    vm.roll(startBlock);

    for (uint256 i = 0; i < numTokens; i++) {
      farm.add(1, lpTokens[i], true);
      lpTokens[i].mint(address(user1), amount);
      vm.prank(address(user1));
      lpTokens[i].approve(address(farm), amount);
      vm.prank(address(user1));
      farm.deposit(i, amount);
    }

    uint256 blocksUntilStop = 1000;
    uint256 postPauseBlocks = 10000;

    uint256 stopBlock = startBlock + blocksUntilStop;
    farm.pauseEmissions(stopBlock);

    // Before stopBlock, totalPending should track emissions as normal
    uint256 midBlock = startBlock + (blocksUntilStop / 2);
    vm.roll(midBlock);
    {
      uint256 expectedTotalPending;
      uint256 blocksPassed = midBlock - startBlock;
      uint256 k;
      for (; k < blocksPassed / farm.decayPeriod(); k++) {
        expectedTotalPending += farm.rewardPerBlock(k) * 38000 * 365;
      }
      expectedTotalPending +=
        farm.rewardPerBlock(k) *
        (blocksPassed % farm.decayPeriod());
      assertEq(farm.totalPending(), expectedTotalPending, "pre-stop");
    }

    vm.roll(stopBlock);
    uint256 expectedAtStop;
    {
      uint256 blocksPassed = stopBlock - startBlock;
      uint256 k;
      for (; k < blocksPassed / farm.decayPeriod(); k++) {
        expectedAtStop += farm.rewardPerBlock(k) * 38000 * 365;
      }
      expectedAtStop +=
        farm.rewardPerBlock(k) *
        (blocksPassed % farm.decayPeriod());
      assertEq(farm.totalPending(), expectedAtStop, "at-stop");
    }

    // After stopBlock, totalPending should not increase further
    vm.roll(stopBlock + postPauseBlocks);
    assertEq(farm.totalPending(), expectedAtStop, "post-stop");
  }

  function testHarvest(uint256 amount, uint256 period, uint8 numTokens) public {
    vm.assume(amount > 1 && amount <= 1e50);
    vm.assume(period > 0 && period < 365 * 38000 * 40); // 40 years of blocks
    vm.assume(numTokens > 0 && numTokens <= 5);

    for (uint256 i = 0; i < numTokens; i++) {
      farm.add(1, lpTokens[i], true);
      lpTokens[i].mint(address(user1), amount);
      lpTokens[i].mint(address(user2), amount);

      vm.prank(address(user1));
      lpTokens[i].approve(address(farm), amount);
      vm.prank(address(user1));
      farm.deposit(i, amount);

      vm.prank(address(user2));
      lpTokens[i].approve(address(farm), amount);
      vm.prank(address(user2));
      farm.deposit(i, amount);
    }

    vm.roll(startBlock + period);

    for (uint256 i = 0; i < numTokens; i++) {
      uint256 pending = farm.pending(i, address(user1));
      vm.prank(address(user1));
      farm.harvest(i);
      vm.prank(address(user2));
      farm.harvest(i);
      assertEq(farm.userInfo(i, address(user1)).amount, amount, "1");
      assertEq(pending, farm.userInfo(i, address(user1)).rewardDebt, "2");
      assertEq(farm.pending(i, address(user1)), 0, "3");
    }
  }

  function testHarvest2(uint256 amount, uint8 numTokens) public {
    vm.assume(amount > 0 && amount <= 1e30);
    vm.assume(numTokens > 0 && numTokens <= 20);
    for (uint256 i; i < numTokens; i++) {
      farm.add(1, lpTokens[i], true);

      lpTokens[i].mint(address(user1), amount);
      vm.prank(address(user1));
      lpTokens[i].approve(address(farm), amount);
      vm.prank(address(user1));
      farm.deposit(i, amount);

      lpTokens[i].mint(address(user2), amount * 9);
      vm.prank(address(user2));
      lpTokens[i].approve(address(farm), amount * 9);
      vm.prank(address(user2));
      farm.deposit(i, amount * 9);
    }

    vm.roll(startBlock);

    for (uint256 i = 0; i < numTokens; i++) {
      // Farm runs for 416_100_000 blocks
      for (uint256 j = 1; j < 1000; j++) {
        uint256 pending1;
        uint256 pending2;
        {
          uint256 lastBlock = (j - 1) ** 3;
          uint256 nextBlock = j ** 3;

          uint256 startRewardPerBlock = farm.currentRewardPerBlock();

          vm.roll(startBlock + nextBlock);

          uint256 endRewardPerBlock = farm.currentRewardPerBlock();

          pending1 = farm.pending(i, address(user1));
          pending2 = farm.pending(i, address(user2));

          uint256 expectedPendingUB1 = ((startRewardPerBlock *
            (nextBlock - lastBlock)) /
            10 /
            numTokens);
          uint256 expectedPendingLB1 = ((endRewardPerBlock *
            (nextBlock - lastBlock)) /
            10 /
            numTokens);
          uint256 expectedPendingUB2 = expectedPendingUB1 * 9;
          uint256 expectedPendingLB2 = expectedPendingLB1 * 9;

          assertGe(
            pending1,
            (Math.min(expectedPendingLB1, expectedPendingUB1) * 99) / 100,
            string(
              abi.encodePacked("1 i: ", i.toString(), " j: ", j.toString())
            )
          );
          assertLe(
            pending1,
            (Math.max(expectedPendingLB1, expectedPendingUB1) * 101) / 100,
            string(
              abi.encodePacked("2 i: ", i.toString(), " j: ", j.toString())
            )
          );
          assertGe(
            pending2,
            (Math.min(expectedPendingLB2, expectedPendingUB2) * 99) / 100,
            string(
              abi.encodePacked("3 i: ", i.toString(), " j: ", j.toString())
            )
          );
          assertLe(
            pending2,
            (Math.max(expectedPendingLB2, expectedPendingUB2) * 101) / 100,
            string(
              abi.encodePacked("4 i: ", i.toString(), " j: ", j.toString())
            )
          );
        }
        uint256 prevBalance1 = rewardToken.balanceOf(address(user1));
        uint256 prevBalance2 = rewardToken.balanceOf(address(user2));

        vm.prank(address(user1));
        farm.harvest(i);

        vm.prank(address(user2));
        farm.harvest(i);

        assertEq(farm.pending(i, address(user1)), 0, "5");
        assertEq(farm.pending(i, address(user2)), 0, "6");

        assertEq(
          pending1,
          rewardToken.balanceOf(address(user1)) - prevBalance1,
          "7"
        );
        assertEq(
          pending2,
          rewardToken.balanceOf(address(user2)) - prevBalance2,
          "8"
        );
      }
    }
  }

  function testEmergencyWithdraw(uint256 amount, uint8 numTokens) public {
    vm.assume(amount > 0 && amount <= 1e50);
    vm.assume(numTokens > 0 && numTokens <= 20);

    for (uint256 i = 0; i < numTokens; i++) {
      farm.add(1, lpTokens[i], true);
      lpTokens[i].mint(address(user1), amount);
      vm.prank(address(user1));
      lpTokens[i].approve(address(farm), amount);
      vm.prank(address(user1));
      farm.deposit(i, amount);
    }

    for (uint256 i = 0; i < numTokens; i++) {
      vm.prank(address(user1));
      farm.emergencyWithdraw(i);
      assertEq(farm.userInfo(i, address(user1)).amount, 0);
      assertEq(farm.userInfo(i, address(user1)).rewardDebt, 0);
      assertEq(lpTokens[i].balanceOf(address(user1)), amount);
    }
  }

  function testAmounts() public {
    uint256[37] memory yearlyExpectedAmounts = [
      uint256(100_000_000_000 ether),
      83_766_559_911 ether,
      70_168_365_594 ether,
      58_777_626_004 ether,
      49_235_995_301 ether,
      41_243_299_502 ether,
      34_548_093_187 ether,
      28_939_749_177 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      24_241_832_333 ether,
      0,
      0,
      0,
      0,
      0,
      0,
      0
    ];
    uint256 sumExpectedAmounts;
    for (uint256 i; i < yearlyExpectedAmounts.length; i++) {
      vm.roll(startBlock + (i + 1) * 365 * 38000);
      sumExpectedAmounts += yearlyExpectedAmounts[i];
      assertGe(farm.totalPending(), (sumExpectedAmounts * 99) / 100, "1");
      assertLe(farm.totalPending(), (sumExpectedAmounts * 101) / 100, "2");
    }
  }
}
