// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChallengeRegistry} from "../src/ChallengeRegistry.sol";
import {SKRToken} from "../src/SKRToken.sol";

/// @title SeedChallenges — proposes the math challenge
/// @notice Run against a live deployment. Governance must subsequently
///         activate the returned challenge id via Governance.propose /
///         execute flow (or directly via the registry if the deployer
///         still holds the governance role).
contract SeedChallenges is Script {
    function run() external returns (uint256 challengeId) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(pk);

        ChallengeRegistry registry = ChallengeRegistry(vm.envAddress("CHALLENGE_REGISTRY"));
        SKRToken token = SKRToken(vm.envAddress("SKR_TOKEN"));
        address mathVerifier = vm.envAddress("MATH_VERIFIER");
        bytes32 specCID = vm.envBytes32("MATH_SPEC_CID");
        bytes32 circuitHash = vm.envBytes32("MATH_CIRCUIT_HASH");

        console2.log("Seeding challenge as", sender);

        vm.startBroadcast(pk);
        token.approve(address(registry), type(uint256).max);
        challengeId = registry.propose(
            ChallengeRegistry.Domain.APPLIED_MATH,
            mathVerifier,
            specCID,
            circuitHash,
            1_000 ether
        );
        vm.stopBroadcast();

        console2.log("Proposed math challenge id", challengeId);
    }
}
