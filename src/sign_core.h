/* Private adapter interface. Upstream arithmetic types remain private. */
#ifndef MLDSA44_SIGN_CORE_H
#define MLDSA44_SIGN_CORE_H
#include <stddef.h>
#include <stdint.h>
#include "params.h"
#if DILITHIUM_MODE != 2
#error "This package implements ML-DSA-44 only; DILITHIUM_MODE must be 2"
#endif

int mldsa44_core_keypair_from_seed(uint8_t *pk, uint8_t *sk, const uint8_t seed[32]);
int mldsa44_core_sign(uint8_t *sig, size_t *siglen,
                     const uint8_t *m, size_t mlen,
                     const uint8_t *prefix, size_t prefix_len,
                     const uint8_t rnd[32], const uint8_t *sk);
int mldsa44_core_verify(const uint8_t *sig, size_t siglen,
                       const uint8_t *m, size_t mlen,
                       const uint8_t *prefix, size_t prefix_len,
                       const uint8_t *pk);
#endif
