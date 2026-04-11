// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IZKVerifier} from "../interfaces/IZKVerifier.sol";

/// @dev Thin interface to the snarkjs-emitted fixed-size verifier
///      (4 public signals: bindingHash, targetCircuitHash, exploitTag, exploitCommitment).
interface IForgeGroth16Verifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[4] calldata input
    ) external view returns (bool);
}

/// @title ForgeVerifierAdapter — bridges snarkjs forge verifier to IZKVerifier
/// @notice ForgeGuard passes dynamic pubSignals; this adapter unpacks
///         the first 4 into the fixed-arity call expected by the generated
///         ForgeVerifier.sol (emitted by snarkjs).
contract ForgeVerifierAdapter is IZKVerifier {
    IForgeGroth16Verifier public immutable inner;

    error WrongSignalLength(uint256 got);

    constructor(IForgeGroth16Verifier _inner) {
        inner = _inner;
    }

    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata pubSignals
    ) external override returns (bool) {
        if (pubSignals.length != 4) revert WrongSignalLength(pubSignals.length);
        uint256[4] memory fixedSignals = [
            pubSignals[0], // bindingHash
            pubSignals[1], // targetCircuitHash
            pubSignals[2], // exploitTag
            pubSignals[3]  // exploitCommitment
        ];
        return inner.verifyProof(a, b, c, fixedSignals);
    }
}
