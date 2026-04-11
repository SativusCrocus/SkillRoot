// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IZKVerifier} from "./interfaces/IZKVerifier.sol";
import {ChallengeRegistry} from "./ChallengeRegistry.sol";
import {StakingVault} from "./StakingVault.sol";

/// @title ForgeGuard — permissionless security testing via forge challenges
/// @notice Anyone submits a candidate exploit vector as a ZK-committed forge
///         challenge. The protocol spins up a mirage instance (sandboxed shadow
///         of the target circuit). Stakers compete to break the mirage in a
///         timed window. Success = bounty + ZK proof of vector + patch proposal.
///         Failure = security attestation that boosts staking yield.
contract ForgeGuard is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BREAK_WINDOW = 72 hours;
    uint256 public constant FORGE_BOND = 1_000 ether;
    uint256 public constant BOUNTY_AMOUNT = 5_000 ether;
    uint256 public constant SURVIVAL_BOOST_BPS = 10; // 0.10% per survived forge
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    enum ForgeStatus {MIRAGE_ACTIVE, BROKEN, SURVIVED}

    struct Forge {
        uint256 id;
        address submitter;
        uint256 targetChallengeId;
        bytes32 targetCircuitHash;   // from ChallengeRegistry
        uint256 exploitCommitment;   // Poseidon hash of private exploit vector
        uint256 exploitTag;          // exploit category
        address forgeVerifier;       // IZKVerifier for forge proofs
        uint64 mirageDeadline;       // end of break window
        ForgeStatus status;
        address breaker;             // who broke it (address(0) if survived)
        bytes32 patchCID;            // IPFS CID of patch proposal
    }

    IERC20 public immutable token;
    ChallengeRegistry public immutable registry;
    StakingVault public immutable vault;
    address public governance;

    mapping(uint256 => Forge) private forges;
    uint256 public nextForgeId = 1;
    uint256 public treasuryBalance;
    uint256 public totalSurvivals;

    // ── Events ──────────────────────────────────────────────────────────
    event TreasuryFunded(address indexed funder, uint256 amount);
    event ForgeSubmitted(
        uint256 indexed forgeId,
        address indexed submitter,
        uint256 indexed targetChallengeId,
        uint256 exploitCommitment,
        uint64 mirageDeadline
    );
    event MirageBroken(uint256 indexed forgeId, address indexed breaker, uint256 bounty);
    event ForgeSurvived(uint256 indexed forgeId, uint256 totalSurvivals);
    event PatchProposed(uint256 indexed forgeId, bytes32 patchCID);
    event GovernanceTransferred(address indexed from, address indexed to);

    // ── Errors ──────────────────────────────────────────────────────────
    error NotGovernance();
    error ChallengeNotActive();
    error InvalidProof();
    error ForgeNotActive();
    error BreakWindowOpen();
    error BreakWindowClosed();
    error NotStaker();
    error InsufficientTreasury();
    error CommitmentMismatch();
    error ZeroAddress();
    error ZeroAmount();
    error UnknownForge();
    error NotSubmitterOrBreaker();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    constructor(
        IERC20 _token,
        ChallengeRegistry _registry,
        StakingVault _vault,
        address _governance
    ) {
        if (address(_token) == address(0) || _governance == address(0)) revert ZeroAddress();
        token = _token;
        registry = _registry;
        vault = _vault;
        governance = _governance;
    }

    function transferGovernance(address newGov) external onlyGovernance {
        if (newGov == address(0)) revert ZeroAddress();
        address old = governance;
        governance = newGov;
        emit GovernanceTransferred(old, newGov);
    }

    // ── Treasury ────────────────────────────────────────────────────────

    /// @notice Anyone can fund the forge treasury for bounty payouts.
    function fundTreasury(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        token.safeTransferFrom(msg.sender, address(this), amount);
        treasuryBalance += amount;
        emit TreasuryFunded(msg.sender, amount);
    }

    // ── Binding hash helpers ────────────────────────────────────────────

    function forgeBindingHashOf(address submitter, uint256 targetChallengeId)
        external
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(submitter, targetChallengeId)))
            & ((uint256(1) << 248) - 1);
    }

    function breakBindingHashOf(address breaker, uint256 forgeId)
        external
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(breaker, forgeId)))
            & ((uint256(1) << 248) - 1);
    }

    // ── Submit forge challenge ──────────────────────────────────────────

    /// @notice Permissionless: submit a candidate exploit as a ZK forge proof.
    ///         Instantly deploys a mirage instance (starts the break window).
    /// @param targetChallengeId The active SkillRoot challenge being targeted.
    /// @param forgeVerifier     IZKVerifier address for the forge circuit.
    /// @param a                 Groth16 proof element.
    /// @param b                 Groth16 proof element.
    /// @param c                 Groth16 proof element.
    /// @param circuitSignals    [targetCircuitHash, exploitTag, exploitCommitment]
    ///                          (bindingHash is prepended by this contract).
    function submitForge(
        uint256 targetChallengeId,
        address forgeVerifier,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata circuitSignals
    ) external nonReentrant returns (uint256 forgeId) {
        ChallengeRegistry.Challenge memory ch = registry.getChallenge(targetChallengeId);
        if (ch.status != ChallengeRegistry.Status.ACTIVE) revert ChallengeNotActive();
        if (forgeVerifier == address(0)) revert ZeroAddress();

        // Take bond
        token.safeTransferFrom(msg.sender, address(this), FORGE_BOND);

        // D2 binding: prepend contract-computed bindingHash as signal 0
        uint256 bindingHash = uint256(keccak256(abi.encode(msg.sender, targetChallengeId)))
            & ((uint256(1) << 248) - 1);
        uint256 n = circuitSignals.length;
        uint256[] memory boundSignals = new uint256[](n + 1);
        boundSignals[0] = bindingHash;
        for (uint256 i = 0; i < n; i++) {
            boundSignals[i + 1] = circuitSignals[i];
        }

        // Verify forge proof
        if (!IZKVerifier(forgeVerifier).verifyProof(a, b, c, boundSignals)) {
            revert InvalidProof();
        }

        // Create forge with mirage instantly active
        forgeId = nextForgeId++;
        uint64 deadline = uint64(block.timestamp + BREAK_WINDOW);

        forges[forgeId] = Forge({
            id: forgeId,
            submitter: msg.sender,
            targetChallengeId: targetChallengeId,
            targetCircuitHash: ch.circuitHash,
            exploitCommitment: circuitSignals[2],
            exploitTag: circuitSignals[1],
            forgeVerifier: forgeVerifier,
            mirageDeadline: deadline,
            status: ForgeStatus.MIRAGE_ACTIVE,
            breaker: address(0),
            patchCID: bytes32(0)
        });

        emit ForgeSubmitted(forgeId, msg.sender, targetChallengeId, circuitSignals[2], deadline);
    }

    // ── Break mirage ────────────────────────────────────────────────────

    /// @notice Staker proves they know the exploit vector, breaking the mirage.
    ///         Pays bounty from treasury, returns bond to submitter.
    /// @param forgeId        The forge challenge to break.
    /// @param a              Groth16 proof element.
    /// @param b              Groth16 proof element.
    /// @param c              Groth16 proof element.
    /// @param circuitSignals [targetCircuitHash, exploitTag, exploitCommitment]
    function breakMirage(
        uint256 forgeId,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata circuitSignals
    ) external nonReentrant {
        Forge storage f = forges[forgeId];
        if (f.id == 0) revert UnknownForge();
        if (f.status != ForgeStatus.MIRAGE_ACTIVE) revert ForgeNotActive();
        if (block.timestamp > f.mirageDeadline) revert BreakWindowClosed();
        if (vault.stakeOf(msg.sender) == 0) revert NotStaker();
        if (treasuryBalance < BOUNTY_AMOUNT) revert InsufficientTreasury();

        // Exploit commitment must match the original forge
        if (circuitSignals.length < 3 || circuitSignals[2] != f.exploitCommitment) {
            revert CommitmentMismatch();
        }

        // D2 binding for the breaker
        uint256 bindingHash = uint256(keccak256(abi.encode(msg.sender, forgeId)))
            & ((uint256(1) << 248) - 1);
        uint256 n = circuitSignals.length;
        uint256[] memory boundSignals = new uint256[](n + 1);
        boundSignals[0] = bindingHash;
        for (uint256 i = 0; i < n; i++) {
            boundSignals[i + 1] = circuitSignals[i];
        }

        if (!IZKVerifier(f.forgeVerifier).verifyProof(a, b, c, boundSignals)) {
            revert InvalidProof();
        }

        // Mark broken
        f.status = ForgeStatus.BROKEN;
        f.breaker = msg.sender;

        // Pay bounty to breaker
        treasuryBalance -= BOUNTY_AMOUNT;
        token.safeTransfer(msg.sender, BOUNTY_AMOUNT);

        // Return bond to submitter (they reported a real exploit)
        token.safeTransfer(f.submitter, FORGE_BOND);

        emit MirageBroken(forgeId, msg.sender, BOUNTY_AMOUNT);
    }

    // ── Finalize survived forge ─────────────────────────────────────────

    /// @notice After the break window closes without a break, the mirage
    ///         survived. Burns the submitter's bond, mints a security
    ///         attestation (yield boost), and increments totalSurvivals.
    function finalizeForge(uint256 forgeId) external {
        Forge storage f = forges[forgeId];
        if (f.id == 0) revert UnknownForge();
        if (f.status != ForgeStatus.MIRAGE_ACTIVE) revert ForgeNotActive();
        if (block.timestamp <= f.mirageDeadline) revert BreakWindowOpen();

        f.status = ForgeStatus.SURVIVED;
        totalSurvivals++;

        // Burn the submitter's bond (unverifiable exploit claim)
        token.safeTransfer(BURN_ADDRESS, FORGE_BOND);

        // Boost staking yield (permanent security attestation)
        vault.addYieldBoost(SURVIVAL_BOOST_BPS);

        emit ForgeSurvived(forgeId, totalSurvivals);
    }

    // ── Patch proposal ──────────────────────────────────────────────────

    /// @notice After a break, submitter or breaker attaches a patch proposal CID.
    function submitPatch(uint256 forgeId, bytes32 patchCID) external {
        Forge storage f = forges[forgeId];
        if (f.id == 0) revert UnknownForge();
        if (f.status != ForgeStatus.BROKEN) revert ForgeNotActive();
        if (msg.sender != f.breaker && msg.sender != f.submitter) {
            revert NotSubmitterOrBreaker();
        }

        f.patchCID = patchCID;
        emit PatchProposed(forgeId, patchCID);
    }

    // ── Views ───────────────────────────────────────────────────────────

    function getForge(uint256 forgeId) external view returns (Forge memory) {
        return forges[forgeId];
    }
}
