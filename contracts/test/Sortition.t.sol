// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SKRToken} from "../src/SKRToken.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {Sortition} from "../src/Sortition.sol";

contract SortitionTest is Test {
    SKRToken internal token;
    StakingVault internal vault;
    Sortition internal sortition;
    address internal gov = address(0xA11CE);
    address internal engine = address(0xE1);

    function setUp() public {
        vm.warp(1_700_000_000);
        vm.roll(1_000);
        token = new SKRToken(gov);
        vault = new StakingVault(token, gov);
        sortition = new Sortition(vault);

        vm.prank(gov);
        vault.setEngine(engine);
    }

    function _bondN(uint256 n, uint256 perValidator) internal {
        for (uint256 i = 0; i < n; i++) {
            address v = address(uint160(0x2000 + i));
            vm.prank(gov);
            token.transfer(v, perValidator);
            vm.startPrank(v);
            token.approve(address(vault), perValidator);
            vault.bond(perValidator);
            vm.stopPrank();
        }
    }

    function test_draw_revertsBeforeRevealDelay() public {
        _bondN(10, 5_000 ether);
        uint256 submissionBlock = block.number;
        // We're still at submissionBlock, not submissionBlock + REVEAL_DELAY + 1
        vm.expectRevert(Sortition.NotReadyToReveal.selector);
        sortition.drawCommittee(submissionBlock);
    }

    function test_draw_producesCommitteeOfSize7() public {
        _bondN(10, 5_000 ether);
        uint256 submissionBlock = block.number;
        vm.roll(submissionBlock + 5);

        address[] memory committee = sortition.drawCommittee(submissionBlock);
        assertEq(committee.length, 7);

        // All distinct
        for (uint256 i = 0; i < committee.length; i++) {
            assertTrue(committee[i] != address(0));
            for (uint256 j = i + 1; j < committee.length; j++) {
                assertTrue(committee[i] != committee[j], "duplicate in committee");
            }
        }
    }

    function test_draw_shrinksWhenValidatorsFewerThanSize() public {
        _bondN(3, 5_000 ether);
        uint256 submissionBlock = block.number;
        vm.roll(submissionBlock + 5);

        address[] memory committee = sortition.drawCommittee(submissionBlock);
        assertEq(committee.length, 3);
    }

    function test_draw_revertsOnNoValidators() public {
        uint256 submissionBlock = block.number;
        vm.roll(submissionBlock + 5);
        vm.expectRevert(Sortition.NoValidators.selector);
        sortition.drawCommittee(submissionBlock);
    }

    function test_draw_revertsAfterRevealWindow() public {
        _bondN(10, 5_000 ether);
        uint256 submissionBlock = block.number;
        // REVEAL_WINDOW = 240; roll way past
        vm.roll(submissionBlock + 4 + 241);
        vm.expectRevert(Sortition.RevealWindowExpired.selector);
        sortition.drawCommittee(submissionBlock);
    }
}
