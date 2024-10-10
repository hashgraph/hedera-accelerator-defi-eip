import ethSigUtil from "@metamask/eth-sig-util";
import { expect } from "chai";
import { ethers } from "hardhat";
import { IDLTPermit } from "../interfaces/IDLTPermit";

const hexRegex = /[A-Fa-fx]/g;

const toBN = (n: number | string | bigint) => BigInt(toHex(n, 0));

const toHex = (n: number | string | bigint, numBytes: number) => {
  const asHexString =
    typeof n === "bigint"
      ? ethers.toBeHex(n).slice(2)
      : typeof n === "string"
      ? hexRegex.test(n)
        ? n.replace(/0x/, "")
        : Number(n).toString(16)
      : Number(n).toString(16);
  return `0x${asHexString.padStart(numBytes * 2, "0")}`;
};

const calculateDLTPermitHash = (params: IDLTPermit) => {
  const PermitTypeString =
    "Permit(address owner,address spender,int64 mainId,int64 subId,uint256 amount,uint256 nonce,uint256 deadline)";

  const permitTypeHash = ethers.id(PermitTypeString);

  const derivedPermitHash = ethers.keccak256(
    "0x" +
      [
        permitTypeHash.slice(2),
        params.owner.slice(2).padStart(64, "0"),
        params.spender.slice(2).padStart(64, "0"),
        ethers.toBeHex(toBN(params.mainId)).slice(2).padStart(64, "0"),
        ethers.toBeHex(toBN(params.subId)).slice(2).padStart(64, "0"),
        ethers.toBeHex(toBN(params.amount)).slice(2).padStart(64, "0"),
        ethers.toBeHex(toBN(params.nonce)).slice(2).padStart(64, "0"),
        ethers.toBeHex(toBN(params.deadline)).slice(2).padStart(64, "0"),
      ].join("")
  );

  return derivedPermitHash;
};

const validateRecoveredAddress = (
  expectAddress: string,
  domainSeparator: string,
  hash: string,
  signature: string
) => {
  const digest = ethers.keccak256(
    `0x1901${domainSeparator.slice(2)}${hash.slice(2)}`
  );
  const recoveredAddress = ethers.recoverAddress(digest, signature);
  expect(recoveredAddress).to.be.equal(expectAddress);
};

async function domainSeparatorCal(name: string, version: string, chainId: number, verifyingContract: string) {
  const EIP712_DOMAIN_TYPEHASH = ethers.keccak256(
    ethers.toUtf8Bytes(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    )
  );

  const NAME_HASH = ethers.keccak256(ethers.toUtf8Bytes(name));
  const VERSION_HASH = ethers.keccak256(ethers.toUtf8Bytes(version));
  const DOMAIN_SEPARATOR = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
          ["bytes32", "bytes32", "bytes32", "uint256", "address"],
          [EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, verifyingContract]
      )
  );
  
  return DOMAIN_SEPARATOR;
}

export {
  toBN,
  toHex,
  calculateDLTPermitHash,
  validateRecoveredAddress,
  domainSeparatorCal,
};
