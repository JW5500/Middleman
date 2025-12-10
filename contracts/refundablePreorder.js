const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RefundablePreorderImp", function () {
  let Contract;
  let contract;
  let seller, buyer1, buyer2;
  const unitPrice = ethers.parseEther("1");
  const deadlineOffset = 3600;
  const confirmationPeriod = 7 * 24 * 60 * 60;

  beforeEach(async function () {
    [seller, buyer1, buyer2] = await ethers.getSigners();

    const now = (await ethers.provider.getBlock("latest")).timestamp;
    const deadline = now + deadlineOffset;

    Contract = await ethers.getContractFactory("RefundablePreorderImp");
    contract = await Contract.deploy("Test Product", unitPrice, deadline);
    await contract.waitForDeployment();
  });

  it("allows buyer to place preorder with correct ETH", async function () {
    await expect(
      contract.connect(buyer1).placePreorder(1, { value: unitPrice })
    ).to.not.be.reverted;

    const buyerInfo = await contract.getBuyerInfo(buyer1.address);
    expect(buyerInfo.amountPaid).to.equal(unitPrice);
    expect(buyerInfo.quantity).to.equal(1n);
  });

  it("reverts if incorrect ETH is sent", async function () {
    await expect(
      contract.connect(buyer1).placePreorder(2, { value: unitPrice })
    ).to.be.revertedWith("Incorrect ETH sent");
  });

  it("allows refund after deadline when not delivered", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });

    await ethers.provider.send("evm_increaseTime", [deadlineOffset + 1]);
    await ethers.provider.send("evm_mine");

    await expect(contract.connect(buyer1).claimRefund()).to.not.be.reverted;

    const buyerInfo = await contract.getBuyerInfo(buyer1.address);
    expect(buyerInfo.refunded).to.equal(true);
  });

  it("does not allow refund if delivered", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });
    await contract.connect(seller).markProductDelivered();

    await ethers.provider.send("evm_increaseTime", [deadlineOffset + 1]);
    await ethers.provider.send("evm_mine");

    await expect(contract.connect(buyer1).claimRefund())
      .to.be.revertedWith("Product delivered - refunds disabled");
  });

  it("allows buyer to confirm receipt", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });
    await contract.connect(seller).markProductDelivered();

    await expect(contract.connect(buyer1).confirmReceipt()).to.not.be.reverted;
  });

  it("allows seller to withdraw after confirmation", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });
    await contract.connect(seller).markProductDelivered();
    await contract.connect(buyer1).confirmReceipt();

    await expect(contract.connect(seller).withdrawFunds()).to.not.be.reverted;
  });

  it("allows seller to withdraw after timeout", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });
    await contract.connect(seller).markProductDelivered();

    await ethers.provider.send("evm_increaseTime", [confirmationPeriod + 10]);
    await ethers.provider.send("evm_mine");

    await expect(contract.connect(seller).withdrawFunds()).to.not.be.reverted;
  });

  it("prevents seller from withdrawing twice", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });
    await contract.connect(seller).markProductDelivered();
    await contract.connect(buyer1).confirmReceipt();

    await contract.connect(seller).withdrawFunds();

    await expect(contract.connect(seller).withdrawFunds())
      .to.be.revertedWith("Already withdrawn");
  });

  it("prevents buyer from refunding twice", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });

    await ethers.provider.send("evm_increaseTime", [deadlineOffset + 1]);
    await ethers.provider.send("evm_mine");

    await contract.connect(buyer1).claimRefund();

    await expect(contract.connect(buyer1).claimRefund())
      .to.be.revertedWith("No preorder found");
  });

  it("prevents seller from withdrawing before delivery", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });

    await expect(contract.connect(seller).withdrawFunds())
      .to.be.revertedWith("Not delivered yet");
  });

  it("allows seller to set activation-code hash for a buyer", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });

    const code = "SECRET123";
    const hash = ethers.keccak256(ethers.toUtf8Bytes(code));

    await expect(
      contract.connect(seller).setActivationCodeHash(buyer1.address, hash)
    ).to.not.be.reverted;
  });

  it("prevents setting activation code for someone with no preorder", async function () {
    const code = "XYZ";
    const hash = ethers.keccak256(ethers.toUtf8Bytes(code));

    await expect(
      contract.connect(seller).setActivationCodeHash(buyer2.address, hash)
    ).to.be.revertedWith("No preorder found");
  });

  it("allows buyer to confirm with correct activation code", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });

    const code = "GAMEKEY-999";
    const hash = ethers.keccak256(ethers.toUtf8Bytes(code));

    await contract.connect(seller).setActivationCodeHash(buyer1.address, hash);
    await contract.connect(seller).markProductDelivered();

    await expect(
      contract.connect(buyer1).confirmReceiptWithCode(code)
    ).to.not.be.reverted;

    await expect(
      contract.connect(buyer1).confirmReceiptWithCode(code)
    ).to.be.revertedWith("Already confirmed");
  });

  it("rejects wrong activation code", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });

    const correct = "CORRECT-CODE";
    const wrong = "WRONG-CODE";
    const hash = ethers.keccak256(ethers.toUtf8Bytes(correct));

    await contract.connect(seller).setActivationCodeHash(buyer1.address, hash);
    await contract.connect(seller).markProductDelivered();

    await expect(
      contract.connect(buyer1).confirmReceiptWithCode(wrong)
    ).to.be.revertedWith("Invalid activation code");
  });

  it("allows seller to withdraw after activation-code confirmation", async function () {
    await contract.connect(buyer1).placePreorder(1, { value: unitPrice });

    const code = "ACCESS-777";
    const hash = ethers.keccak256(ethers.toUtf8Bytes(code));

    await contract.connect(seller).setActivationCodeHash(buyer1.address, hash);
    await contract.connect(seller).markProductDelivered();
    await contract.connect(buyer1).confirmReceiptWithCode(code);

    await expect(contract.connect(seller).withdrawFunds()).to.not.be.reverted;
  });
});
