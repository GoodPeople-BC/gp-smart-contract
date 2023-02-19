// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IGPVault.sol";
import "./IGPToken.sol";

contract GPVault is IGPVault, AccessControl {
    bytes32 public constant GOVR_ROLE = keccak256("GOVR_ROLE");

    uint public gpBP;
    address public gpFund;
    IGPToken public gpToken; // IGTToken for mint
    IERC20 public usdc;

    DonateProposal[] public donations;
    mapping(uint => uint) public donationIndex; // did => index
    mapping(uint => mapping(address => uint)) public donateAmounts; // did => eoa => amount
    mapping(uint => address[]) public donators; // did => donators address

    constructor(address _gpFund, IGPToken _gpToken, IERC20 _usdc, uint _gpBP) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        gpFund = _gpFund;
        gpBP = _gpBP;
        gpToken = _gpToken;
        usdc = _usdc;
    }

    // function changeProposalStatus(uint donateId, ProposalStatus status) 
    //     external
    // {
    //     DonateProposal storage p = donations[donationIndex[donateId]];
    //     p.status = status;
    // }

    // function changeDonatePeriod(uint donateId, uint start, uint end, uint amount, bool r, bool c) 
    //     external
    // {
    //     DonateProposal storage p = donations[donationIndex[donateId]];
    //     p.currentAmount = amount;
    //     p.start = uint32(start);
    //     p.end = uint32(end);
    //     p.refunded = r;
    //     p.claimed = c;
    // }

    function addGovernanceRole(address governance) 
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole(GOVR_ROLE, governance);
    }

    function getDonateInfo(uint donateId)
        external
        view
        returns (uint, uint, string memory, uint, uint)
    {
        DonateProposal memory p = donations[donationIndex[donateId]];
        return (p.currentAmount, p.maxAmount, p.desc, p.start, p.end);
    }

   function getDonateProposal(uint donateId)
        external
        view
        returns (DonateProposal memory)
    {
        return donations[donationIndex[donateId]];
    }
    
    function getCurrentStatus(uint donateId)
        public
        view
        returns (DonateStatus status)
    {
        DonateProposal memory p = donations[donationIndex[donateId]];
        require(p.recipient != address(0), "V: invalid proposal id");

        if (p.claimed) {
            return DonateStatus.Completed;
        }
        
        if (p.refunded) {
            return DonateStatus.Refunded;
        }

        if (p.currentAmount >= p.maxAmount) {
            return DonateStatus.Succeeded;
        }

        uint current = block.timestamp;
        if (current < p.start) {
            return DonateStatus.Waiting;
        } else if (p.start <= current && current < p.end) {
            return DonateStatus.Proceeding;
        } else {
            return DonateStatus.Failed;
        }
    }

    // move to GPToken.sol after confirm token economy formular
    function changeGpBp(uint _gpBP)
        external
        onlyRole(GOVR_ROLE)
    {
        gpBP = _gpBP;
    }

    // from governance excution
    function addDonateProposal(uint donateId, uint maxAmount, uint start, uint end, address recipient, string memory desc)
        external 
        onlyRole(GOVR_ROLE)
    {
        require(donations.length == donateId, "V: invalid donation id");
        DonateProposal memory p = DonateProposal({
            donateId: donateId,
            currentAmount: 0,
            maxAmount: maxAmount,
            start: uint32(start),
            end: uint32(end),
            claimed: false,
            refunded: false,
            recipient: recipient,
            status: ProposalStatus.Vote,
            desc: desc
        });
        donationIndex[donateId] = donations.length;
        donations.push(p);

        emit DonationAdded(p.donateId, p.recipient, msg.sender, p.maxAmount);
    }

    function startDonateProposal(uint donateId)
        external 
        onlyRole(GOVR_ROLE)
    {
        DonateProposal storage p = donations[donationIndex[donateId]];
        require(p.status == ProposalStatus.Vote, "V: invalid proposal status");
        p.status = ProposalStatus.Executed;
        emit DonationStarted(p.donateId, p.recipient, msg.sender, p.maxAmount);
    }

    function emgergencyWithdraw(uint amount) 
        external 
        onlyRole(GOVR_ROLE)
    {
        require(usdc.transfer(gpFund, amount), "V: failed to transfer in emgergencyWithdraw");
        emit Withdraw(msg.sender, gpFund, amount);
    }

    function claim(uint donateId)
        external
    {
        DonateProposal storage p = donations[donationIndex[donateId]];
        require(p.status == ProposalStatus.Executed, "V: invalid proposal status");
        require(getCurrentStatus(donateId) == DonateStatus.Succeeded, "V: invalid donate status");
        uint fee = p.maxAmount * 100 / 1000;
        require(usdc.transfer(gpFund, fee), "V:failed to fund transfer");
        require(usdc.transfer(p.recipient, p.maxAmount - fee), "V: failed to recipient transfer");
        p.currentAmount = 0;
        p.claimed = true;
        emit Claimed(p.donateId, p.recipient, p.maxAmount);
    }

    // need to approve from msg sender
    function donate(uint donateId, uint amount) 
        external
        returns (uint transferAmount)
    {
        DonateProposal storage p = donations[donationIndex[donateId]];
        require(p.status == ProposalStatus.Executed, "V: invalid proposal status");
        require(getCurrentStatus(donateId) == DonateStatus.Proceeding, "V: invalid donate status");

        uint remainAmount = p.maxAmount - p.currentAmount;
        transferAmount = remainAmount < amount? remainAmount : amount;
        require(usdc.transferFrom(msg.sender, address(this), transferAmount), "V: failed to transferFrom");

        if (donateAmounts[donateId][msg.sender] == 0) {
            donators[donateId].push(msg.sender);
        } 

        donateAmounts[donateId][msg.sender] += transferAmount;
        p.currentAmount += transferAmount;

        require(gpToken.mint(msg.sender, transferAmount * gpBP / 10000 * 1e12), "V: failed to transfer gp");
        emit Donated(p.donateId, msg.sender, amount);
    }

    // need to approve from msg sender
    function sponsorGp(uint amount)
        external
    {
        require(usdc.transferFrom(msg.sender, gpFund, amount), "V: failed to transferFrom");
        require(gpToken.mint(msg.sender, amount * gpBP / 10000 * 1e12), "V: failed to transfer gp");
        emit Sponsored(msg.sender, amount);
    }

    function refund(uint donateId)
        external
    {
        DonateProposal storage p = donations[donationIndex[donateId]];
        require(p.status == ProposalStatus.Executed, "V: invalid proposal status");
        require(getCurrentStatus(donateId) == DonateStatus.Failed, "V: invalid donate status");

        uint refundAmount = 0;
        for (uint i = 0; i < donators[donateId].length; i++) {
            address donator = donators[donateId][i];
            uint donateAmount = donateAmounts[donateId][donator];
            require(usdc.transfer(donator, donateAmount), "V: failed to transfer");

            refundAmount += donateAmount;
            donateAmounts[donateId][donator] = 0;
            emit Refunded(p.donateId, donator, donateAmount);
        }

        require(p.currentAmount == refundAmount, "V: failed to verfiy refund amount");
        p.currentAmount = 0;
        p.refunded = true;
    }
}