/* SPDX-License-Identifier: MIT */
#include "mldsa44.h"
#include "sign_core.h"

_Static_assert(CRYPTO_PUBLICKEYBYTES == MLDSA44_PUBLICKEY_BYTES, "public key size");
_Static_assert(CRYPTO_SECRETKEYBYTES == MLDSA44_SECRETKEY_BYTES, "secret key size");
_Static_assert(CRYPTO_BYTES == MLDSA44_SIGNATURE_BYTES, "signature size");

static const uint8_t empty_input[1] = {0};

static int valid_message_context(const uint8_t *m, size_t mlen,
                                 const uint8_t *ctx, size_t ctxlen) {
  return (m != NULL || mlen == 0) && (ctx != NULL || ctxlen == 0)
      && ctxlen <= MLDSA44_CONTEXT_MAX_BYTES;
}

static size_t make_prefix(uint8_t prefix[257], const uint8_t *ctx, size_t ctxlen) {
  prefix[0] = 0; /* ordinary ML-DSA domain, FIPS 204 Algorithm 2 */
  prefix[1] = (uint8_t)ctxlen;
  for (size_t i = 0; i < ctxlen; ++i) prefix[i + 2] = ctx[i];
  return ctxlen + 2;
}

void mldsa44_clear(void *buffer, size_t length) {
  volatile uint8_t *p = (volatile uint8_t *)buffer;
  if (p != NULL) while (length-- != 0) *p++ = 0;
}

int mldsa44_keypair_from_seed(uint8_t pk[MLDSA44_PUBLICKEY_BYTES],
                            uint8_t sk[MLDSA44_SECRETKEY_BYTES],
                            const uint8_t seed[MLDSA44_SEED_BYTES]) {
  if (pk == NULL || sk == NULL || seed == NULL) return MLDSA44_ERR_INVALID;
  return mldsa44_core_keypair_from_seed(pk, sk, seed);
}

int mldsa44_sign(uint8_t sig[MLDSA44_SIGNATURE_BYTES], size_t *siglen,
                const uint8_t *m, size_t mlen,
                const uint8_t *ctx, size_t ctxlen,
                const uint8_t rnd[MLDSA44_RANDOM_BYTES],
                const uint8_t sk[MLDSA44_SECRETKEY_BYTES]) {
  uint8_t prefix[257];
  if (siglen == NULL) return MLDSA44_ERR_INVALID;
  *siglen = 0;
  if (sig == NULL || sk == NULL || rnd == NULL || !valid_message_context(m, mlen, ctx, ctxlen))
    return MLDSA44_ERR_INVALID;
  size_t prefix_len = make_prefix(prefix, ctx, ctxlen);
  return mldsa44_core_sign(sig, siglen, m == NULL ? empty_input : m, mlen,
                          prefix, prefix_len, rnd, sk);
}

int mldsa44_sign_deterministic(uint8_t sig[MLDSA44_SIGNATURE_BYTES], size_t *siglen,
                              const uint8_t *m, size_t mlen,
                              const uint8_t *ctx, size_t ctxlen,
                              const uint8_t sk[MLDSA44_SECRETKEY_BYTES]) {
  static const uint8_t zero_randomness[MLDSA44_RANDOM_BYTES] = {0};
  return mldsa44_sign(sig, siglen, m, mlen, ctx, ctxlen, zero_randomness, sk);
}

int mldsa44_verify(const uint8_t *sig, size_t siglen,
                  const uint8_t *m, size_t mlen,
                  const uint8_t *ctx, size_t ctxlen,
                  const uint8_t pk[MLDSA44_PUBLICKEY_BYTES]) {
  uint8_t prefix[257];
  if (sig == NULL || pk == NULL || siglen != MLDSA44_SIGNATURE_BYTES ||
      !valid_message_context(m, mlen, ctx, ctxlen)) return MLDSA44_ERR_INVALID;
  size_t prefix_len = make_prefix(prefix, ctx, ctxlen);
  return mldsa44_core_verify(sig, siglen, m == NULL ? empty_input : m, mlen,
                            prefix, prefix_len, pk);
}
