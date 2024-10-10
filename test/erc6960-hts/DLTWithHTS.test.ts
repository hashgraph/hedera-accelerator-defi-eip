import { expect } from "chai";
import { ethers } from "hardhat";
import { TestDLTWithHTS } from "../../typechain-types";
import { parseEther, Signer } from "ethers";

async function deployFixture() {
  const [owner] = await ethers.getSigners();

  const wallet = ethers.Wallet.createRandom();
  const user1 = wallet.connect(ethers.getDefaultProvider());

  // ------------------------------------------------------------------ 
  const DLTFactory = await ethers.getContractFactory("TestDLTWithHTS");
  const DLT = await DLTFactory.deploy("Polytrade DLT", "PLT", "1.0", { 
    value : parseEther("50"),
    gasLimit: 2400000
  });
  console.log(` - DLT deployed at: ${await DLT.getAddress()}`);

  return {
    DLT,
    owner,
    user1,
  }
}

describe("DLTWithHTS", async () => {
  let DLT: TestDLTWithHTS;
  let owner: Signer;
  let user1: Signer;

  before(async () => {
    const context = await deployFixture();

    DLT = context.DLT;
    owner = context.owner;
    user1 = context.user1;
  });

  it("Should return batch balances after minting", async () => {
    const minttx = await DLT.mintMainAsset(owner.getAddress(), ethers.parseEther("10000"), { 
      value: parseEther('3'),
      gasLimit: 2400000
    });
    
    await minttx.wait();

    const mainId = 1;
    const subid = 1;
    const balanceOfBatch = await DLT.balanceOfBatch([owner.getAddress()], [mainId],[subid]);
    const subBalanceOf = await DLT.subBalanceOf(owner.getAddress(), mainId, subid);

    expect(balanceOfBatch).to.deep.equal([subBalanceOf]);
  });

  it("Should revert if main token is not minted", async () => {
    const mainId = 2;
    const subid = 1;
    await expect(DLT.mintSubAsset(owner.getAddress(), mainId, subid, ethers.parseEther("10000"))).to.be.rejectedWith("Token Not Minted");
  });

  it("Should mint subasset", async () => {    
    const mainId = 1;
    const subid = 2;
    const tx = await DLT.mintSubAsset(owner.getAddress(), mainId, subid, ethers.parseEther("10000"));
    await tx.wait();

    expect(await DLT.subBalanceOf(owner.getAddress(), mainId, subid)).to.be.equal(ethers.parseEther("10000"));
  });

  it("Should increase balances after minting", async () => {
    const mainId = 1;
    const subid = 2;
    const tx = await DLT.mintSubAsset(owner.getAddress(), mainId, subid, ethers.parseEther("1"));
    await tx.wait();

    expect(await DLT.subBalanceOf(owner.getAddress(), mainId, subid)).to.be.equal(ethers.parseEther("10001"));
    expect(await DLT.totalMainSupply(mainId)).to.equal(ethers.parseEther("20001"));
    expect(await DLT.totalSubSupply(mainId, subid)).to.equal(
      ethers.parseEther("10001")
    );
    expect(await DLT.totalMainIds()).to.equal(1);
    expect(await DLT.totalSubIds(mainId)).to.equal(2);
  });

  it("Should add subId to subIds after minting and remove after burning", async () => {


    const mainId = 1;
    await DLT.mintSubAsset(owner.getAddress(), mainId, 3, ethers.parseEther("10000"));

    const beforeBurn = await DLT.getSubIds(mainId);

    expect(beforeBurn.length).to.equal(3);

    await DLT.burn(owner.getAddress(), mainId, 3, ethers.parseEther("10000"));

    const afterBurn = await DLT.getSubIds(mainId);
    const array = [];
    for (let i = 0; i < afterBurn.length; i++) {
      array.push(Number(afterBurn[i]));
    }

    expect(array.length).to.equal(2);
    expect(array[0]).to.equal(1);
    expect(array[1]).to.equal(2);
  });

  it("Should revert batch safeTransferFrom because of array mismatch length", async () => {
    await expect(
      DLT.connect(owner).safeBatchTransferFrom(
        owner.getAddress(),
        user1.getAddress(),
        [], // mismatch
        [1],
        [ethers.parseEther("5000")],
        ethers.randomBytes(1)
      )
    ).to.be.revertedWith("DLT: mainIds, subIds and amounts length mismatch");
  });

  it("Should revert batch safeTransferFrom to address zero", async () => {
    await expect(
      DLT.connect(owner).safeBatchTransferFrom(
        owner.getAddress(),
        ethers.ZeroAddress,
        [1],
        [1],
        [ethers.parseEther("5000")],
        ethers.randomBytes(1)
      )
    ).to.be.revertedWith("DLT: transfer to the zero address");
  });

  it("Should revert batch safeTransferFrom because of insufficient balance", async () => {
    await expect(
      DLT.connect(owner).safeBatchTransferFrom(
        owner.getAddress(),
        user1.getAddress(),
        [1],
        [1],
        [ethers.parseEther("10000000")],
        ethers.randomBytes(1)
      )
    ).to.be.revertedWith("DLT: insufficient balance for transfer");
  });

  it("Set Approval for all", async function () {
    expect(await DLT.setApprovalForAll(user1.getAddress(), true))
      .to.emit(DLT, "ApprovalForAll")
      .withArgs(owner.getAddress(), user1.getAddress(), true);

    expect(
      await DLT.isApprovedForAll(owner.getAddress(), user1.getAddress())
    );
  });

  it("Should revert to mint for address zero", async function () {
    await expect(
      DLT.mintSubAsset(ethers.ZeroAddress, 1, 1, ethers.parseEther("10000"))
    ).to.be.revertedWith("DLT: mint to the zero address");
  });

  it("Should revert to mint zero amount", async function () {
    await expect(DLT.mintSubAsset(owner.getAddress(), 1, 1, 0)).to.be.revertedWith(
      "DLT: mint zero amount"
    );
  });

  it("Should revert transfer from zero address", async function () {
    await expect(
      DLT.transfer(
        ethers.ZeroAddress,
        owner.getAddress(),
        1,
        1,
        ethers.parseEther("10000")
      )
    ).to.be.revertedWith("DLT: transfer from the zero address");
  });

  it("Should revert to burn for address zero", async function () {
    await expect(
      DLT.burn(ethers.ZeroAddress, 1, 1, ethers.parseEther("10000"))
    ).to.be.revertedWith("DLT: burn from the zero address");
  });

  it("Should revert to burn amount greater than the current balance", async function () {
    await expect(
      DLT.burn(owner.getAddress(), 1, 1, ethers.parseEther("20000"))
    ).to.be.revertedWith("DLT: insufficient balance");
  });

  it("Should revert to burn 0 amount", async function () {
    await expect(DLT.burn(owner.getAddress(), 1, 1, 0)).to.be.revertedWith(
      "DLT: burn zero amount"
    );
  });

  it("Should approve MaxInt256", async function () {
    expect(
      await DLT.connect(owner).approve(
        user1.getAddress(),
        1,
        1,
        ethers.MaxInt256
      )
    );
  });

  it("Should revert on approve when approving same owner", async function () {
    await expect(
      DLT.connect(owner).approve(
        owner.getAddress(),
        1,
        1,
        ethers.parseEther("10000")
      )
    ).to.be.revertedWith("DLT: approval to current owner");
  });

  it("Should revert on approve for address zero", async function () {
    await expect(
      DLT.connect(owner).approve(
        ethers.ZeroAddress,
        1,
        1,
        ethers.parseEther("10000")
      )
    ).to.be.revertedWith("DLT: approve to the zero address");
  });

  it("should revert approve from zero address", async function () {
    await expect(
      DLT.allow(
        ethers.ZeroAddress,
        owner.getAddress(),
        1,
        1,
        ethers.parseEther("10000")
      )
    ).to.be.revertedWith("DLT: approve from the zero address");
  });
});
