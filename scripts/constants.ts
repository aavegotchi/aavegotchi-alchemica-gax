import { HardhatEthersHelpers } from "@nomiclabs/hardhat-ethers/types";

export interface Contracts {
  gltrAddress: string;
  farmAddress: string;
}

interface NetworkToContracts {
  [network: number]: Contracts;
}

function varsByChainId(chainId: number) {
  if ([137, 80001, 84532, 8453, 31337].includes(chainId))
    return networkToVars[chainId];
  else return networkToVars[137];
}

export async function varsForNetwork(ethers: HardhatEthersHelpers) {
  return varsByChainId((await ethers.provider.getNetwork()).chainId);
}

export const baseVars: Contracts = {
  gltrAddress: "0x4D140CE792bEdc430498c2d219AfBC33e2992c9D",
  farmAddress: "",
};

export const maticVars: Contracts = {
  gltrAddress: "0x3801c3b3b5c98f88a9c9005966aa96aa440b9afc",
  farmAddress: "0x1fE64677Ab1397e20A1211AFae2758570fEa1B8c",
};

const networkToVars: NetworkToContracts = {
  137: maticVars,
  8453: baseVars,
  31337: baseVars, //to simulate base mainnet
};
