// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ChallengeRegistry — full lifecycle challenge management
/// @notice Multi-challenge API live at genesis. v0 seeds and activates only
///         one challenge (the math modexp); the rest of the API is exercised
///         through tests and available for future challenge proposals.
contract ChallengeRegistry {
    using SafeERC20 for IERC20;

    uint256 public constant PROPOSER_BOND = 10_000 ether;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    enum Domain {ALGO, FORMAL_VER, APPLIED_MATH, SEC_CODE}
    enum Status {PENDING, ACTIVE, DEPRECATED, REJECTED}

    struct Challenge {
        uint256 id;
        address proposer;
        Domain domain;
        address verifier;
        bytes32 specCID;
        bytes32 circuitHash;
        uint256 signalWeight;
        Status status;
    }

    IERC20 public immutable token;
    address public governance;

    mapping(uint256 => Challenge) private challenges;
    mapping(uint256 => uint256) public bondOf; // claimId → bond held
    uint256 public nextChallengeId = 1;

    event ChallengeProposed(
        uint256 indexed id,
        address indexed proposer,
        Domain domain,
        address verifier,
        bytes32 specCID,
        bytes32 circuitHash,
        uint256 signalWeight
    );
    event ChallengeActivated(uint256 indexed id);
    event ChallengeRejected(uint256 indexed id);
    event ChallengeDeprecated(uint256 indexed id);
    event GovernanceTransferred(address indexed from, address indexed to);

    error NotGovernance();
    error ZeroAddress();
    error InvalidStatus();
    error UnknownChallenge();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    constructor(IERC20 _token, address _governance) {
        if (address(_token) == address(0) || _governance == address(0)) revert ZeroAddress();
        token = _token;
        governance = _governance;
    }

    function transferGovernance(address newGov) external onlyGovernance {
        if (newGov == address(0)) revert ZeroAddress();
        address old = governance;
        governance = newGov;
        emit GovernanceTransferred(old, newGov);
    }

    function propose(
        Domain domain,
        address verifier,
        bytes32 specCID,
        bytes32 circuitHash,
        uint256 signalWeight
    ) external returns (uint256 id) {
        if (verifier == address(0)) revert ZeroAddress();

        token.safeTransferFrom(msg.sender, address(this), PROPOSER_BOND);

        id = nextChallengeId++;
        challenges[id] = Challenge({
            id: id,
            proposer: msg.sender,
            domain: domain,
            verifier: verifier,
            specCID: specCID,
            circuitHash: circuitHash,
            signalWeight: signalWeight,
            status: Status.PENDING
        });
        bondOf[id] = PROPOSER_BOND;

        emit ChallengeProposed(id, msg.sender, domain, verifier, specCID, circuitHash, signalWeight);
    }

    function activate(uint256 id) external onlyGovernance {
        Challenge storage c = challenges[id];
        if (c.id == 0) revert UnknownChallenge();
        if (c.status != Status.PENDING) revert InvalidStatus();
        c.status = Status.ACTIVE;

        uint256 b = bondOf[id];
        bondOf[id] = 0;
        if (b > 0) token.safeTransfer(c.proposer, b);

        emit ChallengeActivated(id);
    }

    function reject(uint256 id) external onlyGovernance {
        Challenge storage c = challenges[id];
        if (c.id == 0) revert UnknownChallenge();
        if (c.status != Status.PENDING) revert InvalidStatus();
        c.status = Status.REJECTED;

        uint256 b = bondOf[id];
        bondOf[id] = 0;
        if (b > 0) token.safeTransfer(BURN_ADDRESS, b);

        emit ChallengeRejected(id);
    }

    function deprecate(uint256 id) external onlyGovernance {
        Challenge storage c = challenges[id];
        if (c.id == 0) revert UnknownChallenge();
        if (c.status != Status.ACTIVE) revert InvalidStatus();
        c.status = Status.DEPRECATED;
        emit ChallengeDeprecated(id);
    }

    function getChallenge(uint256 id) external view returns (Challenge memory) {
        return challenges[id];
    }

    function isActive(uint256 id) external view returns (bool) {
        return challenges[id].status == Status.ACTIVE;
    }
}
