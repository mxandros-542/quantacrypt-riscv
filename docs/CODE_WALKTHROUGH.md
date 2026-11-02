# Reading the ML-DSA-44 implementation

Start with `examples/demo.c` to see how firmware calls the public API. It owns
the key/signature buffers and supplies a test seed, message, context, and
signing randomness. It checks every return value.

## Key generation: FIPS 204 Algorithm 6

`src/mldsa44.c:mldsa44_keypair_from_seed` checks pointers and calls
`src/sign_core.c:mldsa44_core_keypair_from_seed`.

Follow these operations in the core:

1. Copy the 32-byte seed and append the matrix dimensions 4, 4.
2. SHAKE256 expands it into the matrix seed, secret-sampling seed, and signing key seed.
3. `polyvec_matrix_expand` generates the matrix in NTT representation.
4. `polyvecl_uniform_eta` and `polyveck_uniform_eta` sample s1 and s2.
5. Transform s1, multiply by the matrix, reduce, and inverse transform.
6. Add s2 to obtain t = A*s1 + s2.
7. `polyveck_power2round` splits t into t1 and t0.
8. Pack the public key, hash it, and pack the expanded private key.

## Signing: FIPS 204 Algorithm 7

`src/mldsa44.c:mldsa44_sign` creates `00 || context_length || context` and calls
`src/sign_core.c:mldsa44_core_sign` with the prefix and message as separate inputs.

In the core, inspect the seed-buffer pointers `rho`, `tr`, `key`, `mu`, and
`rhoprime`. They represent different byte strings, not polynomial arrays.

The matrix and transforms of s1, s2, and t0 are prepared before the `rej:` label.
Each visit to that label uses the next mask nonce and performs a new attempt:

1. Sample y and calculate w = A*y through NTT arithmetic.
2. Decompose w and hash its encoded high part together with mu.
3. Expand the hash into the sparse challenge polynomial c and transform c.
4. Compute z = y + c*s1 and reject if z exceeds its bound.
5. Compute c*s2 and check the low-part bound.
6. Compute c*t0, check its bound, construct the hint, and check its weight.
7. Pack the challenge hash, z, and hint.

The reference uses an equivalent optimized hint construction. Its `make_hint`
arguments are decomposed low/high parts; do not substitute the arguments of
FIPS 204's abstract `MakeHint(z,r)` directly into that C function.

## Verification: FIPS 204 Algorithm 8

`mldsa44_verify` constructs the same context prefix. `mldsa44_core_verify`:

1. Checks the signature length, decodes the signature, and checks z's norm.
2. Computes the public-key hash and message representative.
3. Regenerates the matrix and challenge.
4. Computes A*z - c*(2^13*t1) in NTT form, then applies the inverse.
5. Uses the hint to reconstruct the high part of the commitment.
6. Hashes it and compares the result with the signature's challenge hash.

## NTT and representation details

Read `vendor/dilithium/ntt.c`, then `reduce.c`, then the polynomial wrappers in
`poly.c`. `ntt` uses eight stages with distances 128 down to 1. It leaves
addition/subtraction results lazily reduced and stores evaluations in the
reference's bit-reversed order.

Twiddle constants include a Montgomery factor R = 2^32. A Montgomery reduction
multiplies its input by R^-1 modulo q. Pointwise multiplication introduces
R^-1, and `invntt_tomont` supplies R, balancing the complete product.

The test `check_ntt_multiplication` in `tests/test_mldsa44.c` compares this entire
pipeline against independent, ordinary negacyclic multiplication. It includes
the identity x^255*x = -1 modulo x^256+1.

## Platform separation

Only `examples/platform.c` and `platform/ibex/` know about the processor's MMIO,
startup address, memory layout, and cycle CSRs. The cryptographic core itself
uses fixed-width C integers and caller-owned arrays. Keccak's 64-bit operations
are lowered to RV32 instructions by the compiler.
