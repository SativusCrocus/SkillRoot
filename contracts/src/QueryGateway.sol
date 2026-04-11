// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AttestationStore} from "./AttestationStore.sol";

/// @title QueryGateway — read-only attestation score aggregator
/// @notice Stable read surface for dApps and wallets. Wraps AttestationStore
///         so the UI does not need the full record shape.
contract QueryGateway {
    AttestationStore public immutable store;

    constructor(AttestationStore _store) {
        store = _store;
    }

    /// @notice Returns [algo, formalVer, appliedMath, secCode] decayed scores.
    function verify(address claimant) external view returns (uint256[4] memory) {
        return store.scoresOf(claimant);
    }

    function records(address claimant) external view returns (AttestationStore.Record[] memory) {
        return store.recordsOf(claimant);
    }
}
