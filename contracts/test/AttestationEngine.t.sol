// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SKRToken} from "../src/SKRToken.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {ChallengeRegistry} from "../src/ChallengeRegistry.sol";
import {Sortition} from "../src/Sortition.sol";
import {AttestationStore} from "../src/AttestationStore.sol";
import {AttestationEngine} from "../src/AttestationEngine.sol";
import {MockVerifier} from "../src/mocks/MockVerifier.sol";

/// @title AttestationEngine unit tests
/// @notice Focused tests for D2 binding, revert paths, and voter-direction
///         slash accounting.
contract AttestationEngineTest is Test {
    SKRToken internal token;
    StakingVault internal vault;
    ChallengeRegistry internal registry;
    Sortition internal sortition;
    AttestationStore internal store;
    AttestationEngine internal engine;
    MockVerifier internal verifier;

    address internal gov = address(0xA11CE);
    address internal claimant = address(0xC1A1);
    address internal proposer = address(0xB0B);

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
        verifier = new MockVerifier();

        vault.setEngine(address(engine));
        store.setEngine(address(engine));
        vm.stopPrank();

        // Bond 10 validators
        for (uint256 i = 0; i < 10; i++) {
            address v = address(uint160(0x3000 + i));
            vm.prank(gov);
            token.transfer(v, 5_000 ether);
            vm.startPrank(v);
            token.approve(address(vault), 5_000 ether);
            vault.bond(5_000 ether);
            vm.stopPrank();
        }

        // Propose + activate a challenge
        vm.prank(gov);
        token.transfer(proposer, 10_000 ether);
        vm.startPrank(proposer);
        token.approve(address(registry), 10_000 ether);
        registry.propose(
            ChallengeRegistry.Domain.APPLIED_MATH,
            address(verifier),
            bytes32("spec"),
            bytes32("hash"),
            1_000 ether
        );
        vm.stopPrank();
        vm.prank(gov);
        registry.activate(1);
    }

    function _defaultSignals() internal pure returns (uint256[] memory s) {
        s = new uint256[](3);
        s[0] = 2; s[1] = 97; s[2] = 55;
    }

    function test_submitClaim_prependsBindingHashFromMsgSender() public {
        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;

        vm.prank(claimant);
        engine.submitClaim(1, a, b, c, _defaultSignals(), bytes32("cid"));

        uint256 expected = uint256(keccak256(abi.encode(claimant, uint256(1)))) & ((uint256(1) << 248) - 1);
        assertEq(verifier.lastBindingHash(), expected);
        assertEq(verifier.lastPubSignalsLength(), 4);
    }

    function test_submitClaim_differentClaimantsGetDifferentBindings() public {
        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;

        vm.prank(claimant);
        engine.submitClaim(1, a, b, c, _defaultSignals(), bytes32("cid"));
        uint256 hash1 = verifier.lastBindingHash();

        address other = address(0xD1FF);
        vm.prank(other);
        engine.submitClaim(1, a, b, c, _defaultSignals(), bytes32("cid"));
        uint256 hash2 = verifier.lastBindingHash();

        assertTrue(hash1 != hash2, "bindings should differ per claimant");
    }

    function test_bindingHashOf_matchesRecordedHash() public {
        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        vm.prank(claimant);
        engine.submitClaim(1, a, b, c, _defaultSignals(), bytes32(0));

        assertEq(
            engine.bindingHashOf(claimant, 1),
            verifier.lastBindingHash()
        );
    }

    function test_vote_revertsForNonMember() public {
        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        vm.prank(claimant);
        uint256 id = engine.submitClaim(1, a, b, c, _defaultSignals(), bytes32(0));

        vm.roll(block.number + 5);
        engine.drawCommittee(id);

        vm.expectRevert(AttestationEngine.NotCommitteeMember.selector);
        vm.prank(address(0xBADBAD));
        engine.vote(id, true);
    }

    function test_vote_revertsOnDoubleVote() public {
        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        vm.prank(claimant);
        uint256 id = engine.submitClaim(1, a, b, c, _defaultSignals(), bytes32(0));

        vm.roll(block.number + 5);
        engine.drawCommittee(id);
        address[] memory committee = engine.committeeOf(id);

        vm.prank(committee[0]);
        engine.vote(id, true);
        vm.prank(committee[0]);
        vm.expectRevert(AttestationEngine.AlreadyVoted.selector);
        engine.vote(id, false);
    }

    function test_finalize_revertsWhileVoteOpen() public {
        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        vm.prank(claimant);
        uint256 id = engine.submitClaim(1, a, b, c, _defaultSignals(), bytes32(0));

        vm.roll(block.number + 5);
        engine.drawCommittee(id);

        vm.expectRevert(AttestationEngine.VoteStillOpen.selector);
        engine.finalize(id);
    }

    function test_drawCommittee_revertsIfAlreadyDrawn() public {
        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        vm.prank(claimant);
        uint256 id = engine.submitClaim(1, a, b, c, _defaultSignals(), bytes32(0));

        vm.roll(block.number + 5);
        engine.drawCommittee(id);
        vm.expectRevert(AttestationEngine.CommitteeAlreadyDrawn.selector);
        engine.drawCommittee(id);
    }

    function test_transferGovernance() public {
        address newGov = address(0xBEEF);
        vm.prank(gov);
        engine.transferGovernance(newGov);
        assertEq(engine.governance(), newGov);
    }
}
