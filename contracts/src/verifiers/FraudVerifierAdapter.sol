// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IZKVerifier} from "../interfaces/IZKVerifier.sol";

/// @dev Thin interface to the snarkjs-emitted fixed-size verifier
///      (4 public signals: bindingHash, base, modulus, claimedResult).
interface IFraudGroth16Verifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[4] calldata input
    ) external view returns (bool);
}

/// @title FraudVerifierAdapter — bridges the fraud Groth16 verifier to IZKVerifier
/// @notice AttestationEngine passes dynamic pubSignals; this adapter unpacks
///         the first 4 into the fixed-arity call expected by the generated
///         FraudVerifier.sol (emitted by snarkjs, not hand-edited).
///         Public signal order must match circuits/fraud/fraud.circom:
///           0. bindingHash
///           1. base
///           2. modulus
///           3. claimedResult
contract FraudVerifierAdapter is IZKVerifier {
    IFraudGroth16Verifier public immutable inner;

    error WrongSignalLength(uint256 got);

    constructor(IFraudGroth16Verifier _inner) {
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
            pubSignals[3]  // claimedResult
        ];
        return inner.verifyProof(a, b, c, fixedSignals);
    }
}
