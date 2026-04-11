// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IZKVerifier} from "./interfaces/IZKVerifier.sol";
import {StakingVault} from "./StakingVault.sol";
import {ChallengeRegistry} from "./ChallengeRegistry.sol";
import {Sortition} from "./Sortition.sol";
import {AttestationStore} from "./AttestationStore.sol";

/// @title AttestationEngine — orchestrator for submit / vote / finalize
/// @notice D2 binding revision: this contract computes
///         bindingHash = keccak256(abi.encode(msg.sender, challengeId))
///         and prepends it as public signal 0 to the circuit's signals before
///         calling the verifier. Circuits expose bindingHash as a pass-through
///         public input — no keccak in Circom.
contract AttestationEngine {
    uint256 public constant VOTE_WINDOW = 24 hours;
    uint256 public constant QUORUM_BPS = 6_666;  // 66.66%
    uint256 public constant SLASH_EQUIVOCATION_BPS = 500; // 5%
    uint256 public constant SLASH_LIVENESS_BPS = 100;     // 1%
    uint256 public constant BPS = 10_000;

    enum ClaimStatus {SUBMITTED, COMMITTEE_DRAWN, FINALIZED_ACCEPT, FINALIZED_REJECT, EXPIRED}

    struct Claim {
        uint256 id;
        uint256 challengeId;
        address claimant;
        uint64 submissionBlock;
        uint64 voteDeadline;  // set on drawCommittee
        bytes32 artifactCID;
        ClaimStatus status;
        uint8 yesVotes;
        uint8 noVotes;
    }

    ChallengeRegistry public immutable registry;
    StakingVault public immutable vault;
    Sortition public immutable sortition;
    AttestationStore public immutable store;

    address public governance;

    mapping(uint256 => Claim) private claims;
    mapping(uint256 => address[]) private committees; // claimId → committee
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => bool)) public isMember;
    /// @dev Per-claim per-validator recorded vote direction (true = yes).
    mapping(uint256 => mapping(address => bool)) private voterYes;

    uint256 public nextClaimId = 1;

    event ClaimSubmitted(
        uint256 indexed claimId,
        uint256 indexed challengeId,
        address indexed claimant,
        uint64 submissionBlock,
        bytes32 artifactCID
    );
    event CommitteeDrawn(uint256 indexed claimId, address[] committee, uint64 voteDeadline);
    event Voted(uint256 indexed claimId, address indexed validator, bool yes);
    event ClaimFinalized(uint256 indexed claimId, bool accepted);
    event GovernanceTransferred(address indexed from, address indexed to);

    error NotGovernance();
    error ChallengeNotActive();
    error InvalidProof();
    error UnknownClaim();
    error CommitteeAlreadyDrawn();
    error CommitteeNotDrawn();
    error NotCommitteeMember();
    error AlreadyVoted();
    error VoteClosed();
    error VoteStillOpen();
    error ZeroAddress();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    constructor(
        ChallengeRegistry _registry,
        StakingVault _vault,
        Sortition _sortition,
        AttestationStore _store,
        address _governance
    ) {
        if (_governance == address(0)) revert ZeroAddress();
        registry = _registry;
        vault = _vault;
        sortition = _sortition;
        store = _store;
        governance = _governance;
    }

    function transferGovernance(address newGov) external onlyGovernance {
        if (newGov == address(0)) revert ZeroAddress();
        address old = governance;
        governance = newGov;
        emit GovernanceTransferred(old, newGov);
    }

    /// @notice Pure helper for off-chain tooling to derive the bindingHash the
    ///         contract will compute for a claimant/challengeId pair.
    function bindingHashOf(address claimant, uint256 challengeId)
        external
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(claimant, challengeId))) & ((uint256(1) << 248) - 1);
    }

    function submitClaim(
        uint256 challengeId,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata circuitSignals,
        bytes32 artifactCID
    ) external returns (uint256 claimId) {
        ChallengeRegistry.Challenge memory ch = registry.getChallenge(challengeId);
        if (ch.status != ChallengeRegistry.Status.ACTIVE) revert ChallengeNotActive();

        // D2 revision: prepend contract-computed bindingHash as public signal 0
        // Mask to 248 bits so the value is guaranteed to fit in the BN254
// scalar field (~254 bits). 248 bits of collision resistance is still
// vastly above any practical threshold.
uint256 bindingHash = uint256(keccak256(abi.encode(msg.sender, challengeId))) & ((uint256(1) << 248) - 1);
        uint256 n = circuitSignals.length;
        uint256[] memory boundSignals = new uint256[](n + 1);
        boundSignals[0] = bindingHash;
        for (uint256 i = 0; i < n; i++) {
            boundSignals[i + 1] = circuitSignals[i];
        }

        if (!IZKVerifier(ch.verifier).verifyProof(a, b, c, boundSignals)) revert InvalidProof();

        claimId = nextClaimId++;
        claims[claimId] = Claim({
            id: claimId,
            challengeId: challengeId,
            claimant: msg.sender,
            submissionBlock: uint64(block.number),
            voteDeadline: 0,
            artifactCID: artifactCID,
            status: ClaimStatus.SUBMITTED,
            yesVotes: 0,
            noVotes: 0
        });

        emit ClaimSubmitted(claimId, challengeId, msg.sender, uint64(block.number), artifactCID);
    }

    function drawCommittee(uint256 claimId) external {
        Claim storage cl = claims[claimId];
        if (cl.id == 0) revert UnknownClaim();
        if (cl.status != ClaimStatus.SUBMITTED) revert CommitteeAlreadyDrawn();

        address[] memory committee = sortition.drawCommittee(cl.submissionBlock);

        committees[claimId] = committee;
        for (uint256 i = 0; i < committee.length; i++) {
            isMember[claimId][committee[i]] = true;
        }

        cl.status = ClaimStatus.COMMITTEE_DRAWN;
        cl.voteDeadline = uint64(block.timestamp + VOTE_WINDOW);

        emit CommitteeDrawn(claimId, committee, cl.voteDeadline);
    }

    function vote(uint256 claimId, bool yes) external {
        Claim storage cl = claims[claimId];
        if (cl.id == 0) revert UnknownClaim();
        if (cl.status != ClaimStatus.COMMITTEE_DRAWN) revert CommitteeNotDrawn();
        if (block.timestamp > cl.voteDeadline) revert VoteClosed();
        if (!isMember[claimId][msg.sender]) revert NotCommitteeMember();
        if (hasVoted[claimId][msg.sender]) revert AlreadyVoted();

        hasVoted[claimId][msg.sender] = true;
        voterYes[claimId][msg.sender] = yes;
        if (yes) cl.yesVotes++;
        else cl.noVotes++;

        emit Voted(claimId, msg.sender, yes);
    }

    function finalize(uint256 claimId) external {
        Claim storage cl = claims[claimId];
        if (cl.id == 0) revert UnknownClaim();
        if (cl.status != ClaimStatus.COMMITTEE_DRAWN) revert CommitteeNotDrawn();
        if (block.timestamp <= cl.voteDeadline) revert VoteStillOpen();

        address[] storage committee = committees[claimId];
        uint256 size = committee.length;

        // Quorum based on YES votes over committee size (silent = NO)
        uint256 quorumMet = (uint256(cl.yesVotes) * BPS) / size;
        bool accepted = quorumMet >= QUORUM_BPS;

        // Liveness slash for no-shows
        for (uint256 i = 0; i < size; i++) {
            address v = committee[i];
            if (!hasVoted[claimId][v]) {
                uint256 stk = vault.stakeOf(v);
                if (stk > 0) {
                    vault.slash(v, (stk * SLASH_LIVENESS_BPS) / BPS);
                }
            }
        }

        // Equivocation slash for voters whose direction differs from final outcome
        for (uint256 i = 0; i < size; i++) {
            address v = committee[i];
            if (!hasVoted[claimId][v]) continue;
            if (voterYes[claimId][v] != accepted) {
                uint256 stk = vault.stakeOf(v);
                if (stk > 0) {
                    vault.slash(v, (stk * SLASH_EQUIVOCATION_BPS) / BPS);
                }
            }
        }

        cl.status = accepted ? ClaimStatus.FINALIZED_ACCEPT : ClaimStatus.FINALIZED_REJECT;

        if (accepted) {
            ChallengeRegistry.Challenge memory ch = registry.getChallenge(cl.challengeId);
            store.record(cl.claimant, cl.challengeId, ch.domain, ch.signalWeight, cl.artifactCID);
        }

        emit ClaimFinalized(claimId, accepted);
    }

    function committeeOf(uint256 claimId) external view returns (address[] memory) {
        return committees[claimId];
    }

    function getClaim(uint256 claimId) external view returns (Claim memory) {
        return claims[claimId];
    }

    function voterDirection(uint256 claimId, address v) external view returns (bool) {
        return voterYes[claimId][v];
    }
}
