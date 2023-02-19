// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/utils/Counters.sol";

import "./GPVault.sol";
import "./GPGovernance.sol";
import "./GPBadge.sol";

import "hardhat/console.sol";


// 조회용 데이터를 만들어 준다, storage 변경이 있는 donation, vote 등은 실제 컨트랙트 주소에 요청 해야한다
contract GPService {
    using Counters for Counters.Counter;
    struct DonationInfo {
        DonationBaseInfo add;
        uint currentAmount;
        uint maxAmount;
        string ipfsKey;
        uint start;
        uint end;
    }

    struct DonationBaseInfo {
        uint donateId;
        uint proposalId;
        uint voteFor;
        uint voteAgainst;
        uint createdTime;
        uint period;
        uint canVote;
    }

    struct ProposalInfo {
        uint createTime;
        uint period;
    }

    enum Status {
        Voting, // 0 
        VoteDefeated, // 1
        VoteSucceeded, // 2
        DonateWaiting, // 3
        Donating, // 4
        DonateDefeated, // 5
        DonateSucceeded, // 6
        DonateComplete, // 7
        DonateRefunded, // 8
        Unknown // 9
    }

    GPGovernance private governance;
    GPVault private vault;
    GPBadge private badge;
    Counters.Counter private counter;

    uint blockTime;
    uint[] private targetAmounts = [10 ether / 1e12, 100 ether / 1e12, 1000 ether / 1e12];
    uint[] private targetPeriods = [2 weeks, 4 weeks, 12 weeks ];

    mapping(bytes32 => uint) ipfsKeys;
    mapping(uint => uint) addProposalIds; // donationId => proposalId
    mapping(uint => ProposalInfo) addProposalInfo; // proposalId => info

    constructor(GPGovernance _governance, GPVault _vault, uint _blockTime) {
        governance = _governance;
        vault = _vault;
        blockTime = _blockTime;
    }

    function getAddProposalIds(uint donationId)
        external
        view
        returns (uint)
    {
        return addProposalIds[donationId];
    }

    function addLength()
        external
        view
        returns (uint)
    {
        return counter.current();
    }

    function getDonationBykey(string memory key)
        external
        view
        returns (DonationInfo memory)
    {
        uint donationId = ipfsKeys[keccak256(bytes(key))];
        return getDonation(donationId);
    }

    function getDonation(uint donationId)
        public
        view
        returns (DonationInfo memory)
    {
        DonationInfo memory info;
        (uint current, uint max, string memory key, uint start, uint end) = vault.getDonateInfo(donationId);
        info.currentAmount = current;
        info.maxAmount = max;
        info.ipfsKey = key;
        info.start = start;
        info.end = end;
        info.add = getAddDonation(donationId);

        return info;
    }

    function getDonationList()
        external
        view
        returns (DonationInfo[] memory)
    {
        DonationInfo[] memory infos = new DonationInfo[](counter.current());
        for(uint i = 0; i < counter.current(); i++) {
            infos[i] = getDonation(i);
        }

        return infos;
    }

    function getAddDonation(uint donationId) 
        public
        view
        returns (DonationBaseInfo memory info)
    {
        uint proposalId = addProposalIds[donationId];
        ProposalInfo memory p = addProposalInfo[proposalId];
        (uint voteAgainst, uint voteFor,) = governance.proposalVotes(proposalId);
        info.donateId = donationId;
        info.proposalId = proposalId;
        info.voteFor = voteFor;
        info.voteAgainst = voteAgainst;
        info.canVote = uint(getState(donationId));
        info.createdTime = p.createTime;
        info.period = p.period;
    }
    
    function getTargetPeriods()
        external
        view
        returns(uint[] memory)
    {
        // 목표 일정 프리셋 조회
        return targetPeriods;
    }

    function getTargetAmounts()
        external
        view
        returns(uint[] memory)
    {
        // 목표 금액 프리셋 조회
        return targetAmounts;
    }

    function addDonationProposal(uint amount, uint period, address recipient, string memory url) 
        external
        returns (uint)
    {
        //governance 호출 하여 기부 요청 안건 등록
        uint donationId = counter.current();
        address[] memory l1 = new address[](1);
        l1[0] = address(vault);
        uint[] memory l2 = new uint[](1);
        l2[0] = 0;
        bytes[] memory l3 = new bytes[](1);
        l3[0]  = abi.encodeWithSelector(vault.startDonateProposal.selector, donationId);
        uint proposeId = governance.propose(l1, l2, l3, "");
        addProposalIds[donationId] = proposeId;
        addProposalInfo[proposeId] = ProposalInfo({
            createTime: block.timestamp,
            period: governance.votingPeriod() * blockTime
        });

        ipfsKeys[keccak256(bytes(url))] = donationId;
        counter.increment();
        vault.addDonateProposal(donationId, amount, block.timestamp, block.timestamp + 24 hours + period, recipient, url);
        return proposeId;
    }

    function executeAddDonationProposal(uint donationId) 
        external
    {
        //governance 호출 하여 기부 요청 안건 등록
        address[] memory l1 = new address[](1);
        l1[0] = address(vault);
        uint[] memory l2 = new uint[](1);
        l2[0] = 0;
        bytes[] memory l3 = new bytes[](1);
        l3[0]  = abi.encodeWithSelector(vault.startDonateProposal.selector, donationId);
        governance.execute(l1, l2, l3, keccak256(bytes("")));
    }

    // abort 없애고
    // state 정리
    function getState(uint donationId) 
        public
        view
        returns (Status status)
    {
        IGovernor.ProposalState state = governance.state(addProposalIds[donationId]);
        if(state == IGovernor.ProposalState.Active) { // ProposalState.Active
            return Status.Voting;
        } else if (state == IGovernor.ProposalState.Succeeded) { // ProposalState.Succeeded 
            return Status.VoteSucceeded;
        } else if (state == IGovernor.ProposalState.Defeated) { // ProposalState.Defeated
            return Status.VoteDefeated;
        } else if (state == IGovernor.ProposalState.Executed) { // ProposalState. Executed
            IGPVault.DonateStatus dState = vault.getCurrentStatus(donationId);
            if (dState == IGPVault.DonateStatus.Waiting) {
                return Status.DonateWaiting;
            } else if (dState == IGPVault.DonateStatus.Proceeding) {
                return Status.Donating;
            } else if (dState == IGPVault.DonateStatus.Succeeded) {
                return Status.DonateSucceeded;
            } else if (dState == IGPVault.DonateStatus.Failed) {
                return Status.DonateDefeated;
            } else if (dState == IGPVault.DonateStatus.Completed) {
                return Status.DonateComplete;
            } else if (dState == IGPVault.DonateStatus.Refunded) {
                return Status.DonateRefunded;
            }
        } else { // Pending, Canceled, Queued, Expired
            return Status.Unknown;
        }
    }
}