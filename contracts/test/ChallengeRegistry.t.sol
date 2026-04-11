// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SKRToken} from "../src/SKRToken.sol";
import {ChallengeRegistry} from "../src/ChallengeRegistry.sol";

contract ChallengeRegistryTest is Test {
    SKRToken internal token;
    ChallengeRegistry internal registry;
    address internal gov = address(0xA11CE);
    address internal proposer = address(0xB0B);
    address internal fakeVerifier = address(0xD1A1);

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new SKRToken(gov);
        registry = new ChallengeRegistry(token, gov);

        vm.prank(gov);
        token.transfer(proposer, 30_000 ether);
    }

    function _propose() internal returns (uint256 id) {
        vm.startPrank(proposer);
        token.approve(address(registry), 10_000 ether);
        id = registry.propose(
            ChallengeRegistry.Domain.APPLIED_MATH,
            fakeVerifier,
            bytes32("spec"),
            bytes32("hash"),
            1_000 ether
        );
        vm.stopPrank();
    }

    function test_propose_holdsBondAndCreatesPending() public {
        uint256 id = _propose();
        assertEq(id, 1);

        ChallengeRegistry.Challenge memory c = registry.getChallenge(id);
        assertEq(uint256(c.status), uint256(ChallengeRegistry.Status.PENDING));
        assertEq(c.proposer, proposer);
        assertEq(c.verifier, fakeVerifier);
        assertEq(token.balanceOf(address(registry)), 10_000 ether);
    }

    function test_activate_returnsBondAndMarksActive() public {
        uint256 id = _propose();
        uint256 balBefore = token.balanceOf(proposer);

        vm.prank(gov);
        registry.activate(id);

        assertTrue(registry.isActive(id));
        assertEq(token.balanceOf(proposer), balBefore + 10_000 ether);
        assertEq(registry.bondOf(id), 0);
    }

    function test_activate_onlyGovernance() public {
        uint256 id = _propose();
        vm.expectRevert(ChallengeRegistry.NotGovernance.selector);
        registry.activate(id);
    }

    function test_reject_burnsBond() public {
        uint256 id = _propose();
        vm.prank(gov);
        registry.reject(id);

        ChallengeRegistry.Challenge memory c = registry.getChallenge(id);
        assertEq(uint256(c.status), uint256(ChallengeRegistry.Status.REJECTED));
        assertEq(
            token.balanceOf(0x000000000000000000000000000000000000dEaD),
            10_000 ether
        );
    }

    function test_deprecate_onlyActive() public {
        uint256 id = _propose();
        // Can't deprecate while PENDING
        vm.prank(gov);
        vm.expectRevert(ChallengeRegistry.InvalidStatus.selector);
        registry.deprecate(id);

        vm.prank(gov);
        registry.activate(id);

        vm.prank(gov);
        registry.deprecate(id);
        assertFalse(registry.isActive(id));
    }

    function test_propose_revertsOnZeroVerifier() public {
        vm.startPrank(proposer);
        token.approve(address(registry), 10_000 ether);
        vm.expectRevert(ChallengeRegistry.ZeroAddress.selector);
        registry.propose(
            ChallengeRegistry.Domain.APPLIED_MATH,
            address(0),
            bytes32("spec"),
            bytes32("hash"),
            1_000 ether
        );
        vm.stopPrank();
    }
}
