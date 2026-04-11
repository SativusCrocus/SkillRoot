// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/// @title Governance — minimal on-chain proposal/vote/execute
/// @notice No timelock in v0 (deferred to v1 per ROADMAP.md). Uses
///         ERC20Votes.getPastVotes at a snapshot block for quorum math.
contract Governance {
    uint256 public constant VOTING_PERIOD = 5 days;
    uint256 public constant QUORUM_BPS = 400; // 4%
    uint256 public constant BPS = 10_000;

    enum ProposalState {PENDING, ACTIVE, SUCCEEDED, DEFEATED, EXECUTED}

    struct Proposal {
        uint256 id;
        address proposer;
        address target;
        bytes data;
        uint256 value;
        uint48 snapshotClock;
        uint48 voteEnd;
        uint256 forVotes;
        uint256 againstVotes;
        ProposalState state;
    }

    ERC20Votes public immutable token;

    mapping(uint256 => Proposal) private _proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public nextProposalId = 1;

    function proposals(uint256 id) external view returns (Proposal memory) {
        return _proposals[id];
    }

    event ProposalCreated(
        uint256 indexed id,
        address indexed proposer,
        address target,
        bytes data,
        uint256 value,
        uint48 voteEnd
    );
    event VoteCast(uint256 indexed id, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed id, bool success, bytes returnData);

    error UnknownProposal();
    error WrongState();
    error VotingClosed();
    error VotingOpen();
    error AlreadyVoted();
    error NoVotingPower();
    error QuorumNotMet();
    error Defeated();
    error ExecutionFailed(bytes returnData);

    constructor(ERC20Votes _token) {
        token = _token;
    }

    function propose(address target, bytes calldata data, uint256 value)
        external
        returns (uint256 id)
    {
        uint48 snap = token.clock() - 1; // snapshot immediately before now
        id = nextProposalId++;
        _proposals[id] = Proposal({
            id: id,
            proposer: msg.sender,
            target: target,
            data: data,
            value: value,
            snapshotClock: snap,
            voteEnd: uint48(block.timestamp + VOTING_PERIOD),
            forVotes: 0,
            againstVotes: 0,
            state: ProposalState.ACTIVE
        });
        emit ProposalCreated(id, msg.sender, target, data, value, _proposals[id].voteEnd);
    }

    function castVote(uint256 id, bool support) external {
        Proposal storage p = _proposals[id];
        if (p.id == 0) revert UnknownProposal();
        if (p.state != ProposalState.ACTIVE) revert WrongState();
        if (block.timestamp > p.voteEnd) revert VotingClosed();
        if (hasVoted[id][msg.sender]) revert AlreadyVoted();

        uint256 weight = token.getPastVotes(msg.sender, p.snapshotClock);
        if (weight == 0) revert NoVotingPower();

        hasVoted[id][msg.sender] = true;
        if (support) p.forVotes += weight;
        else p.againstVotes += weight;

        emit VoteCast(id, msg.sender, support, weight);
    }

    function execute(uint256 id) external payable {
        Proposal storage p = _proposals[id];
        if (p.id == 0) revert UnknownProposal();
        if (p.state != ProposalState.ACTIVE) revert WrongState();
        if (block.timestamp <= p.voteEnd) revert VotingOpen();

        uint256 totalSupply = token.getPastTotalSupply(p.snapshotClock);
        uint256 quorumNeeded = (totalSupply * QUORUM_BPS) / BPS;
        if (p.forVotes < quorumNeeded) revert QuorumNotMet();
        if (p.forVotes <= p.againstVotes) revert Defeated();

        p.state = ProposalState.EXECUTED;

        (bool ok, bytes memory ret) = p.target.call{value: p.value}(p.data);
        if (!ok) revert ExecutionFailed(ret);

        emit ProposalExecuted(id, ok, ret);
    }

    receive() external payable {}
}
