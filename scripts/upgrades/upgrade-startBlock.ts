import * as hre from "hardhat";
import { ethers, run } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

import { gasPrice } from "../helperFunctions";
import {
  DiamondCutFacet,
  UpdateStartBlockInit__factory,
} from "../../typechain-types";

import { UpdateStartBlockInitInterface } from "../../typechain-types/UpdateStartBlockInit";

export async function upgrade() {
  const signer = (await ethers.getSigners())[0];

  const UpdateStartBlockInit = await ethers.getContractFactory(
    "UpdateStartBlockInit",
    signer
  );

  console.log("Deploying new init");
  const updateStartBlockInit = await UpdateStartBlockInit.deploy({
    gasPrice: gasPrice,
  });
  await updateStartBlockInit.deployed();
  console.log("UpdateStartBlockInit: " + updateStartBlockInit.address);

  const diamondCutFacet = (await hre.ethers.getContractAt(
    "DiamondCutFacet",
    "0x1fE64677Ab1397e20A1211AFae2758570fEa1B8c",
    signer
  )) as DiamondCutFacet;

  let iface: UpdateStartBlockInitInterface = new ethers.utils.Interface(
    UpdateStartBlockInit__factory.abi
  ) as UpdateStartBlockInitInterface;

  console.log("signer:", await signer.getAddress());
  console.log("Running diamond cut");
  await diamondCutFacet.diamondCut(
    [],
    updateStartBlockInit.address,
    iface.encodeFunctionData("init", [BigNumber.from(28471715 + 40000)]),
    { gasPrice: gasPrice }
  );
}

if (require.main === module) {
  upgrade()
    .then(() => process.exit(0))
    // .then(() => console.log('upgrade completed') /* process.exit(0) */)
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
