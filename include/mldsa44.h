/* SPDX-License-Identifier: MIT */
#ifndef MLDSA44_H
#define MLDSA44_H

#include <stddef.h>
#include <stdint.h>

#define MLDSA44_PUBLICKEY_BYTES 1312u
#define MLDSA44_SECRETKEY_BYTES 2560u
#define MLDSA44_SIGNATURE_BYTES 2420u
#define MLDSA44_SEED_BYTES 32u
#define MLDSA44_RANDOM_BYTES 32u
#define MLDSA44_CONTEXT_MAX_BYTES 255u

#define MLDSA44_OK 0
#define MLDSA44_ERR_INVALID -1
#define MLDSA44_ERR_RETRY_LIMIT -2

#ifdef __cplusplus
extern "C" {
#endif

/* Pure ML-DSA-44 (FIPS 204), detached signatures, byte-oriented messages.
 * No allocation, OS calls, or hidden/global RNG. All output buffers must have
 * the stated capacity, and all buffers must be non-overlapping.
 * Message/context may be NULL only if their corresponding length is zero.
 * pk and sk inputs must point to complete fixed-size encodings.
 * Secret keys are trusted inputs; this API does not validate arbitrary sk data.
 */

/* seed must be 32 fresh, cryptographically random bytes for a real key.
 * Reusing a seed deliberately reproduces the same key pair. */
int mldsa44_keypair_from_seed(uint8_t pk[MLDSA44_PUBLICKEY_BYTES],
                            uint8_t sk[MLDSA44_SECRETKEY_BYTES],
                            const uint8_t seed[MLDSA44_SEED_BYTES]);

/* Hedged signing: supply 32 fresh random bytes in rnd.
 * siglen is set to zero on error. Context is bound to the signature.
 * This is the ordinary external ML-DSA interface, not HashML-DSA/prehash. */
int mldsa44_sign(uint8_t sig[MLDSA44_SIGNATURE_BYTES], size_t *siglen,
                const uint8_t *message, size_t message_len,
                const uint8_t *context, size_t context_len,
                const uint8_t rnd[MLDSA44_RANDOM_BYTES],
                const uint8_t sk[MLDSA44_SECRETKEY_BYTES]);

/* FIPS 204 deterministic signing uses an all-zero rnd; key generation still
 * requires a cryptographically random seed. */
int mldsa44_sign_deterministic(uint8_t sig[MLDSA44_SIGNATURE_BYTES], size_t *siglen,
                              const uint8_t *message, size_t message_len,
                              const uint8_t *context, size_t context_len,
                              const uint8_t sk[MLDSA44_SECRETKEY_BYTES]);

/* Returns 0 for a valid signature; -1 for invalid signatures/arguments. */
int mldsa44_verify(const uint8_t *sig, size_t siglen,
                  const uint8_t *message, size_t message_len,
                  const uint8_t *context, size_t context_len,
                  const uint8_t pk[MLDSA44_PUBLICKEY_BYTES]);

/* Explicit caller-buffer clearing (does not scrub all internal stack frames). */
void mldsa44_clear(void *buffer, size_t length);

#ifdef __cplusplus
}
#endif
#endif
