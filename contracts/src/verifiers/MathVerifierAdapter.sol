// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IZKVerifier} from "../interfaces/IZKVerifier.sol";

/// @dev Thin interface to the snarkjs-emitted fixed-size verifier
///      (4 public signals: bindingHash, base, modulus, result).
interface IMathGroth16Verifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[4] calldata input
    ) external view returns (bool);
}

/// @title MathVerifierAdapter — bridges snarkjs fixed-size verifier to IZKVerifier
/// @notice AttestationEngine passes dynamic pubSignals; this adapter unpacks
///         the first 4 into the fixed-arity call expected by the generated
///         MathVerifier.sol (which is emitted by snarkjs and not hand-edited).
contract MathVerifierAdapter is IZKVerifier {
    IMathGroth16Verifier public immutable inner;

    error WrongSignalLength(uint256 got);

    constructor(IMathGroth16Verifier _inner) {
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
            pubSignals[1], // base
            pubSignals[2], // modulus
            pubSignals[3]  // result
        ];
        return inner.verifyProof(a, b, c, fixedSignals);
    }
}
