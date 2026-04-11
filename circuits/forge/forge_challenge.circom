pragma circom 2.1.9;

include "poseidon.circom";
include "../common/claimant_binding.circom";

// ForgeChallenge — ZK-commits to an exploit vector targeting a SkillRoot circuit.
//
// This is the second parallel circuit added by the ForgeGuard layer.
// The core SkillRoot circuit (math.circom) remains untouched.
//
// Public signals (in order):
//   0. bindingHash        — D2 binding (keccak computed contract-side)
//   1. targetCircuitHash  — identifies the circuit under test
//   2. exploitTag         — exploit category (1=collision, 2=range, 3=underconstraint)
//   3. exploitCommitment  — Poseidon hash of the private exploit vector
//
// Private signals:
//   - exploitVector[4]    — the actual exploit data (4 field elements)
//
// ~600 constraints (Poseidon-4 dominates).

template ForgeChallenge() {
    // Public
    signal input bindingHash;
    signal input targetCircuitHash;
    signal input exploitTag;
    signal input exploitCommitment;

    // Private
    signal input exploitVector[4];

    // D2 binding passthrough (convention: always public signal 0)
    component passthrough = BindingPassthrough();
    passthrough.in <== bindingHash;

    // Poseidon commitment over the 4-element exploit vector
    component hasher = Poseidon(4);
    for (var i = 0; i < 4; i++) {
        hasher.inputs[i] <== exploitVector[i];
    }

    // Enforce: public commitment matches hash of private vector
    exploitCommitment === hasher.out;

    // Constrain targetCircuitHash and exploitTag into the arithmetic
    // so the compiler cannot optimize them away as unconstrained inputs.
    signal _anchor;
    _anchor <== targetCircuitHash * exploitTag;
}

component main {public [bindingHash, targetCircuitHash, exploitTag, exploitCommitment]} = ForgeChallenge();
