import { ethers, run, network } from "hardhat";
import {
  convertFacetAndSelectorsToString,
  DeployUpgradeTaskArgs,
  FacetsAndAddSelectors,
} from "../../tasks/deployUpgrade";
import { varsForNetwork } from "../constants";
import { FarmFacetInterface } from "../../typechain-types/FarmFacet";
import { FarmFacet__factory } from "../../typechain-types";
import { getLedgerSigner, impersonate } from "../helperFunctions";

export async function upgrade() {
  const addresses = await varsForNetwork(ethers);
  const facets: FacetsAndAddSelectors[] = [
    {
      facetName: "contracts/facets/FarmFacet.sol:FarmFacet",
      addSelectors: [
        "function pauseEmissions(uint256 stopBlock_) external",
        "function resumeEmissions() external",
        "function transferRemainingGltr(address to) external",
      ],
      removeSelectors: [],
    },
  ];
  const joined = convertFacetAndSelectorsToString(facets);

  const ownershipFacet = await ethers.getContractAt(
    "OwnershipFacet",
    addresses.farmAddress
  );
  const owner = await ownershipFacet.owner();

  let iface: FarmFacetInterface = new ethers.utils.Interface(
    FarmFacet__factory.abi
  ) as FarmFacetInterface;

  //set the end block when gltr emissions end on polygon

  const END_BLOCK = 75990240;

  let calldata = iface.encodeFunctionData("pauseEmissions", [END_BLOCK]);

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

  //then transfer remaining gltr to owner
  const testing = ["hardhat", "localhost"].includes(network.name);

  let signer;
  let farmFacet = await ethers.getContractAt(
    "FarmFacet",
    addresses.farmAddress
  );

  if (testing) {
    signer = await ethers.getSigner(owner);
    farmFacet = await impersonate(owner, farmFacet, ethers, network);
  } else {
    signer = await getLedgerSigner(ethers);
    farmFacet = await ethers.getContractAt(
      "FarmFacet",
      addresses.farmAddress,
      signer
    );
  }

  const PC = "0x01F010a5e001fe9d6940758EA5e8c777885E351e";

  const tx = await farmFacet.transferRemainingGltr(PC);
  await tx.wait();
  console.log("transferRemainingGltr done");
}

if (require.main === module) {
  upgrade()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
