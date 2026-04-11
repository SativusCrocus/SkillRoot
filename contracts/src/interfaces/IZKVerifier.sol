// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Dynamic-arity Groth16 verifier interface. Adapters wrap the
/// fixed-size verifiers emitted by snarkjs.
/// @dev Not declared `view` so test mocks may record calldata. Real
///      Groth16 verifier adapters are pure w.r.t. storage and may be
///      implemented as `view` internally; they still satisfy this interface.
interface IZKVerifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata pubSignals
    ) external returns (bool);
}
