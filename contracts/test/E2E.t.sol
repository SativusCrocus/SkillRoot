// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SKRToken} from "../src/SKRToken.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {ChallengeRegistry} from "../src/ChallengeRegistry.sol";
import {Sortition} from "../src/Sortition.sol";
import {AttestationStore} from "../src/AttestationStore.sol";
import {AttestationEngine} from "../src/AttestationEngine.sol";
import {QueryGateway} from "../src/QueryGateway.sol";
import {Governance} from "../src/Governance.sol";
import {MockVerifier} from "../src/mocks/MockVerifier.sol";
import {IZKVerifier} from "../src/interfaces/IZKVerifier.sol";

/// @title E2E — Gate 1: full lifecycle with MockVerifier
/// @notice Deploys the whole stack, seeds a math challenge, bonds 10
///         validators, submits a claim, draws committee, votes YES
///         unanimously, finalizes, and asserts the decayed score from
///         QueryGateway.
contract E2ETest is Test {
    SKRToken internal token;
    StakingVault internal vault;
    ChallengeRegistry internal registry;
    Sortition internal sortition;
    AttestationStore internal store;
    AttestationEngine internal engine;
    QueryGateway internal gateway;
    MockVerifier internal verifier;

    address internal gov = address(0xA11CE);
    address internal claimant = address(0xC1A11A17);
    address internal proposer = address(0xB0B);

    address[] internal validators;

    function setUp() public {
        // Warp to a non-zero block timestamp so ERC20Votes clock is sane
        vm.warp(1_700_000_000);
        vm.roll(1_000);

        vm.startPrank(gov);
        token = new SKRToken(gov);
        vault = new StakingVault(token, gov);
        registry = new ChallengeRegistry(token, gov);
        sortition = new Sortition(vault);
        store = new AttestationStore(gov);
        engine = new AttestationEngine(registry, vault, sortition, store, gov);
        gateway = new QueryGateway(store);
        verifier = new MockVerifier();

        // Wire gated writers
        vault.setEngine(address(engine));
        store.setEngine(address(engine));
        vm.stopPrank();

        // Fund proposer and 10 validators from gov treasury
        vm.startPrank(gov);
        token.transfer(proposer, 20_000 ether);
        for (uint256 i = 0; i < 10; i++) {
            address v = address(uint160(0x1000 + i));
            validators.push(v);
            token.transfer(v, 5_000 ether);
        }
        token.transfer(claimant, 1 ether);
        vm.stopPrank();

        // Bond validators
        for (uint256 i = 0; i < 10; i++) {
            address v = validators[i];
            vm.startPrank(v);
            token.approve(address(vault), 5_000 ether);
            vault.bond(5_000 ether);
            vm.stopPrank();
        }

        // Proposer bonds and proposes a math challenge
        vm.startPrank(proposer);
        token.approve(address(registry), 10_000 ether);
        uint256 cid = registry.propose(
            ChallengeRegistry.Domain.APPLIED_MATH,
            address(verifier),
            bytes32("math-spec-v0"),
            bytes32("math-circuit-hash"),
            1_000 ether // signalWeight
        );
        vm.stopPrank();

        // Governance activates it
        vm.prank(gov);
        registry.activate(cid);
        assertEq(cid, 1, "first challenge id = 1");
    }

    function test_fullLifecycle_acceptsAndScoresMathDomain() public {
        uint256 challengeId = 1;

        // --- submit claim ---
        uint256[2] memory a = [uint256(1), uint256(2)];
        uint256[2][2] memory b = [[uint256(3), uint256(4)], [uint256(5), uint256(6)]];
        uint256[2] memory c = [uint256(7), uint256(8)];

        // Circuit-level public signals (without the contract-prepended bindingHash):
        // base=2, modulus=97, result=55 (which is 2^20 mod 97)
        uint256[] memory circuitSignals = new uint256[](3);
        circuitSignals[0] = 2;
        circuitSignals[1] = 97;
        circuitSignals[2] = 55;

        bytes32 artifact = bytes32("ipfs://artifact");

        uint256 expectedBinding = uint256(
            keccak256(abi.encode(claimant, challengeId))
        ) & ((uint256(1) << 248) - 1);

        vm.prank(claimant);
        uint256 claimId = engine.submitClaim(
            challengeId, a, b, c, circuitSignals, artifact
        );
        assertEq(claimId, 1);

        // MockVerifier recorded the 4 bound signals
        assertEq(verifier.lastBindingHash(), expectedBinding, "bindingHash prepended");
        assertEq(verifier.lastPubSignalsLength(), 4, "4 signals total");
        assertEq(verifier.lastPubSignals(1), 2, "base");
        assertEq(verifier.lastPubSignals(2), 97, "modulus");
        assertEq(verifier.lastPubSignals(3), 55, "result");

        // Verify the pure helper matches
        assertEq(
            engine.bindingHashOf(claimant, challengeId),
            expectedBinding
        );

        // --- draw committee (after REVEAL_DELAY + 1 blocks) ---
        vm.roll(block.number + 5);
        engine.drawCommittee(claimId);

        address[] memory committee = engine.committeeOf(claimId);
        assertEq(committee.length, 7, "COMMITTEE_SIZE = 7");

        // --- unanimous YES vote ---
        for (uint256 i = 0; i < committee.length; i++) {
            vm.prank(committee[i]);
            engine.vote(claimId, true);
        }

        // --- finalize after vote window ---
        vm.warp(block.timestamp + 25 hours);
        engine.finalize(claimId);

        AttestationEngine.Claim memory cl = engine.getClaim(claimId);
        assertEq(uint256(cl.status), uint256(AttestationEngine.ClaimStatus.FINALIZED_ACCEPT));

        // --- QueryGateway reports decayed score in APPLIED_MATH slot ---
        uint256[4] memory scores = gateway.verify(claimant);
        // index 2 = APPLIED_MATH
        assertGt(scores[2], 0, "math score > 0 after attestation");
        // Other domains should be zero
        assertEq(scores[0], 0);
        assertEq(scores[1], 0);
        assertEq(scores[3], 0);

        // No slashes happened — everyone voted yes and final was accept
        for (uint256 i = 0; i < committee.length; i++) {
            assertEq(vault.stakeOf(committee[i]), 5_000 ether, "no slash");
        }
    }

    function test_fullLifecycle_rejectsOnMajorityNo_slashesYesVoters() public {
        uint256 challengeId = 1;
        verifier.setAccept(true);

        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        uint256[] memory signals = new uint256[](3);
        signals[0] = 2;
        signals[1] = 97;
        signals[2] = 55;

        vm.prank(claimant);
        uint256 claimId = engine.submitClaim(
            challengeId, a, b, c, signals, bytes32(0)
        );

        vm.roll(block.number + 5);
        engine.drawCommittee(claimId);
        address[] memory committee = engine.committeeOf(claimId);

        // 2 vote YES, 5 vote NO → rejected. The 2 YES voters are equivocators.
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(committee[i]);
            engine.vote(claimId, true);
        }
        for (uint256 i = 2; i < 7; i++) {
            vm.prank(committee[i]);
            engine.vote(claimId, false);
        }

        vm.warp(block.timestamp + 25 hours);
        engine.finalize(claimId);

        AttestationEngine.Claim memory cl = engine.getClaim(claimId);
        assertEq(uint256(cl.status), uint256(AttestationEngine.ClaimStatus.FINALIZED_REJECT));

        // YES voters got equivocation slash (5% of 5000 = 250)
        for (uint256 i = 0; i < 2; i++) {
            assertEq(vault.stakeOf(committee[i]), 5_000 ether - 250 ether, "equivocation slash on YES voter");
        }
        // NO voters unslashed
        for (uint256 i = 2; i < 7; i++) {
            assertEq(vault.stakeOf(committee[i]), 5_000 ether, "no slash");
        }

        // No attestation written
        uint256[4] memory scores = gateway.verify(claimant);
        assertEq(scores[2], 0);
    }

    function test_fullLifecycle_slashesLivenessForNoShow() public {
        uint256 challengeId = 1;

        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        uint256[] memory signals = new uint256[](3);
        signals[0] = 2; signals[1] = 97; signals[2] = 55;

        vm.prank(claimant);
        uint256 claimId = engine.submitClaim(challengeId, a, b, c, signals, bytes32(0));
        vm.roll(block.number + 5);
        engine.drawCommittee(claimId);
        address[] memory committee = engine.committeeOf(claimId);

        // Only first 5 vote yes; last 2 are no-shows (silent = no)
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(committee[i]);
            engine.vote(claimId, true);
        }

        vm.warp(block.timestamp + 25 hours);
        engine.finalize(claimId);

        // 5/7 yes = 7142 bps >= 6666 quorum => accepted
        AttestationEngine.Claim memory cl = engine.getClaim(claimId);
        assertEq(uint256(cl.status), uint256(AttestationEngine.ClaimStatus.FINALIZED_ACCEPT));

        // No-shows got liveness slash (1% of 5000 = 50)
        for (uint256 i = 5; i < 7; i++) {
            assertEq(vault.stakeOf(committee[i]), 5_000 ether - 50 ether, "liveness slash");
        }
        // Yes voters unslashed
        for (uint256 i = 0; i < 5; i++) {
            assertEq(vault.stakeOf(committee[i]), 5_000 ether);
        }
    }

    function test_submitClaim_revertsOnInactiveChallenge() public {
        // Deprecate the only challenge
        vm.prank(gov);
        registry.deprecate(1);

        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        uint256[] memory signals = new uint256[](3);
        signals[0] = 2; signals[1] = 97; signals[2] = 55;

        vm.expectRevert(AttestationEngine.ChallengeNotActive.selector);
        vm.prank(claimant);
        engine.submitClaim(1, a, b, c, signals, bytes32(0));
    }

    function test_submitClaim_revertsOnVerifierRejection() public {
        verifier.setAccept(false);

        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        uint256[] memory signals = new uint256[](3);
        signals[0] = 2; signals[1] = 97; signals[2] = 55;

        vm.expectRevert(AttestationEngine.InvalidProof.selector);
        vm.prank(claimant);
        engine.submitClaim(1, a, b, c, signals, bytes32(0));
    }
}
