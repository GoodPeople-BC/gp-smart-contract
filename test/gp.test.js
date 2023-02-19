const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GP Test", function () {
  let [owner, fund, recipient, tester] = [];

  it("Deploy token contract", async function () {
    [owner, fund, recipient, tester] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("GPToken", owner);
    const Badge = await ethers.getContractFactory("GPBadge", owner);
    const USDC = await ethers.getContractFactory("USDC", owner) // "0xe6b8a5CF854791412c1f6EFC7CAf629f5Df1c747"

    usdc = await USDC.deploy();
    token = await Token.deploy();
    badge = await Badge.deploy("testurl");
    await usdc.deployed();
    await token.deployed();
    await badge.deployed();
  });

  it("Deploy vault contract", async function () {
    const Vault = await ethers.getContractFactory("GPVault", owner);
    vault = await Vault.deploy(fund.address, token.address, usdc.address, 10000);
    await vault.deployed();

    await token.connect(owner).addGovernanceRole(vault.address)
  })

  it("Deploy gp contract", async function () {
    const GP = await ethers.getContractFactory("GPGovernance", owner);
    gp = await GP.deploy(token.address, 12);
    await gp.deployed();
  })

  it("Deploy gp service contract", async function() {
    const GPS = await ethers.getContractFactory("GPService", owner);
    gps = await GPS.deploy(gp.address, vault.address)
    await gps.deployed();
  })

  it("Test GP Badge uri", async () => {
    const url = await badge.uri(10);
    expect(url).to.equal("testurl/10")
  });

  it("Test GP Service period, amount", async () => {
    const amounts = await gps.getTargetAmounts()
    const periods = await gps.getTargetPeriods()
    expect(periods.length).to.equal(3)
    expect(amounts.length).to.equal(3)
    expect(periods[0]).to.equal("1209600")
    expect(periods[1]).to.equal("2419200")
    expect(periods[2]).to.equal("7257600")
    expect(amounts[0]).to.equal("10000000")
    expect(amounts[1]).to.equal("100000000")
    expect(amounts[2]).to.equal("1000000000")
  });

  it("Test GP Service addDonation", async () => {
    await vault.connect(owner).addGovernanceRole(gps.address);
    await vault.connect(owner).addGovernanceRole(gp.address);
    
    {
        await usdc.connect(owner).mint(owner.address, "100000000000000000000")
        const balance = await usdc.balanceOf(owner.address)
        console.log(balance)
    }

    // sponser 통해 투표권 발급 및 delegate self
    {
        await usdc.connect(owner).approve(vault.address, "10000000000000000000");
        await vault.connect(owner).sponsorGp("10000000000000000000");
        // await token.connect(owner).delegate(owner.address)
    }

    // 투표 의제 등록
    let proposeId
    let donationId
    {
      console.log("1. add proposal")
        await gps.connect(owner).addDonationProposal("10000000", "1209600", recipient.address, "ipfs/url")
        donationId = await gps.addLength();
        console.log(donationId)
        const proposal = await vault.getDonateProposal(donationId-1)
        console.log(proposal)
        proposeId = await gps.getAddProposalIds(donationId-1)
    }

    // 찬성 투표
    { 
        console.log("2. vote")
        await gp.connect(owner).castVote(proposeId, 1)

        const balance = await gp.getVotingBalance(proposeId, owner.address)
        console.log("2. vote")
        console.log(balance)
    }

    // 투표 조회
    {
        console.log("3. get proposal")
        const voted = await gp.proposalVotes(proposeId)
        console.log(voted)

        const hasvoted = await gp.hasVoted(proposeId, owner.address)
        console.log(hasvoted)
    }
    

    // 기부 리스트 조회
    {
        console.log("4. get proposal list")
        const list = await gps.getDonationList()
        console.log(list)
    }

    // 투표 시간 조정
    {
        console.log("5. end proposal")
        for (let index = 0; index < 8600; index++) {
            await network.provider.send("evm_mine")
        }    
    }

    // 투표 실행
    {
        console.log("6. execute proposal")
        console.log(donationId-1)
        await gps.executeAddDonationProposal(donationId-1)
    }

    // 현재 기부 상태
    {
        console.log("7. get proposal")
        const proposal = await vault.getDonateProposal(donationId-1)
        console.log("proposal")
        console.log(proposal)
    }

    // 기부 리스트 조회
    {
        console.log("8. get proposal list")
        const list = await gps.getDonationList()
        console.log(list)
    }

    // 기부하기
    {
        console.log("9. before donate")
        const status = await vault.getCurrentStatus(donationId-1);
        console.log(status);
        await network.provider.send("evm_increaseTime", [90000])
        await network.provider.send("evm_mine")

        const status2 = await vault.getCurrentStatus(donationId-1);
        console.log(status2);

        const b1 = await token.balanceOf(owner.address)
        console.log(b1)

        await usdc.connect(owner).approve(vault.address, 10000000)
        await vault.connect(owner).donate(donationId-1, 10000000);
        const status3 = await vault.getCurrentStatus(donationId-1);
        const proposal = await vault.getDonateProposal(donationId-1)
        console.log("proposal")
        console.log(proposal)

        const b2 = await token.balanceOf(owner.address)
        console.log(b2)
    }


    // 기부 리스트 조회
    {
      const list = await gps.getDonationList()
      console.log(list)
    }

    {
      console.log("Get donation by key")
      const list = await gps.getDonationBykey("ipfs/url")
      console.log(list)
    }

    //  기부 수령하기
    {
        const b1 = await usdc.balanceOf(recipient.address)
        console.log(b1)

        await vault.claim(donationId-1)

        const b2 = await usdc.balanceOf(recipient.address)
        console.log(b2)
    }

    {
      console.log("Get donation by key")
      const list = await gps.getDonationBykey("ipfs/url")
      console.log(list)
    }
  });
});
