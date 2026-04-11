// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SKRToken} from "../src/SKRToken.sol";
import {Governance} from "../src/Governance.sol";

contract GovernanceTarget {
    uint256 public x;

    function setX(uint256 v) external {
        x = v;
    }
}

contract GovernanceTest is Test {
    SKRToken internal token;
    Governance internal governance;
    GovernanceTarget internal target;

    address internal gov = address(0xA11CE);
    address internal alice = address(0xA1);
    address internal bob = address(0xB0B);

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new SKRToken(gov);
        governance = new Governance(token);
        target = new GovernanceTarget();

        // Distribute: alice 10M, bob 10M, keep 80M with gov
        vm.startPrank(gov);
        token.transfer(alice, 10_000_000 ether);
        token.transfer(bob, 10_000_000 ether);
        vm.stopPrank();

        // Self-delegate for voting power
        vm.prank(gov); token.delegate(gov);
        vm.prank(alice); token.delegate(alice);
        vm.prank(bob); token.delegate(bob);

        // Advance 1s so delegations are in the past (ERC20Votes needs this)
        vm.warp(block.timestamp + 1);
    }

    function _propose() internal returns (uint256 id) {
        bytes memory data = abi.encodeCall(GovernanceTarget.setX, (42));
        vm.prank(alice);
        id = governance.propose(address(target), data, 0);
    }

    function test_propose_createsActiveProposal() public {
        uint256 id = _propose();
        assertEq(id, 1);
    }

    function test_castVote_countsWeight() public {
        uint256 id = _propose();
        vm.prank(alice);
        governance.castVote(id, true);
        vm.prank(bob);
        governance.castVote(id, true);

        Governance.Proposal memory p = governance.proposals(id);
        assertEq(p.forVotes, 20_000_000 ether);
        assertEq(p.againstVotes, 0);
    }

    function test_castVote_doubleVoteReverts() public {
        uint256 id = _propose();
        vm.prank(alice);
        governance.castVote(id, true);
        vm.prank(alice);
        vm.expectRevert(Governance.AlreadyVoted.selector);
        governance.castVote(id, true);
    }

    function test_execute_revertsOnQuorumNotMet() public {
        uint256 id = _propose();
        // Nobody votes
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert(Governance.QuorumNotMet.selector);
        governance.execute(id);
    }

    function test_execute_success() public {
        uint256 id = _propose();
        // Gov (80M) alone clears quorum
        vm.prank(gov);
        governance.castVote(id, true);

        vm.warp(block.timestamp + 6 days);
        governance.execute(id);
        assertEq(target.x(), 42);
    }

    function test_execute_revertsWhileVotingOpen() public {
        uint256 id = _propose();
        vm.prank(gov);
        governance.castVote(id, true);
        vm.expectRevert(Governance.VotingOpen.selector);
        governance.execute(id);
    }

    function test_execute_revertsOnDefeated() public {
        uint256 id = _propose();
        // Gov votes FOR, alice+bob vote AGAINST (20M against, 80M for — still passes)
        // So instead: alice FOR (10M), gov AGAINST (80M) → defeated but 10M does not meet 4% quorum of 100M = 4M ✓
        // Actually 10M >= 4M quorum, so quorum is met; 10M < 80M → defeated
        vm.prank(alice);
        governance.castVote(id, true);
        vm.prank(gov);
        governance.castVote(id, false);

        vm.warp(block.timestamp + 6 days);
        vm.expectRevert(Governance.Defeated.selector);
        governance.execute(id);
    }
}
