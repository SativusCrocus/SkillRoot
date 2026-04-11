pragma circom 2.1.9;

// BindingPassthrough — the D2 pattern
//
// The claimant binding hash is computed by AttestationEngine in Solidity:
//     bindingHash = keccak256(abi.encode(msg.sender, challengeId))
// and prepended to the proof's public signals as signal[0]. Circuits do
// NOT compute keccak. They only need to expose `bindingHash` as a
// pass-through public input so the verifier contract can pin it into the
// proof, while the circuit can also embed it into its arithmetic if it
// wants to bind private witness to the caller.
//
// This template is a no-op wire that exists mainly to document the
// convention: if you see `bindingHash <== BindingPassthrough()(bh);`
// in a circuit, it means "publish bh as a public signal, by convention
// always in position 0 of the signals array".
template BindingPassthrough() {
    signal input  in;
    signal output out;
    out <== in;
}
