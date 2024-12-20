import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import {
  domainSeparatorCal,
  calculateDLTPermitHash,
  validateRecoveredAddress,
} from "./helpers/eip712";
import { TestDLT } from "../../typechain-types";
import { Signer } from "ethers";
import { IDLTPermit } from "./interfaces/IDLTPermit";

describe("DLTPermit", async function () {
  let DLT: TestDLT;
  let initialHolder: Signer;
  let spender: Signer;
  let name: string;
  let symbol: string;
  let version: string;
  let domainSeparator: string;
  let signature: string;
  let params: IDLTPermit;
  let domainData: any;
  let permitType: any;
  let chainId: number;

  before("Deployment DLT", async function () {
    [initialHolder, spender] = await ethers.getSigners();

    name = "DLTPermit";
    symbol = "DLTP";
    version = "1.0";
    chainId = 31337;
    // ------------------------------------------------------------------
    const DLTFactory = await ethers.getContractFactory("TestDLT");
    DLT = await DLTFactory.deploy(name, symbol, version);

    expect(await DLT.subBalanceOf(initialHolder.getAddress(), 1, 1)).to.equal(
      ethers.parseEther("0")
    );

    await DLT.mint(
      initialHolder.getAddress(),
      1,
      1,
      ethers.parseEther("10000")
    );
    domainSeparator = await DLT.DOMAIN_SEPARATOR();
    expect(await DLT.subBalanceOf(initialHolder.getAddress(), 1, 1)).to.equal(
      ethers.parseEther("10000")
    );
  });

  it("initial nonce is 0", async function () {
    expect(await DLT.nonces(initialHolder.getAddress())).to.be.equal("0");
  });

  it("domain separator", async function () {
    expect(domainSeparator).to.equal(
      await domainSeparatorCal(name, version, chainId, await DLT.getAddress())
    );
  });

  const mainId = 1n;
  const subId = 1n;
  const amount = 1000n;
  const nonce = 0n;
  const deadline = ethers.MaxUint256;

  it("accepts owner signature", async function () {
    params = {
      owner: await initialHolder.getAddress(),
      spender: await spender.getAddress(),
      mainId,
      subId,
      amount,
      nonce,
      deadline,
    };
    domainData = {
      name,
      version,
      chainId,
      verifyingContract: await DLT.getAddress(),
    };
    permitType = {
      Permit: [
        { name: "owner", type: "address" },
        { name: "spender", type: "address" },
        { name: "mainId", type: "int64" },
        { name: "subId", type: "int64" },
        { name: "amount", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    };
    signature = await initialHolder.signTypedData(
      domainData,
      permitType,
      params
    );

    // Validate Signature Offchain
    const hash = calculateDLTPermitHash(params);
    validateRecoveredAddress(
      await initialHolder.getAddress(),
      domainSeparator,
      hash,
      signature
    );

    const { r, s, v } = ethers.Signature.from(signature);

    await DLT.permit(
      initialHolder.getAddress(),
      spender.getAddress(),
      mainId,
      subId,
      amount,
      deadline,
      v,
      r,
      s
    );

    expect(await DLT.nonces(initialHolder.getAddress())).to.be.equal("1");
    expect(
      await DLT.allowance(
        initialHolder.getAddress(),
        spender.getAddress(),
        1,
        1
      )
    ).to.be.equal(amount);
  });

  it("rejects reused signature", async function () {
    const { r, s, v } = ethers.Signature.from(signature);

    await expect(
      DLT.permit(
        await initialHolder.getAddress(),
        await spender.getAddress(),
        mainId,
        subId,
        amount,
        deadline,
        v,
        r,
        s
      )
    ).to.be.reverted;
  });

  it("rejects other signature", async function () {
    signature = await spender.signTypedData(domainData, permitType, params);

    const { r, s, v } = ethers.Signature.from(signature);

    await expect(
      DLT.permit(
        await initialHolder.getAddress(),
        await spender.getAddress(),
        mainId,
        subId,
        amount,
        deadline,
        v,
        r,
        s
      )
    ).to.be.reverted;
  });

  it("rejects with invalid S parameter", async function () {
    signature = await spender.signTypedData(domainData, permitType, params);

    const { r, v } = ethers.Signature.from(signature);
    const s = ethers.toQuantity(ethers.MaxUint256);
    await expect(
      DLT.permit(
        await initialHolder.getAddress(),
        await spender.getAddress(),
        mainId,
        subId,
        amount,
        deadline,
        v,
        r,
        s
      )
    ).to.be.reverted;
  });

  it("rejects with invalid V parameter", async function () {
    signature = await spender.signTypedData(domainData, permitType, params);

    const { r, s } = ethers.Signature.from(signature);
    const v = 0;
    await expect(
      DLT.permit(
        await initialHolder.getAddress(),
        await spender.getAddress(),
        mainId,
        subId,
        amount,
        deadline,
        v,
        r,
        s
      )
    ).to.be.reverted;
  });

  it("rejects expired permit", async function () {
    const expiredDeadline = (await time.latest()) - 100;

    signature = await spender.signTypedData(domainData, permitType, params);

    const { r, s, v } = ethers.Signature.from(signature);

    await expect(
      DLT.permit(
        initialHolder.getAddress(),
        spender.getAddress(),
        mainId,
        subId,
        amount,
        expiredDeadline,
        v,
        r,
        s
      )
    ).to.be.reverted;
  });
});
