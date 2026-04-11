// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ChallengeRegistry} from "./ChallengeRegistry.sol";

/// @title AttestationStore — per-claimant per-domain attestation records
/// @notice Writes are gated on the AttestationEngine. Reads are public and
///         compute a time-decayed weight per attestation. Half-lives differ
///         by domain.
contract AttestationStore {
    // Half-lives in seconds, keyed by ChallengeRegistry.Domain enum values
    uint256 public constant HL_ALGO         = 730 days;
    uint256 public constant HL_FORMAL_VER   = 1095 days;
    uint256 public constant HL_APPLIED_MATH = 1095 days;
    uint256 public constant HL_SEC_CODE     = 365 days;

    struct Record {
        uint256 challengeId;
        ChallengeRegistry.Domain domain;
        uint64 timestamp;
        uint256 baseWeight;
        bytes32 artifactCID;
    }

    address public governance;
    address public engine;

    mapping(address => Record[]) private records;

    event EngineSet(address indexed engine);
    event GovernanceTransferred(address indexed from, address indexed to);
    event AttestationRecorded(
        address indexed claimant,
        uint256 indexed challengeId,
        ChallengeRegistry.Domain domain,
        uint256 baseWeight,
        bytes32 artifactCID
    );

    error NotGovernance();
    error NotEngine();
    error EngineAlreadySet();
    error ZeroAddress();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    modifier onlyEngine() {
        if (msg.sender != engine) revert NotEngine();
        _;
    }

    constructor(address _governance) {
        if (_governance == address(0)) revert ZeroAddress();
        governance = _governance;
    }

    function setEngine(address _engine) external onlyGovernance {
        if (engine != address(0)) revert EngineAlreadySet();
        if (_engine == address(0)) revert ZeroAddress();
        engine = _engine;
        emit EngineSet(_engine);
    }

    function transferGovernance(address newGov) external onlyGovernance {
        if (newGov == address(0)) revert ZeroAddress();
        address old = governance;
        governance = newGov;
        emit GovernanceTransferred(old, newGov);
    }

    function record(
        address claimant,
        uint256 challengeId,
        ChallengeRegistry.Domain domain,
        uint256 baseWeight,
        bytes32 artifactCID
    ) external onlyEngine {
        records[claimant].push(Record({
            challengeId: challengeId,
            domain: domain,
            timestamp: uint64(block.timestamp),
            baseWeight: baseWeight,
            artifactCID: artifactCID
        }));
        emit AttestationRecorded(claimant, challengeId, domain, baseWeight, artifactCID);
    }

    /// @notice Compute decayed score per domain for a claimant.
    /// @dev Discrete half-life: w · 2^(-floor(Δ/H)) · (1 - (Δ mod H)/(2H))
    ///      Avoids fixed-point libraries at the cost of minor piecewise-linear steps.
    function scoresOf(address claimant) external view returns (uint256[4] memory scores) {
        Record[] storage rs = records[claimant];
        uint256 nowTs = block.timestamp;

        for (uint256 i = 0; i < rs.length; i++) {
            Record storage r = rs[i];
            uint256 age = nowTs - r.timestamp;
            uint256 hl = _halfLife(r.domain);

            uint256 shifts = age / hl;
            uint256 modAge = age % hl;

            // Cap shifts to prevent astronomical right-shifts
            if (shifts > 64) {
                continue;
            }

            // w · 2^(-shifts) · (1 - modAge / (2 * hl))
            // = (w >> shifts) · (2·hl - modAge) / (2·hl)
            uint256 weight = r.baseWeight >> shifts;
            uint256 adj = (weight * (2 * hl - modAge)) / (2 * hl);

            scores[uint256(r.domain)] += adj;
        }
    }

    function _halfLife(ChallengeRegistry.Domain d) internal pure returns (uint256) {
        if (d == ChallengeRegistry.Domain.ALGO)         return HL_ALGO;
        if (d == ChallengeRegistry.Domain.FORMAL_VER)   return HL_FORMAL_VER;
        if (d == ChallengeRegistry.Domain.APPLIED_MATH) return HL_APPLIED_MATH;
        return HL_SEC_CODE;
    }

    function recordsOf(address claimant) external view returns (Record[] memory) {
        return records[claimant];
    }
}
