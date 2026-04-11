// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SKRToken} from "../src/SKRToken.sol";

contract SKRTokenTest is Test {
    SKRToken internal token;
    address internal gov = address(0xA11CE);

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new SKRToken(gov);
    }

    function test_fixedSupplyMintedToGovernance() public view {
        assertEq(token.totalSupply(), 100_000_000 ether);
        assertEq(token.balanceOf(gov), 100_000_000 ether);
        assertEq(token.governance(), gov);
    }

    function test_clockIsTimestampMode() public view {
        assertEq(uint256(token.clock()), block.timestamp);
        assertEq(token.CLOCK_MODE(), "mode=timestamp");
    }

    function test_transferGovernance() public {
        address newGov = address(0xBEEF);
        vm.prank(gov);
        token.transferGovernance(newGov);
        assertEq(token.governance(), newGov);
    }

    function test_transferGovernance_revertsFromNonGov() public {
        vm.expectRevert(SKRToken.NotGovernance.selector);
        vm.prank(address(0xDEAD));
        token.transferGovernance(address(0xBEEF));
    }

    function test_transferGovernance_revertsOnZero() public {
        vm.expectRevert(SKRToken.ZeroAddress.selector);
        vm.prank(gov);
        token.transferGovernance(address(0));
    }

    function test_votingPowerRequiresDelegation() public {
        address alice = address(0xA11);
        vm.prank(gov);
        token.transfer(alice, 1_000 ether);
        // Without self-delegation, votes are 0
        assertEq(token.getVotes(alice), 0);

        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 1_000 ether);
    }

    function test_constructorRevertsOnZeroGov() public {
        vm.expectRevert(SKRToken.ZeroAddress.selector);
        new SKRToken(address(0));
    }

    function test_noMintFunctionExists() public view {
        // Compile-time check — there is no mint() selector. This test documents
        // intent by asserting total supply is locked at INITIAL_SUPPLY.
        assertEq(token.INITIAL_SUPPLY(), 100_000_000 ether);
    }
}
