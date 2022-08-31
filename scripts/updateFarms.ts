import { ethers, network } from "hardhat";
import { FarmFacet } from "../typechain-types/FarmFacet";
import { impersonate } from "../scripts/helperFunctions";
import { farmAddress } from "../helpers/constants";

async function main() {
  const owner = "0x94cb5C277FCC64C274Bd30847f0821077B231022";

  let farmFacet = (await ethers.getContractAt(
    "FarmFacet",
    farmAddress
  )) as FarmFacet;

  if (network.name === "localhost" || network.name === "hardhat") {
    farmFacet = await impersonate(owner, farmFacet, ethers, network);
  }

  console.log("Remove GHST-WMATIC rewards");
  let tx = await farmFacet.set(
    "6", //ghst-wmatic
    "0",
    true
  );
  await tx.wait();

  console.log("Set GHST-USDC to 20%");
  tx = await farmFacet.set("5", "4", true); //ghst-usdc
  await tx.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
