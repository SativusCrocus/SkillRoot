// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {StakingVault} from "./StakingVault.sol";

/// @title Sortition — stake-weighted committee draw via future-blockhash entropy
/// @notice No oracle, no VRF. Entropy comes from `blockhash(submissionBlock + 4)`.
///         REVEAL_WINDOW = 240 blocks before the draw expires and the claim
///         must be resubmitted. Linear O(k·n) draw is fine for v0's validator set.
contract Sortition {
    uint256 public constant COMMITTEE_SIZE = 7;
    uint256 public constant REVEAL_DELAY = 4;
    uint256 public constant REVEAL_WINDOW = 240;

    StakingVault public immutable vault;

    error NotReadyToReveal();
    error RevealWindowExpired();
    error NoValidators();
    error InsufficientTotalStake();

    constructor(StakingVault _vault) {
        vault = _vault;
    }

    /// @notice Draw a stake-weighted committee using future-blockhash entropy.
    /// @param submissionBlock the block at which the claim was submitted
    /// @return committee an array of distinct validator addresses
    function drawCommittee(uint256 submissionBlock)
        external
        view
        returns (address[] memory committee)
    {
        uint256 revealAt = submissionBlock + REVEAL_DELAY;
        if (block.number <= revealAt) revert NotReadyToReveal();
        if (block.number > revealAt + REVEAL_WINDOW) revert RevealWindowExpired();

        bytes32 seed = blockhash(revealAt);
        // blockhash returns 0 for blocks older than 256 — REVEAL_WINDOW = 240 keeps us safe
        if (seed == bytes32(0)) revert RevealWindowExpired();

        address[] memory validators = vault.getValidators();
        uint256 n = validators.length;
        if (n == 0) revert NoValidators();

        uint256 total = vault.totalStake();
        if (total == 0) revert InsufficientTotalStake();

        uint256 k = COMMITTEE_SIZE > n ? n : COMMITTEE_SIZE;
        committee = new address[](k);

        // Build a mutable stake snapshot so we can zero-out picked validators
        uint256[] memory stakes = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            stakes[i] = vault.stakeOf(validators[i]);
        }

        uint256 remaining = total;
        uint256 picked = 0;

        for (uint256 draw = 0; draw < k; draw++) {
            if (remaining == 0) break;
            uint256 r = uint256(keccak256(abi.encode(seed, submissionBlock, draw))) % remaining;

            uint256 cum = 0;
            for (uint256 i = 0; i < n; i++) {
                uint256 s = stakes[i];
                if (s == 0) continue;
                cum += s;
                if (r < cum) {
                    committee[picked++] = validators[i];
                    remaining -= s;
                    stakes[i] = 0;
                    break;
                }
            }
        }

        // Shrink array if we picked fewer than k (e.g. remaining hit zero)
        if (picked != k) {
            assembly {
                mstore(committee, picked)
            }
        }
    }
}
