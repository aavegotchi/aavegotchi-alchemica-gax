// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../token/GAXLiquidityTokenReward.sol";
import "../diamond/facets/DiamondCutFacet.sol";
import "../diamond/facets/DiamondLoupeFacet.sol";
import "../diamond/facets/OwnershipFacet.sol";

import "../diamond/interfaces/IDiamondCut.sol";
import "../diamond/interfaces/IDiamondLoupe.sol";

import "../diamond/Diamond.sol";

import "../facets/FarmFacet.sol";
import "../init/FarmInit.sol";
import "../init/ReentrancyGuardInit.sol";

/** Helper farm diamond deployment contract. Facet and init contracts must already be deployed because of the contract size limit. */
contract FarmAndGLTRDeployer {
    struct DeployedAddresses {
        address diamond;
        address rewardToken;
        address diamondCutFacet;
        address diamondLoupeFacet;
        address ownershipFacet;
        address farmFacet;
        address farmInit;
        address reentrancyGuardInit;
    }

    struct FarmInitParams {
        uint256 startBlock;
        uint256 decayPeriod;
    }

    function deployFarmAndGLTR(
        DeployedAddresses memory deployedAddresses,
        FarmInitParams memory farmInitParams
    ) external {
        // Cut diamond with diamond selectors and initialize reentry guard
        IDiamondCut(deployedAddresses.diamond).diamondCut(
            populateDiamondCuts(
                deployedAddresses.diamondLoupeFacet,
                deployedAddresses.ownershipFacet
            ),
            deployedAddresses.reentrancyGuardInit,
            abi.encodeWithSelector(ReentrancyGuardInit.init.selector)
        );

        // Cut diamond with farm selectors and initialize farm
        IDiamondCut(deployedAddresses.diamond).diamondCut(
            populateFarmCuts(deployedAddresses.farmFacet),
            deployedAddresses.farmInit,
            abi.encodeWithSelector(
                FarmInit.init.selector,
                deployedAddresses.rewardToken,
                farmInitParams.startBlock,
                farmInitParams.decayPeriod
            )
        );

        // Transfer ownership of the diamond to the sender
        OwnershipFacet(deployedAddresses.diamond).transferOwnership(msg.sender);
    }

    function populateDiamondCuts(
        address diamondLoupeFacet,
        address ownershipFacet
    ) internal pure returns (IDiamondCut.FacetCut[] memory diamondCuts) {
        diamondCuts = new IDiamondCut.FacetCut[](2);
        bytes4[] memory loupeFunctionSelectors = new bytes4[](4);
        {
            uint256 index;
            loupeFunctionSelectors[index++] = DiamondLoupeFacet.facets.selector;
            loupeFunctionSelectors[index++] = DiamondLoupeFacet
                .facetFunctionSelectors
                .selector;
            loupeFunctionSelectors[index++] = DiamondLoupeFacet
                .facetAddresses
                .selector;
            loupeFunctionSelectors[index++] = DiamondLoupeFacet
                .facetAddress
                .selector;
        }
        diamondCuts[0] = IDiamondCut.FacetCut(
            diamondLoupeFacet,
            IDiamondCut.FacetCutAction.Add,
            loupeFunctionSelectors
        );
        bytes4[] memory ownershipFunctionSelectors = new bytes4[](2);
        {
            uint256 index;
            ownershipFunctionSelectors[index++] = OwnershipFacet.owner.selector;
            ownershipFunctionSelectors[index++] = OwnershipFacet
                .transferOwnership
                .selector;
        }
        diamondCuts[1] = IDiamondCut.FacetCut(
            ownershipFacet,
            IDiamondCut.FacetCutAction.Add,
            ownershipFunctionSelectors
        );
        return diamondCuts;
    }

    function populateFarmCuts(
        address farmFacet
    ) internal pure returns (IDiamondCut.FacetCut[] memory farmCuts) {
        farmCuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory farmFunctionSelectors = new bytes4[](26);
        {
            uint256 index;
            farmFunctionSelectors[index++] = FarmFacet.add.selector;
            farmFunctionSelectors[index++] = FarmFacet.set.selector;
            farmFunctionSelectors[index++] = FarmFacet.massUpdatePools.selector;
            farmFunctionSelectors[index++] = FarmFacet.updatePool.selector;
            farmFunctionSelectors[index++] = FarmFacet.deposit.selector;
            farmFunctionSelectors[index++] = FarmFacet.withdraw.selector;
            farmFunctionSelectors[index++] = FarmFacet.harvest.selector;
            farmFunctionSelectors[index++] = FarmFacet.batchHarvest.selector;
            farmFunctionSelectors[index++] = FarmFacet
                .emergencyWithdraw
                .selector;
            farmFunctionSelectors[index++] = FarmFacet.poolLength.selector;
            farmFunctionSelectors[index++] = FarmFacet.deposited.selector;
            farmFunctionSelectors[index++] = FarmFacet.pending.selector;
            farmFunctionSelectors[index++] = FarmFacet.totalPending.selector;
            farmFunctionSelectors[index++] = FarmFacet.rewardToken.selector;
            farmFunctionSelectors[index++] = FarmFacet.paidOut.selector;
            farmFunctionSelectors[index++] = FarmFacet.rewardPerBlock.selector;
            farmFunctionSelectors[index++] = FarmFacet.poolInfo.selector;
            farmFunctionSelectors[index++] = FarmFacet.poolTokens.selector;
            farmFunctionSelectors[index++] = FarmFacet.userInfo.selector;
            farmFunctionSelectors[index++] = FarmFacet.totalAllocPoint.selector;
            farmFunctionSelectors[index++] = FarmFacet.startBlock.selector;
            farmFunctionSelectors[index++] = FarmFacet.decayPeriod.selector;
            farmFunctionSelectors[index++] = FarmFacet.allUserInfo.selector;
            farmFunctionSelectors[index++] = FarmFacet
                .currentRewardPerBlock
                .selector;
            farmFunctionSelectors[index++] = FarmFacet.poolBalance.selector;
            farmFunctionSelectors[index++] = FarmFacet
                .pauseEmissionsAndTransferRemainingGltr
                .selector;
        }
        farmCuts[0] = IDiamondCut.FacetCut(
            farmFacet,
            IDiamondCut.FacetCutAction.Add,
            farmFunctionSelectors
        );
    }
}
