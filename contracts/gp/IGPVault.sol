// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGPVault {
    struct DonateProposal {
        uint donateId;
        uint currentAmount;
        uint maxAmount;
        uint32 start;
        uint32 end;
        bool claimed;
        bool refunded;
        address recipient;
        string desc;
        ProposalStatus status;
    }

    enum DonateStatus {
        Waiting, // not yet started
        Proceeding, // can donate
        Succeeded, // reached to maxAmount
        Failed, // not reached to maxAmount
        Completed,
        Refunded
    }

    enum ProposalStatus {
        Vote,
        Executed
    }

    event DonationAdded(uint indexed donateId, address indexed recipient, address from, uint Amount);
    event DonationStarted(uint indexed donateId, address indexed recipient, address from, uint Amount);
    event Claimed(uint indexed donateId, address indexed recipient, uint amount);
    event Refunded(uint indexed donateId, address indexed refundAddress, uint amount);
    event Withdraw(address indexed from, address indexed to, uint amount);
    event Donated(uint indexed donateId, address indexed from, uint amount);
    event Sponsored(address indexed sponsor, uint amount);

    function getCurrentStatus(uint donateId) external view returns (DonateStatus status);
    function changeGpBp(uint _gpBP) external;
    function addDonateProposal(uint donateId, uint maxAmount, uint start, uint end, address recipient, string memory desc) external;
    function claim(uint donateId) external;
    function emgergencyWithdraw(uint amount) external;
    function donate(uint donateId, uint amount) external returns (uint transferAmount);
    function sponsorGp(uint amount) external;
    function refund(uint donateId) external;
}