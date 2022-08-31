import { ethers, network } from "hardhat";
import { FarmFacet } from "../typechain-types/FarmFacet";
import { impersonate } from "../scripts/helperFunctions";

async function main() {
  const farmAddress = "0x1fE64677Ab1397e20A1211AFae2758570fEa1B8c";

  const owner = "0x94cb5C277FCC64C274Bd30847f0821077B231022";

  let farmFacet = (await ethers.getContractAt(
    "FarmFacet",
    farmAddress
  )) as FarmFacet;

  if (network.name === "localhost" || network.name === "hardhat") {
    farmFacet = await impersonate(owner, farmFacet, ethers, network);
  }

  const tx = await farmFacet.add(
    "3",
    "0xb0e35478a389dd20050d66a67fb761678af99678",
    true
  );
  await tx.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
