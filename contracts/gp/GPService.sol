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
        DonationBaseInfo abort;
        bool hasAbort;
        uint currentAmount;
        uint maxAmount;
        string ipfsKey;
        uint governanceStatus;
        uint donationStatus;
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

    GPGovernance private governance;
    GPVault private vault;
    GPBadge private badge;
    Counters.Counter private counter;
    // Counters.Counter private abortCounter;

    uint[] private targetAmounts = [10 ether / 1e12, 100 ether / 1e12, 1000 ether / 1e12];
    uint[] private targetPeriods = [2 weeks, 4 weeks, 12 weeks ];

    mapping(bytes32 => uint) ipfsKeys;
    mapping(uint => uint) addProposalIds; // donationId => proposalId
    mapping(uint => ProposalInfo) addProposalInfo; // proposalId => info
    mapping(uint => uint) abortProposalIds; // donationId => proposalId
    mapping(uint => ProposalInfo) abortProposalInfo; // proposalId => info

    constructor(GPGovernance _governance, GPVault _vault) {
        governance = _governance;
        vault = _vault;
    }

    function getAddProposalIds(uint donationId)
        external
        view
        returns (uint)
    {
        return addProposalIds[donationId];
    }

    function getAbortProposalIds(uint donationId)
        external
        view
        returns (uint)
    {
        return abortProposalIds[donationId];
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
        (uint current, uint max, string memory key) = vault.getDonateInfo(donationId);
        info.donationStatus = uint(vault.getCurrentStatus(donationId));
        info.governanceStatus = uint(vault.getDonationStatus(donationId));
        info.currentAmount = current;
        info.maxAmount = max;
        info.ipfsKey = key;

        info.add = getAddDonation(donationId);
        if (abortProposalIds[donationId] != 0) {
            info.hasAbort = true;
            info.abort = getAbortDonation(donationId);
        }

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
        uint state = uint(governance.state(proposalId));
        (uint voteAgainst, uint voteFor,) = governance.proposalVotes(proposalId);
        info.donateId = donationId;
        info.proposalId = proposalId;
        info.voteFor = voteFor;
        info.voteAgainst = voteAgainst;
        info.canVote = getState(state);
        info.createdTime = p.createTime;
        info.period = p.period;
    }

    function getAbortDonation(uint donationId) 
        public
        view
        returns (DonationBaseInfo memory info)
    {
        uint proposalId = abortProposalIds[donationId];
        ProposalInfo memory p = abortProposalInfo[proposalId];
        uint state = uint(governance.state(proposalId));
        (uint voteAgainst, uint voteFor,) = governance.proposalVotes(proposalId);
        info.donateId = donationId;
        info.proposalId = proposalId;
        info.voteFor = voteFor;
        info.voteAgainst = voteAgainst;
        info.canVote = getState(state);
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
            period: governance.votingPeriod()
        });

        ipfsKeys[keccak256(bytes(url))] = donationId;
        counter.increment();
        vault.addDonateProposal(donationId, amount, block.timestamp + 24 hours, block.timestamp + 24 hours + period, recipient, url);
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

    function hashProp(uint donationId)
        external
        view
        returns (uint)
    {
        address[] memory l1 = new address[](1);
        l1[0] = address(vault);
        uint[] memory l2 = new uint[](1);
        l2[0] = 0;
        bytes[] memory l3 = new bytes[](1);
        l3[0]  = abi.encodeWithSelector(vault.abortDonateProposal.selector, donationId);
        return governance.hashProposal(l1, l2, l3, "");
    }

    function abortDonationProposal(uint donationId) 
        external
        returns (uint)
    {
        //donationID validation
        //governance에 등록된 거버 넌스 안건 리스트 조회
        address[] memory l1 = new address[](1);
        l1[0] = address(vault);
        uint[] memory l2 = new uint[](1);
        l2[0] = 0;
        bytes[] memory l3 = new bytes[](1);
        l3[0]  = abi.encodeWithSelector(vault.abortDonateProposal.selector, donationId);
        uint proposeId = governance.propose(l1, l2, l3, "");
        abortProposalIds[donationId] = proposeId;
        abortProposalInfo[proposeId] = ProposalInfo({
            createTime: block.timestamp,
            period: governance.votingPeriod()
        });

        return proposeId;
    }

    function executeAbortDonationProposal(uint donationId) 
        external
    {
        //governance 호출 하여 기부 요청 안건 등록
        address[] memory l1 = new address[](1);
        l1[0] = address(vault);
        uint[] memory l2 = new uint[](1);
        l2[0] = 0;
        bytes[] memory l3 = new bytes[](1);
        l3[0]  = abi.encodeWithSelector(vault.abortDonateProposal.selector, donationId);
        governance.execute(l1, l2, l3, "");
    }

    function getState(uint state) 
        public
        pure
        returns (uint)
    {
        if(state == 1) { // ProposalState.Active
            return 0;
        } else if (state == 3) { // ProposalState.Defeated
            return 1;
        } else if (state == 4) { // ProposalState.Succeeded
            return 2;
        } else if (state == 7) { // ProposalState. Executed
            return 3;
        } else { // Pending, Canceled, Queued, Expired
            return 4;
        }
    }
}