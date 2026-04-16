// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChallengeRegistry} from "../src/ChallengeRegistry.sol";

/// @notice Seed script — proposes and genesis-activates the first challenge.
///         Already executed on the v0.2.0-no-vote deployment (challenge 1 is ACTIVE).
///         Kept for reference; re-running will create challenge 2+.
contract SeedChallenges is Script {
    // v0.2.0-no-vote deployment addresses (Base Sepolia)
    address constant SKR_TOKEN              = 0xebEB1dAC3F774b47e28844D1493758838D8463B2;
    address constant CHALLENGE_REGISTRY     = 0xbD13B7822bBc4cC6C0C53CA08497643C6085294B;
    address constant FRAUD_VERIFIER_ADAPTER = 0x173241d25feb42EA8D9D3D4c767788c6F23C62A7;

    uint256 constant PROPOSER_BOND = 10_000 ether;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        IERC20 skr = IERC20(SKR_TOKEN);
        ChallengeRegistry registry = ChallengeRegistry(CHALLENGE_REGISTRY);

        // 1. Approve bond
        skr.approve(CHALLENGE_REGISTRY, PROPOSER_BOND);
        console2.log("Approved 10,000 SKR to ChallengeRegistry");

        // 2. Propose challenge: APPLIED_MATH (2), FraudVerifierAdapter, specCID, circuitHash, weight=100
        uint256 id = registry.propose(
            ChallengeRegistry.Domain.APPLIED_MATH,
            FRAUD_VERIFIER_ADAPTER,
            keccak256("modexp-v1"),
            keccak256("circuit-hash-v1"),
            100
        );
        console2.log("Proposed challenge id:", id);

        // 3. Genesis-activate (deployer one-shot)
        registry.genesisActivate(id);
        console2.log("Genesis-activated challenge", id);

        vm.stopBroadcast();
    }
}
