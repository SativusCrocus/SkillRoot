// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IZKVerifier} from "../interfaces/IZKVerifier.sol";

/// @title MockVerifier — test double for IZKVerifier
/// @notice Stores lastBindingHash so tests can assert D2 revision behavior.
contract MockVerifier is IZKVerifier {
    bool public accept = true;
    uint256 public lastBindingHash;
    uint256[] public lastPubSignals;

    function setAccept(bool v) external {
        accept = v;
    }

    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[] calldata pubSignals
    ) external override returns (bool) {
        if (pubSignals.length > 0) {
            lastBindingHash = pubSignals[0];
            delete lastPubSignals;
            for (uint256 i = 0; i < pubSignals.length; i++) {
                lastPubSignals.push(pubSignals[i]);
            }
        }
        return accept;
    }

    function lastPubSignalsLength() external view returns (uint256) {
        return lastPubSignals.length;
    }
}
