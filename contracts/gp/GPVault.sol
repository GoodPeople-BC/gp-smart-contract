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
    mapping(uint => mapping(address => uint)) donateAmounts; // did => eoa => amount
    mapping(uint => address[]) donators; // did => donators address

    constructor(address _gpFund, IGPToken _gpToken, IERC20 _usdc, uint _gpBP) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        gpFund = _gpFund;
        gpBP = _gpBP;
        gpToken = _gpToken;
        usdc = _usdc;
    }

    function addGovernanceRole(address governance) 
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole(GOVR_ROLE, governance);
    }

    function getDonateInfo(uint donateId)
        external
        view
        returns (uint, uint, string memory)
    {
        DonateProposal memory p = donations[donationIndex[donateId]];
        return (p.currentAmount, p.maxAmount, p.desc);
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
        
        uint current = block.timestamp;
        if (current < p.start) {
            return DonateStatus.Waiting;
        } else if (p.start <= current && current < p.end) {
            if (p.currentAmount < p.maxAmount) {
                return DonateStatus.Proceeding;
            } else {
                return DonateStatus.Succeeded;
            }
        } else {
            if (p.currentAmount < p.maxAmount) {
                return DonateStatus.Failed;
            } else {
                return DonateStatus.Succeeded;
            }
        }
    }

    function getDonationStatus(uint donateId) 
        external
        view
        returns(DonationStatus status) 
    {
        return donations[donationIndex[donateId]].status;
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
            recipient: recipient,
            status: DonationStatus.Vote,
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
        require(p.status == DonationStatus.Vote, "V: invalid proposal status");
        p.status = DonationStatus.Idle;
        emit DonationStarted(p.donateId, p.recipient, msg.sender, p.maxAmount);
    }

    // from governance excutions
    function abortDonateProposal(uint donateId)
        external
        onlyRole(GOVR_ROLE)
    {
        DonateProposal storage p = donations[donationIndex[donateId]];
        require(p.status == DonationStatus.Idle, "V: invalid proposal status");
        require(getCurrentStatus(donateId) != DonateStatus.Waiting, "V: invalid donate status");

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
        p.status = DonationStatus.Aborted;
        p.currentAmount = 0;

        emit DonationAborted(p.donateId, p.recipient, msg.sender, p.maxAmount);
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
        require(p.status == DonationStatus.Idle, "V: invalid proposal status");
        require(getCurrentStatus(donateId) == DonateStatus.Succeeded, "V: invalid donate status");
        uint fee = p.maxAmount * 100 / 1000;
        require(usdc.transfer(gpFund, fee), "V:failed to fund transfer");
        require(usdc.transfer(p.recipient, p.maxAmount - fee), "V: failed to recipient transfer");
        p.status = DonationStatus.Completed;
        p.currentAmount = 0;
        p.claimed = true;
        // todo badge
        emit Claimed(p.donateId, p.recipient, p.maxAmount);
    }

    // need to approve from msg sender
    function donate(uint donateId, uint amount) 
        external
        returns (uint transferAmount)
    {
        DonateProposal storage p = donations[donationIndex[donateId]];
        require(p.status == DonationStatus.Idle, "V: invalid proposal status");
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
        require(p.status == DonationStatus.Idle, "V: invalid proposal status");
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
        p.status = DonationStatus.Aborted;
        p.currentAmount = 0;
    }
}