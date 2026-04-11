// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SKRToken} from "../src/SKRToken.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {ChallengeRegistry} from "../src/ChallengeRegistry.sol";
import {Sortition} from "../src/Sortition.sol";
import {AttestationStore} from "../src/AttestationStore.sol";
import {AttestationEngine} from "../src/AttestationEngine.sol";
import {ForgeGuard} from "../src/ForgeGuard.sol";
import {MockVerifier} from "../src/mocks/MockVerifier.sol";

/// @title ForgeGuard.t — full lifecycle tests for the ForgeGuard layer
/// @notice Deploys the SkillRoot stack + ForgeGuard, then exercises:
///         1. Permissionless forge submission → mirage spin-up
///         2. Staker breaks mirage → bounty payout + bond return
///         3. Mirage survives → bond burn + yield boost
///         4. Patch proposal after break
///         5. Edge cases (window expiry, non-staker, insufficient treasury)
contract ForgeGuardTest is Test {
    SKRToken internal token;
    StakingVault internal vault;
    ChallengeRegistry internal registry;
    Sortition internal sortition;
    AttestationStore internal store;
    AttestationEngine internal engine;
    ForgeGuard internal forgeGuard;
    MockVerifier internal mainVerifier;
    MockVerifier internal forgeVerifier;

    address internal gov = address(0xA11CE);
    address internal proposer = address(0xB0B);
    address internal forger = address(0xF04637); // forge submitter
    address internal breaker = address(0xB4EAC); // staker who breaks
    address internal funder = address(0xF00D);

    address[] internal validators;

    function setUp() public {
        vm.warp(1_700_000_000);
        vm.roll(1_000);

        vm.startPrank(gov);
        token = new SKRToken(gov);
        vault = new StakingVault(token, gov);
        registry = new ChallengeRegistry(token, gov);
        sortition = new Sortition(vault);
        store = new AttestationStore(gov);
        engine = new AttestationEngine(registry, vault, sortition, store, gov);
        forgeGuard = new ForgeGuard(token, registry, vault, gov);
        mainVerifier = new MockVerifier();
        forgeVerifier = new MockVerifier();

        // Wire permissions
        vault.setEngine(address(engine));
        vault.setForgeGuard(address(forgeGuard));
        store.setEngine(address(engine));
        vm.stopPrank();

        // Fund actors
        vm.startPrank(gov);
        token.transfer(proposer, 20_000 ether);
        token.transfer(forger, 10_000 ether);
        token.transfer(funder, 50_000 ether);

        // Fund breaker and make them a validator
        token.transfer(breaker, 10_000 ether);
        // Fund 5 more validators
        for (uint256 i = 0; i < 5; i++) {
            address v = address(uint160(0x1000 + i));
            validators.push(v);
            token.transfer(v, 5_000 ether);
        }
        vm.stopPrank();

        // Bond breaker as a validator
        vm.startPrank(breaker);
        token.approve(address(vault), 5_000 ether);
        vault.bond(5_000 ether);
        vm.stopPrank();

        // Bond other validators
        for (uint256 i = 0; i < 5; i++) {
            address v = validators[i];
            vm.startPrank(v);
            token.approve(address(vault), 5_000 ether);
            vault.bond(5_000 ether);
            vm.stopPrank();
        }

        // Propose + activate a challenge (target for forge)
        vm.startPrank(proposer);
        token.approve(address(registry), 10_000 ether);
        registry.propose(
            ChallengeRegistry.Domain.APPLIED_MATH,
            address(mainVerifier),
            bytes32("math-spec-v0"),
            bytes32("math-circuit-hash"),
            1_000 ether
        );
        vm.stopPrank();
        vm.prank(gov);
        registry.activate(1);

        // Fund the forge treasury
        vm.startPrank(funder);
        token.approve(address(forgeGuard), 50_000 ether);
        forgeGuard.fundTreasury(50_000 ether);
        vm.stopPrank();
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    function _dummyProof()
        internal
        pure
        returns (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c)
    {
        a = [uint256(1), uint256(2)];
        b = [[uint256(3), uint256(4)], [uint256(5), uint256(6)]];
        c = [uint256(7), uint256(8)];
    }

    function _forgeSignals() internal pure returns (uint256[] memory signals) {
        // [targetCircuitHash, exploitTag, exploitCommitment]
        signals = new uint256[](3);
        signals[0] = uint256(bytes32("math-circuit-hash")); // targetCircuitHash
        signals[1] = 1; // exploitTag: collision
        signals[2] = 0xDEADBEEF; // exploitCommitment (mock Poseidon output)
    }

    function _submitForge() internal returns (uint256 forgeId) {
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) = _dummyProof();
        uint256[] memory signals = _forgeSignals();

        vm.startPrank(forger);
        token.approve(address(forgeGuard), 1_000 ether);
        forgeId = forgeGuard.submitForge(1, address(forgeVerifier), a, b, c, signals);
        vm.stopPrank();
    }

    // ── Test: full break lifecycle ──────────────────────────────────────

    function test_forgeBreak_fullLifecycle() public {
        uint256 forgeId = _submitForge();
        assertEq(forgeId, 1, "first forge id");

        // Verify forge stored correctly
        ForgeGuard.Forge memory f = forgeGuard.getForge(forgeId);
        assertEq(f.submitter, forger);
        assertEq(f.targetChallengeId, 1);
        assertEq(f.exploitCommitment, 0xDEADBEEF);
        assertEq(f.exploitTag, 1);
        assertEq(uint256(f.status), uint256(ForgeGuard.ForgeStatus.MIRAGE_ACTIVE));
        assertEq(f.mirageDeadline, block.timestamp + 72 hours);

        // Verify binding hash was prepended (MockVerifier records it)
        uint256 expectedBinding = uint256(
            keccak256(abi.encode(forger, uint256(1)))
        ) & ((uint256(1) << 248) - 1);
        assertEq(forgeVerifier.lastBindingHash(), expectedBinding, "forge bindingHash");
        assertEq(forgeVerifier.lastPubSignalsLength(), 4, "4 bound signals");

        // Verify pure helper matches
        assertEq(forgeGuard.forgeBindingHashOf(forger, 1), expectedBinding);

        // --- Staker breaks the mirage ---
        uint256 breakerBalBefore = token.balanceOf(breaker);

        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) = _dummyProof();
        uint256[] memory signals = _forgeSignals();

        vm.prank(breaker);
        forgeGuard.breakMirage(forgeId, a, b, c, signals);

        // Verify break binding hash
        uint256 expectedBreakBinding = uint256(
            keccak256(abi.encode(breaker, forgeId))
        ) & ((uint256(1) << 248) - 1);
        assertEq(forgeGuard.breakBindingHashOf(breaker, forgeId), expectedBreakBinding);

        // Verify forge status
        f = forgeGuard.getForge(forgeId);
        assertEq(uint256(f.status), uint256(ForgeGuard.ForgeStatus.BROKEN));
        assertEq(f.breaker, breaker);

        // Bounty paid to breaker
        assertEq(
            token.balanceOf(breaker) - breakerBalBefore,
            5_000 ether,
            "bounty paid"
        );

        // Bond returned to submitter
        assertEq(token.balanceOf(forger), 10_000 ether, "bond returned");

        // Treasury decreased
        assertEq(forgeGuard.treasuryBalance(), 45_000 ether);
    }

    // ── Test: mirage survives → yield boost ─────────────────────────────

    function test_forgeSurvival_yieldsBoost() public {
        uint256 forgeId = _submitForge();

        // Warp past the break window
        vm.warp(block.timestamp + 73 hours);
        forgeGuard.finalizeForge(forgeId);

        ForgeGuard.Forge memory f = forgeGuard.getForge(forgeId);
        assertEq(uint256(f.status), uint256(ForgeGuard.ForgeStatus.SURVIVED));
        assertEq(forgeGuard.totalSurvivals(), 1);

        // Bond was burned
        assertEq(token.balanceOf(forger), 9_000 ether, "bond burned");

        // Yield boost applied to vault
        assertEq(vault.yieldBoostBps(), 10, "0.1% boost after 1 survival");

        // A second survival stacks
        uint256 forgeId2 = _submitForge();
        vm.warp(block.timestamp + 73 hours);
        forgeGuard.finalizeForge(forgeId2);
        assertEq(vault.yieldBoostBps(), 20, "0.2% boost after 2 survivals");
        assertEq(forgeGuard.totalSurvivals(), 2);
    }

    // ── Test: patch proposal after break ────────────────────────────────

    function test_patchProposal_afterBreak() public {
        uint256 forgeId = _submitForge();

        // Break it
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) = _dummyProof();
        uint256[] memory signals = _forgeSignals();
        vm.prank(breaker);
        forgeGuard.breakMirage(forgeId, a, b, c, signals);

        // Breaker submits patch
        bytes32 patchCID = bytes32("ipfs://patch-proposal-v1");
        vm.prank(breaker);
        forgeGuard.submitPatch(forgeId, patchCID);

        ForgeGuard.Forge memory f = forgeGuard.getForge(forgeId);
        assertEq(f.patchCID, patchCID);

        // Submitter can also update patch
        bytes32 patchCID2 = bytes32("ipfs://patch-proposal-v2");
        vm.prank(forger);
        forgeGuard.submitPatch(forgeId, patchCID2);
        f = forgeGuard.getForge(forgeId);
        assertEq(f.patchCID, patchCID2);
    }

    // ── Test: revert if break window closed ─────────────────────────────

    function test_breakMirage_revertsAfterDeadline() public {
        uint256 forgeId = _submitForge();

        vm.warp(block.timestamp + 73 hours);

        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) = _dummyProof();
        uint256[] memory signals = _forgeSignals();

        vm.expectRevert(ForgeGuard.BreakWindowClosed.selector);
        vm.prank(breaker);
        forgeGuard.breakMirage(forgeId, a, b, c, signals);
    }

    // ── Test: revert if finalize called too early ───────────────────────

    function test_finalizeForge_revertsBeforeDeadline() public {
        uint256 forgeId = _submitForge();

        vm.expectRevert(ForgeGuard.BreakWindowOpen.selector);
        forgeGuard.finalizeForge(forgeId);
    }

    // ── Test: non-staker cannot break ───────────────────────────────────

    function test_breakMirage_revertsForNonStaker() public {
        uint256 forgeId = _submitForge();

        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) = _dummyProof();
        uint256[] memory signals = _forgeSignals();

        address nonStaker = address(0xBAD);
        vm.expectRevert(ForgeGuard.NotStaker.selector);
        vm.prank(nonStaker);
        forgeGuard.breakMirage(forgeId, a, b, c, signals);
    }

    // ── Test: commitment mismatch reverts break ─────────────────────────

    function test_breakMirage_revertsOnCommitmentMismatch() public {
        uint256 forgeId = _submitForge();

        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) = _dummyProof();
        uint256[] memory signals = new uint256[](3);
        signals[0] = uint256(bytes32("math-circuit-hash"));
        signals[1] = 1;
        signals[2] = 0xBADC0FFE; // wrong commitment

        vm.expectRevert(ForgeGuard.CommitmentMismatch.selector);
        vm.prank(breaker);
        forgeGuard.breakMirage(forgeId, a, b, c, signals);
    }

    // ── Test: inactive challenge cannot be targeted ─────────────────────

    function test_submitForge_revertsOnInactiveChallenge() public {
        vm.prank(gov);
        registry.deprecate(1);

        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) = _dummyProof();
        uint256[] memory signals = _forgeSignals();

        vm.startPrank(forger);
        token.approve(address(forgeGuard), 1_000 ether);
        vm.expectRevert(ForgeGuard.ChallengeNotActive.selector);
        forgeGuard.submitForge(1, address(forgeVerifier), a, b, c, signals);
        vm.stopPrank();
    }

    // ── Test: invalid proof reverts ─────────────────────────────────────

    function test_submitForge_revertsOnInvalidProof() public {
        forgeVerifier.setAccept(false);

        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) = _dummyProof();
        uint256[] memory signals = _forgeSignals();

        vm.startPrank(forger);
        token.approve(address(forgeGuard), 1_000 ether);
        vm.expectRevert(ForgeGuard.InvalidProof.selector);
        forgeGuard.submitForge(1, address(forgeVerifier), a, b, c, signals);
        vm.stopPrank();
    }

    // ── Test: insufficient treasury reverts break ───────────────────────

    function test_breakMirage_revertsOnEmptyTreasury() public {
        // Deploy a second ForgeGuard with no treasury
        vm.startPrank(gov);
        ForgeGuard fg2 = new ForgeGuard(token, registry, vault, gov);
        // We can't set a second forgeGuard on the same vault, so test the
        // revert path directly by using a forge on the main forgeGuard after
        // draining the treasury. We drain by breaking 10 forges.
        vm.stopPrank();

        // Submit + break enough forges to drain treasury (50k / 5k = 10)
        for (uint256 i = 0; i < 10; i++) {
            uint256 fid = _submitForge();
            (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) = _dummyProof();
            uint256[] memory signals = _forgeSignals();
            vm.prank(breaker);
            forgeGuard.breakMirage(fid, a, b, c, signals);
        }
        assertEq(forgeGuard.treasuryBalance(), 0);

        // Now another submit + attempted break should fail
        uint256 forgeId = _submitForge();
        (uint256[2] memory a2, uint256[2][2] memory b2, uint256[2] memory c2) = _dummyProof();
        uint256[] memory signals2 = _forgeSignals();

        vm.expectRevert(ForgeGuard.InsufficientTreasury.selector);
        vm.prank(breaker);
        forgeGuard.breakMirage(forgeId, a2, b2, c2, signals2);
    }

    // ── Test: double break reverts ──────────────────────────────────────

    function test_breakMirage_revertsOnAlreadyBroken() public {
        uint256 forgeId = _submitForge();

        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) = _dummyProof();
        uint256[] memory signals = _forgeSignals();

        vm.prank(breaker);
        forgeGuard.breakMirage(forgeId, a, b, c, signals);

        // Second break attempt
        vm.expectRevert(ForgeGuard.ForgeNotActive.selector);
        vm.prank(breaker);
        forgeGuard.breakMirage(forgeId, a, b, c, signals);
    }

    // ── Test: treasury funding ──────────────────────────────────────────

    function test_fundTreasury() public {
        uint256 before = forgeGuard.treasuryBalance();

        vm.startPrank(funder);
        // funder may not have balance left, use gov
        vm.stopPrank();

        vm.startPrank(gov);
        token.approve(address(forgeGuard), 10_000 ether);
        forgeGuard.fundTreasury(10_000 ether);
        vm.stopPrank();

        assertEq(forgeGuard.treasuryBalance(), before + 10_000 ether);
    }

    // ── Test: existing E2E still works (regression) ─────────────────────

    function test_existingStakingVault_unchangedForValidators() public {
        // Verify validators are bonded and can still operate
        assertEq(vault.stakeOf(breaker), 5_000 ether);
        assertEq(vault.validatorCount(), 6); // breaker + 5 validators
        assertEq(vault.yieldBoostBps(), 0, "no boost initially");
    }
}
