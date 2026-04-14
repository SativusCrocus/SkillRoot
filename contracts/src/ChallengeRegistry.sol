// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StakingVault} from "./StakingVault.sol";

/// @title ChallengeRegistry — bonded proposals + permissionless rejection/activation (v0.2.0-no-vote)
/// @notice Flow:
///           1. propose: anyone locks PROPOSER_BOND (10k SKR); challenge PENDING.
///           2. REJECTION_WINDOW (48h): any address with ≥ REJECTOR_MIN_STAKE may
///              reject. Bond is split half to rejector, half burned.
///           3. After window: anyone calls activateChallenge → ACTIVE, bond returned.
///         One-shot bootstrap exception: genesisActivate() — callable only by the
///         deployer, exactly once (self-zeroes the deployer pointer on use). Required
///         because no stakers exist at t=0 to drive either rejection or the 48h clock.
///         No governance. No voting. No committee.
contract ChallengeRegistry {
    using SafeERC20 for IERC20;

    uint256 public constant PROPOSER_BOND = 10_000 ether;
    uint256 public constant REJECTION_WINDOW = 48 hours;
    uint256 public constant REJECTOR_MIN_STAKE = 1_000 ether; // must match StakingVault.MIN_STAKE
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    enum Domain {ALGO, FORMAL_VER, APPLIED_MATH, SEC_CODE}
    enum Status {PENDING, ACTIVE, REJECTED}

    struct Challenge {
        uint256 id;
        address proposer;
        Domain domain;
        address verifier;
        bytes32 specCID;
        bytes32 circuitHash;
        uint256 signalWeight;
        Status status;
        uint64 rejectionDeadline;
    }

    IERC20 public immutable token;
    StakingVault public immutable vault;

    /// @dev One-shot bootstrap key. Set to deployer in constructor; zeroed on
    ///      first successful genesisActivate() call. After that, the only paths
    ///      to ACTIVE are rejectChallenge / activateChallenge after 48h.
    address public genesisDeployer;

    mapping(uint256 => Challenge) private challenges;
    mapping(uint256 => uint256) public bondOf;
    uint256 public nextChallengeId = 1;

    event ChallengeProposed(
        uint256 indexed id,
        address indexed proposer,
        Domain domain,
        address verifier,
        bytes32 specCID,
        bytes32 circuitHash,
        uint256 signalWeight,
        uint64 rejectionDeadline
    );
    event ChallengeActivated(uint256 indexed id, address indexed activator, uint256 bondReturned);
    event ChallengeRejected(
        uint256 indexed id,
        address indexed rejector,
        uint256 rewardToRejector,
        uint256 burned
    );
    event GenesisKeyBurned();

    error ZeroAddress();
    error InvalidStatus();
    error UnknownChallenge();
    error RejectionWindowClosed();
    error RejectionWindowOpen();
    error RejectorUnderstaked();
    error NotGenesisDeployer();
    error GenesisAlreadyUsed();

    constructor(IERC20 _token, StakingVault _vault) {
        if (address(_token) == address(0) || address(_vault) == address(0)) revert ZeroAddress();
        token = _token;
        vault = _vault;
        genesisDeployer = msg.sender;
    }

    /// @notice Propose a new challenge. Locks PROPOSER_BOND. Challenge enters
    ///         PENDING and can be rejected during REJECTION_WINDOW; otherwise
    ///         anyone may activate it after the window elapses.
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
        uint64 deadline = uint64(block.timestamp + REJECTION_WINDOW);

        challenges[id] = Challenge({
            id: id,
            proposer: msg.sender,
            domain: domain,
            verifier: verifier,
            specCID: specCID,
            circuitHash: circuitHash,
            signalWeight: signalWeight,
            status: Status.PENDING,
            rejectionDeadline: deadline
        });
        bondOf[id] = PROPOSER_BOND;

        emit ChallengeProposed(
            id,
            msg.sender,
            domain,
            verifier,
            specCID,
            circuitHash,
            signalWeight,
            deadline
        );
    }

    /// @notice Reject a PENDING challenge during its 48h rejection window.
    ///         Caller must have ≥ REJECTOR_MIN_STAKE in the vault. Bond is
    ///         split half to caller, half burned.
    function rejectChallenge(uint256 id) external {
        Challenge storage c = challenges[id];
        if (c.id == 0) revert UnknownChallenge();
        if (c.status != Status.PENDING) revert InvalidStatus();
        if (block.timestamp > c.rejectionDeadline) revert RejectionWindowClosed();
        if (vault.stakeOf(msg.sender) < REJECTOR_MIN_STAKE) revert RejectorUnderstaked();

        c.status = Status.REJECTED;

        uint256 b = bondOf[id];
        bondOf[id] = 0;
        uint256 reward = b / 2;
        uint256 burned = b - reward;
        if (reward > 0) token.safeTransfer(msg.sender, reward);
        if (burned > 0) token.safeTransfer(BURN_ADDRESS, burned);

        emit ChallengeRejected(id, msg.sender, reward, burned);
    }

    /// @notice Activate a PENDING challenge after its rejection window expires.
    ///         Permissionless. Bond is returned to the proposer.
    function activateChallenge(uint256 id) external {
        Challenge storage c = challenges[id];
        if (c.id == 0) revert UnknownChallenge();
        if (c.status != Status.PENDING) revert InvalidStatus();
        if (block.timestamp <= c.rejectionDeadline) revert RejectionWindowOpen();

        c.status = Status.ACTIVE;

        uint256 b = bondOf[id];
        bondOf[id] = 0;
        if (b > 0) token.safeTransfer(c.proposer, b);

        emit ChallengeActivated(id, msg.sender, b);
    }

    /// @notice One-shot deployer-only activation for the genesis challenge.
    ///         Exists solely to bootstrap the system when no stakers yet exist
    ///         to enforce the 48h window. Self-zeroes `genesisDeployer` after
    ///         a single successful call; all subsequent attempts revert.
    function genesisActivate(uint256 id) external {
        address gd = genesisDeployer;
        if (gd == address(0)) revert GenesisAlreadyUsed();
        if (msg.sender != gd) revert NotGenesisDeployer();

        Challenge storage c = challenges[id];
        if (c.id == 0) revert UnknownChallenge();
        if (c.status != Status.PENDING) revert InvalidStatus();

        c.status = Status.ACTIVE;

        uint256 b = bondOf[id];
        bondOf[id] = 0;
        if (b > 0) token.safeTransfer(c.proposer, b);

        genesisDeployer = address(0);

        emit ChallengeActivated(id, gd, b);
        emit GenesisKeyBurned();
    }

    function getChallenge(uint256 id) external view returns (Challenge memory) {
        return challenges[id];
    }

    function isActive(uint256 id) external view returns (bool) {
        return challenges[id].status == Status.ACTIVE;
    }
}
