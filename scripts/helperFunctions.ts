import { Signer } from "@ethersproject/abstract-signer";
import { Contract } from "@ethersproject/contracts";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DiamondLoupeFacet, OwnershipFacet } from "../typechain-types";
import {
  DefenderRelayProvider,
  DefenderRelaySigner,
} from "defender-relay-client/lib/ethers";
import { LedgerSigner } from "@anders-t/ethers-ledger";

export const gasPrice = 1000000000000;

export async function impersonate(
  address: string,
  contract: any,
  ethers: any,
  network: any
) {
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
  let signer = await ethers.getSigner(address);
  contract = contract.connect(signer);
  return contract;
}

export async function resetChain(hre: any) {
  await hre.network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: process.env.MATIC_URL,
        },
      },
    ],
  });
}

export function getSighashes(selectors: string[], ethers: any): string[] {
  if (selectors.length === 0) return [];
  const sighashes: string[] = [];
  selectors.forEach((selector) => {
    if (selector !== "") sighashes.push(getSelector(selector, ethers));
  });
  return sighashes;
}

export function getSelectors(contract: Contract) {
  const signatures = Object.keys(contract.interface.functions);
  const selectors = signatures.reduce((acc: string[], val: string) => {
    if (val !== "init(bytes)") {
      acc.push(contract.interface.getSighash(val));
    }
    return acc;
  }, []);
  return selectors;
}

export function getSelector(func: string, ethers: any) {
  const abiInterface = new ethers.utils.Interface([func]);
  return abiInterface.getSighash(ethers.utils.Fragment.from(func));
}

export const maticDiamondAddress = "0xB77225AD50bF0Ea5c9a51Dcf17D0D503Aca44DAD";

export async function diamondOwner(address: string, ethers: any) {
  return await (await ethers.getContractAt("OwnershipFacet", address)).owner();
}

export async function getFunctionsForFacet(facetAddress: string, ethers: any) {
  const Loupe = (await ethers.getContractAt(
    "DiamondLoupeFacet",
    maticDiamondAddress
  )) as DiamondLoupeFacet;
  const functions = await Loupe.facetFunctionSelectors(facetAddress);
  return functions;
}

export async function getDiamondSigner(
  hre: HardhatRuntimeEnvironment,
  override?: string,
  useLedger?: boolean
) {
  //Instantiate the Signer
  let signer: Signer;
  const owner = await (
    (await hre.ethers.getContractAt(
      "OwnershipFacet",
      maticDiamondAddress
    )) as OwnershipFacet
  ).owner();
  const testing = ["hardhat", "localhost"].includes(hre.network.name);

  if (testing) {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [override ? override : owner],
    });
    return await hre.ethers.getSigner(override ? override : owner);
  } else if (hre.network.name === "matic") {
    return (await hre.ethers.getSigners())[0];
  } else {
    throw Error("Incorrect network selected");
  }
}

export const xpRelayerAddress = "0xb6384935d68e9858f8385ebeed7db84fc93b1420";
export const xpRelayerAddressBaseSepolia =
  "0x46c7064038C4821dDd1c27Ed9FC4b283a74AC6d2";
export const xpRelayerAddressBase =
  "0xf52398257A254D541F392667600901f710a006eD";

export interface RelayerInfo {
  apiKey: string;
  apiSecret: string;
}

export async function getRelayerSigner(hre: HardhatRuntimeEnvironment) {
  const testing = ["hardhat", "localhost"].includes(hre.network.name);
  let xpRelayer;
  if (
    hre.network.config.chainId === 137 ||
    hre.network.config.chainId === 8453
  ) {
    xpRelayer = xpRelayerAddress;
  } else if (hre.network.config.chainId === 84532) {
    xpRelayer = xpRelayerAddressBaseSepolia;
  }

  if (testing) {
    if (hre.network.config.chainId !== 31337) {
      console.log("Using Hardhat");

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [xpRelayer],
      });
      await hre.network.provider.request({
        method: "hardhat_setBalance",
        params: [xpRelayerAddress, "0x100000000000000000000000"],
      });
      return await hre.ethers.provider.getSigner(xpRelayerAddress);
    } else {
      return (await hre.ethers.getSigners())[0];
    }
    //we assume same defender for base mainnet
  } else if (hre.network.name === "matic" || hre.network.name === "base") {
    console.log("USING", hre.network.name);

    const credentials: RelayerInfo = {
      apiKey: process.env.DEFENDER_APIKEY!,
      apiSecret: process.env.DEFENDER_SECRET!,
    };

    const provider = new DefenderRelayProvider(credentials);
    return new DefenderRelaySigner(credentials, provider, {
      speed: "average",
      validForSeconds: 200,
    });
  } else if (hre.network.name === "baseSepolia") {
    console.log("USING BASE SEPOLIA DEFENDER");
    const credentials: RelayerInfo = {
      apiKey: process.env.DEFENDER_APIKEY_BASESEPOLIA!,
      apiSecret: process.env.DEFENDER_SECRET_BASESEPOLIA!,
    };

    const provider = new DefenderRelayProvider(credentials);
    return new DefenderRelaySigner(credentials, provider, {
      speed: "safeLow",
      validForSeconds: 180,
    });
  } else if (
    ["tenderly", "polter", "amoy", "geist"].includes(hre.network.name)
  ) {
    //impersonate
    return (await hre.ethers.getSigners())[0];
  } else {
    throw Error("Incorrect network selected");
  }
}

export async function getLedgerSigner(ethers: any) {
  console.log("Getting ledger signer");
  return new LedgerSigner(ethers.provider, "m/44'/60'/1'/0/0");
}
