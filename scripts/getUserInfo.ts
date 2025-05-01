import { FarmFacet } from "../typechain-types";
import { farmAddress } from "../helpers/constants";
import { ethers } from "hardhat";
async function main() {
  const targetAddress = "0x027Ffd3c119567e85998f4E6B9c3d83D5702660c";

  // Get the deployed contract instance
  const farmFacet = (await ethers.getContractAt(
    "FarmFacet",
    farmAddress // Replace with your deployed contract address
  )) as FarmFacet;

  // Call allUserInfo
  const userInfo = await farmFacet.allUserInfo(targetAddress);

  // Log the results
  console.log("User Info for address:", targetAddress);
  userInfo.forEach((info, index) => {
    console.log(`\nPool ${index}:`);
    console.log("LP Token Address:", info.lpToken);
    console.log("Allocation Points:", info.allocPoint.toString());
    console.log("Pending Rewards:", ethers.utils.formatEther(info.pending));
    console.log("User Balance:", ethers.utils.formatEther(info.userBalance));
    console.log("Pool Balance:", ethers.utils.formatEther(info.poolBalance));
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
