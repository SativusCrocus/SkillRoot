// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SKRToken} from "../src/SKRToken.sol";
import {StakingVault} from "../src/StakingVault.sol";

contract StakingVaultTest is Test {
    SKRToken internal token;
    StakingVault internal vault;
    address internal gov = address(0xA11CE);
    address internal engine = address(0xE1);
    address internal alice = address(0xA1);
    address internal bob = address(0xB0B);

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new SKRToken(gov);
        vault = new StakingVault(token, gov);

        vm.prank(gov);
        vault.setEngine(engine);

        vm.startPrank(gov);
        token.transfer(alice, 10_000 ether);
        token.transfer(bob, 10_000 ether);
        vm.stopPrank();
    }

    function _bond(address who, uint256 amt) internal {
        vm.startPrank(who);
        token.approve(address(vault), amt);
        vault.bond(amt);
        vm.stopPrank();
    }

    function test_bond_addsStakeAndValidator() public {
        _bond(alice, 1_000 ether);
        assertEq(vault.stakeOf(alice), 1_000 ether);
        assertEq(vault.totalStake(), 1_000 ether);
        assertEq(vault.validatorCount(), 1);
        assertEq(vault.validatorIdx(alice), 1);
    }

    function test_bond_revertsBelowMin() public {
        vm.startPrank(alice);
        token.approve(address(vault), 999 ether);
        vm.expectRevert(StakingVault.BelowMinStake.selector);
        vault.bond(999 ether);
        vm.stopPrank();
    }

    function test_requestUnbond_fullExit_removesFromValidators() public {
        _bond(alice, 1_000 ether);
        _bond(bob, 2_000 ether);
        assertEq(vault.validatorCount(), 2);

        vm.prank(alice);
        vault.requestUnbond(1_000 ether);

        assertEq(vault.stakeOf(alice), 0);
        assertEq(vault.validatorIdx(alice), 0, "alice removed");
        assertEq(vault.validatorCount(), 1);
        // Swap-pop put bob at index 0 (1-indexed = 1)
        assertEq(vault.validatorIdx(bob), 1);
    }

    function test_requestUnbond_partial_mustStayAboveMin() public {
        _bond(alice, 2_000 ether);
        // Cannot leave 500 ether (below MIN_STAKE)
        vm.startPrank(alice);
        vm.expectRevert(StakingVault.BelowMinStake.selector);
        vault.requestUnbond(1_500 ether);
        vm.stopPrank();
    }

    function test_withdraw_afterDelay() public {
        _bond(alice, 1_000 ether);

        vm.prank(alice);
        vault.requestUnbond(1_000 ether);

        vm.prank(alice);
        vm.expectRevert(StakingVault.StillLocked.selector);
        vault.withdraw();

        vm.warp(block.timestamp + 14 days + 1);
        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw();
        assertEq(token.balanceOf(alice), balBefore + 1_000 ether);
    }

    function test_slash_burnsToDead_andRemovesBelowMin() public {
        _bond(alice, 1_000 ether);
        uint256 supplyBefore = token.totalSupply();

        // Slashing 500 drops alice to 500 (below min) → removed
        vm.prank(engine);
        vault.slash(alice, 500 ether);

        assertEq(vault.stakeOf(alice), 500 ether);
        assertEq(vault.validatorIdx(alice), 0, "removed");
        assertEq(token.balanceOf(0x000000000000000000000000000000000000dEaD), 500 ether);
        // Total supply unchanged — we burn to 0xdead, not call _burn
        assertEq(token.totalSupply(), supplyBefore);
    }

    function test_slash_onlyEngine() public {
        _bond(alice, 1_000 ether);
        vm.expectRevert(StakingVault.NotEngine.selector);
        vault.slash(alice, 10 ether);
    }

    function test_setEngine_onlyOnce() public {
        vm.startPrank(gov);
        vm.expectRevert(StakingVault.EngineAlreadySet.selector);
        vault.setEngine(address(0xBEEF));
        vm.stopPrank();
    }
}
