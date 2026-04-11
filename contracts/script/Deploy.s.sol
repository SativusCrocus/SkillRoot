// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {SKRToken} from "../src/SKRToken.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {ChallengeRegistry} from "../src/ChallengeRegistry.sol";
import {Sortition} from "../src/Sortition.sol";
import {AttestationStore} from "../src/AttestationStore.sol";
import {AttestationEngine} from "../src/AttestationEngine.sol";
import {QueryGateway} from "../src/QueryGateway.sol";
import {Governance} from "../src/Governance.sol";
import {ForgeGuard} from "../src/ForgeGuard.sol";

/// @title Deploy — end-to-end SkillRoot v0 deployment
/// @notice Deploys 8 production contracts. The math verifier adapter is
///         deployed separately by build-circuits.sh once the snarkjs
///         artifacts exist. Governance is the deployer initially and
///         should be transferred to the Governance contract post-setup.
contract Deploy is Script {
    struct Deployed {
        SKRToken token;
        Governance governance;
        StakingVault vault;
        ChallengeRegistry registry;
        Sortition sortition;
        AttestationStore store;
        AttestationEngine engine;
        QueryGateway gateway;
        ForgeGuard forgeGuard;
    }

    function run() external returns (Deployed memory d) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // 1. Token (mints 100M to deployer as initial governance)
        d.token = new SKRToken(deployer);

        // 2. Governance contract (takes token reference for voting power)
        d.governance = new Governance(d.token);

        // 3. Subsystem contracts — deployer holds governance role during setup
        d.vault = new StakingVault(d.token, deployer);
        d.registry = new ChallengeRegistry(d.token, deployer);
        d.sortition = new Sortition(d.vault);
        d.store = new AttestationStore(deployer);

        // 4. Engine — the orchestrator
        d.engine = new AttestationEngine(d.registry, d.vault, d.sortition, d.store, deployer);

        // 5. Read-only gateway
        d.gateway = new QueryGateway(d.store);

        // 6. ForgeGuard — parallel security layer
        d.forgeGuard = new ForgeGuard(d.token, d.registry, d.vault, deployer);

        // 7. Wire engine + forge permissions
        d.vault.setEngine(address(d.engine));
        d.store.setEngine(address(d.engine));
        d.vault.setForgeGuard(address(d.forgeGuard));

        // 8. Optionally transfer governance of all subsystems to the Governance
        //    contract. Skip on testnet / anvil so the deployer can seed the
        //    initial challenge directly; the handover is performed in a
        //    follow-up step (see scripts/deploy-sepolia.sh and
        //    docs/bootstrapping.md week 8).
        bool skipTransfer = vm.envOr("SKIP_GOV_TRANSFER", uint256(0)) == 1;
        if (!skipTransfer) {
            d.token.transfer(address(d.governance), d.token.balanceOf(deployer));
            d.token.transferGovernance(address(d.governance));
            d.vault.transferGovernance(address(d.governance));
            d.registry.transferGovernance(address(d.governance));
            d.store.transferGovernance(address(d.governance));
            d.engine.transferGovernance(address(d.governance));
            d.forgeGuard.transferGovernance(address(d.governance));
        }

        vm.stopBroadcast();

        console2.log("SKRToken",          address(d.token));
        console2.log("Governance",        address(d.governance));
        console2.log("StakingVault",      address(d.vault));
        console2.log("ChallengeRegistry", address(d.registry));
        console2.log("Sortition",         address(d.sortition));
        console2.log("AttestationStore",  address(d.store));
        console2.log("AttestationEngine", address(d.engine));
        console2.log("QueryGateway",      address(d.gateway));
        console2.log("ForgeGuard",        address(d.forgeGuard));
    }
}
