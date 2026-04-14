// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IZKVerifier} from "./interfaces/IZKVerifier.sol";
import {StakingVault} from "./StakingVault.sol";
import {ChallengeRegistry} from "./ChallengeRegistry.sol";
import {AttestationStore} from "./AttestationStore.sol";

/// @title AttestationEngine — fraud-proof + auto-finalize orchestrator (v0.2.0-no-vote)
/// @notice Flow:
///           1. submitClaim: claimant posts CLAIM_BOND + valid ZK proof; claim PENDING.
///           2. CHALLENGE_WINDOW (24h): any address with ≥ MIN_STAKE in the vault may
///              submit a fraud proof. If valid, claim is rejected, bond is split
///              (half to prover, half burned).
///           3. After the window, anyone calls finalizeClaim → accepted, bond returned,
///              attestation recorded.
///         No committees. No voting. No governance. No sortition.
///         D2 binding revision preserved: contract computes
///         bindingHash = keccak(msg.sender, challengeId) & 2^248-1 and prepends it
///         as public signal 0 for BOTH the claim proof and the fraud proof. The
///         fraud proof is bound to the claim's claimant+challengeId, not msg.sender.
contract AttestationEngine is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant CHALLENGE_WINDOW = 24 hours;
    uint256 public constant CLAIM_BOND = 100 ether;           // 100 SKR per claim
    uint256 public constant FRAUD_PROVER_MIN_STAKE = 1_000 ether; // must match StakingVault.MIN_STAKE
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    enum ClaimStatus {PENDING, FINALIZED_ACCEPT, FINALIZED_REJECT}

    struct Claim {
        uint256 id;
        uint256 challengeId;
        address claimant;
        uint64 submittedAt;
        uint64 challengeDeadline;
        uint256 bond;
        bytes32 artifactCID;
        ClaimStatus status;
    }

    ChallengeRegistry public immutable registry;
    StakingVault public immutable vault;
    AttestationStore public immutable store;
    IERC20 public immutable token;
    IZKVerifier public immutable fraudVerifier;

    mapping(uint256 => Claim) private claims;
    uint256 public nextClaimId = 1;

    event ClaimSubmitted(
        uint256 indexed claimId,
        uint256 indexed challengeId,
        address indexed claimant,
        uint64 submittedAt,
        uint64 challengeDeadline,
        uint256 bond,
        bytes32 artifactCID
    );
    event FraudProven(
        uint256 indexed claimId,
        address indexed prover,
        uint256 rewardToProver,
        uint256 burned
    );
    event ClaimFinalized(uint256 indexed claimId, bool accepted, uint256 bondReturned);

    error ChallengeNotActive();
    error InvalidProof();
    error InvalidFraudProof();
    error UnknownClaim();
    error NotPending();
    error ChallengeWindowClosed();
    error ChallengeWindowOpen();
    error ProverUnderstaked();
    error ZeroAddress();

    constructor(
        ChallengeRegistry _registry,
        StakingVault _vault,
        AttestationStore _store,
        IERC20 _token,
        IZKVerifier _fraudVerifier
    ) {
        if (
            address(_registry) == address(0) ||
            address(_vault) == address(0) ||
            address(_store) == address(0) ||
            address(_token) == address(0) ||
            address(_fraudVerifier) == address(0)
        ) revert ZeroAddress();
        registry = _registry;
        vault = _vault;
        store = _store;
        token = _token;
        fraudVerifier = _fraudVerifier;
    }

    /// @notice Pure helper for off-chain tooling to derive the bindingHash the
    ///         contract will compute for a (claimant, challengeId) pair.
    function bindingHashOf(address claimant, uint256 challengeId)
        external
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(claimant, challengeId))) & ((uint256(1) << 248) - 1);
    }

    /// @notice Submit a claim against an ACTIVE challenge. Requires CLAIM_BOND
    ///         in SKR and a valid Groth16 proof for the challenge's verifier.
    ///         Contract prepends bindingHash as public signal 0.
    function submitClaim(
        uint256 challengeId,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata circuitSignals,
        bytes32 artifactCID
    ) external nonReentrant returns (uint256 claimId) {
        ChallengeRegistry.Challenge memory ch = registry.getChallenge(challengeId);
        if (ch.status != ChallengeRegistry.Status.ACTIVE) revert ChallengeNotActive();

        uint256 bindingHash = _bindingHash(msg.sender, challengeId);
        uint256[] memory boundSignals = _prepend(bindingHash, circuitSignals);

        if (!IZKVerifier(ch.verifier).verifyProof(a, b, c, boundSignals)) revert InvalidProof();

        token.safeTransferFrom(msg.sender, address(this), CLAIM_BOND);

        claimId = nextClaimId++;
        uint64 nowTs = uint64(block.timestamp);
        uint64 deadline = nowTs + uint64(CHALLENGE_WINDOW);

        claims[claimId] = Claim({
            id: claimId,
            challengeId: challengeId,
            claimant: msg.sender,
            submittedAt: nowTs,
            challengeDeadline: deadline,
            bond: CLAIM_BOND,
            artifactCID: artifactCID,
            status: ClaimStatus.PENDING
        });

        emit ClaimSubmitted(claimId, challengeId, msg.sender, nowTs, deadline, CLAIM_BOND, artifactCID);
    }

    /// @notice Submit a fraud proof against a PENDING claim before its challenge
    ///         window closes. Prover must have ≥ FRAUD_PROVER_MIN_STAKE in the
    ///         vault at time of call. On success claimant's bond is split:
    ///         half to prover, half burned to 0xdead.
    function submitFraudProof(
        uint256 claimId,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata fraudSignals
    ) external nonReentrant {
        Claim storage cl = claims[claimId];
        if (cl.id == 0) revert UnknownClaim();
        if (cl.status != ClaimStatus.PENDING) revert NotPending();
        if (block.timestamp > cl.challengeDeadline) revert ChallengeWindowClosed();
        if (vault.stakeOf(msg.sender) < FRAUD_PROVER_MIN_STAKE) revert ProverUnderstaked();

        uint256 bindingHash = _bindingHash(cl.claimant, cl.challengeId);
        uint256[] memory boundSignals = _prepend(bindingHash, fraudSignals);

        if (!fraudVerifier.verifyProof(a, b, c, boundSignals)) revert InvalidFraudProof();

        cl.status = ClaimStatus.FINALIZED_REJECT;

        uint256 bond = cl.bond;
        cl.bond = 0;
        uint256 reward = bond / 2;
        uint256 burned = bond - reward;

        if (reward > 0) token.safeTransfer(msg.sender, reward);
        if (burned > 0) token.safeTransfer(BURN_ADDRESS, burned);

        emit FraudProven(claimId, msg.sender, reward, burned);
        emit ClaimFinalized(claimId, false, 0);
    }

    /// @notice After the 24h challenge window closes with no successful fraud
    ///         proof, anyone may finalize the claim. Bond is returned, the
    ///         attestation is recorded in the store.
    function finalizeClaim(uint256 claimId) external nonReentrant {
        Claim storage cl = claims[claimId];
        if (cl.id == 0) revert UnknownClaim();
        if (cl.status != ClaimStatus.PENDING) revert NotPending();
        if (block.timestamp <= cl.challengeDeadline) revert ChallengeWindowOpen();

        cl.status = ClaimStatus.FINALIZED_ACCEPT;

        uint256 bond = cl.bond;
        cl.bond = 0;
        if (bond > 0) token.safeTransfer(cl.claimant, bond);

        ChallengeRegistry.Challenge memory ch = registry.getChallenge(cl.challengeId);
        store.record(cl.claimant, cl.challengeId, ch.domain, ch.signalWeight, cl.artifactCID);

        emit ClaimFinalized(claimId, true, bond);
    }

    function getClaim(uint256 claimId) external view returns (Claim memory) {
        return claims[claimId];
    }

    function _bindingHash(address claimant, uint256 challengeId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(claimant, challengeId))) & ((uint256(1) << 248) - 1);
    }

    function _prepend(uint256 head, uint256[] calldata tail)
        internal
        pure
        returns (uint256[] memory out)
    {
        uint256 n = tail.length;
        out = new uint256[](n + 1);
        out[0] = head;
        for (uint256 i = 0; i < n; i++) {
            out[i + 1] = tail[i];
        }
    }
}
