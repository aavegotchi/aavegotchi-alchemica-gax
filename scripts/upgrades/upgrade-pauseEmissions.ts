import { ethers, run, network } from "hardhat";
import {
  convertFacetAndSelectorsToString,
  DeployUpgradeTaskArgs,
  FacetsAndAddSelectors,
} from "../../tasks/deployUpgrade";
import { varsForNetwork } from "../constants";
import { FarmFacetInterface } from "../../typechain-types/FarmFacet";
import { FarmFacet__factory } from "../../typechain-types";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

export async function upgrade() {
  const addresses = await varsForNetwork(ethers);
  const facets: FacetsAndAddSelectors[] = [
    {
      facetName: "contracts/facets/FarmFacet.sol:FarmFacet",
      addSelectors: [
        "function pauseEmissionsAndTransferRemainingGltr(address to) external",
      ],
      removeSelectors: [],
    },
  ];
  const joined = convertFacetAndSelectorsToString(facets);

  const ownershipFacet = await ethers.getContractAt(
    "OwnershipFacet",
    addresses.farmAddress
  );

  if (network.name === "hardhat") {
    await mine();
  }

  const owner = await ownershipFacet.owner();

  let iface: FarmFacetInterface = new ethers.utils.Interface(
    FarmFacet__factory.abi
  ) as FarmFacetInterface;

  //pause emissions and transfer remaining GLTR immediately when upgrade is deployed
  const PC = "0x01F010a5e001fe9d6940758EA5e8c777885E351e";

  let calldata = iface.encodeFunctionData(
    "pauseEmissionsAndTransferRemainingGltr",
    [PC]
  );

  const args: DeployUpgradeTaskArgs = {
    diamondAddress: addresses.farmAddress,
    facetsAndAddSelectors: joined,
    useLedger: true,
    useMultisig: false,
    diamondUpgrader: owner,
    initCalldata: calldata,
    initAddress: addresses.farmAddress,
  };

  await run("deployUpgrade", args);

  console.log(
    "Emissions paused and remaining GLTR transferred in single transaction"
  );
}

if (require.main === module) {
  upgrade()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
