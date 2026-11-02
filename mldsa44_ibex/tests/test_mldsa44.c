/* SPDX-License-Identifier: MIT */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "mldsa44.h"
#include "poly.h"
#include "fips202.h"

#define CHECK(condition) do { if (!(condition)) { \
  fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); return 1; \
} } while (0)

static uint8_t pk[MLDSA44_PUBLICKEY_BYTES], sk[MLDSA44_SECRETKEY_BYTES];
static uint8_t pk2[MLDSA44_PUBLICKEY_BYTES], sk2[MLDSA44_SECRETKEY_BYTES];
static uint8_t sig[MLDSA44_SIGNATURE_BYTES], sig2[MLDSA44_SIGNATURE_BYTES];
static uint8_t message[4096], context[256];
static uint32_t random_state = 1; /* TEST DATA ONLY */

static uint32_t test_random(void) {
  random_state ^= random_state << 13;
  random_state ^= random_state >> 17;
  random_state ^= random_state << 5;
  return random_state;
}

static int32_t canonical(int64_t value) {
  value %= Q;
  return (int32_t)(value < 0 ? value + Q : value);
}

static int check_ntt_multiplication(void) {
  poly a, b, a_hat, b_hat, product;
  int64_t expected[N];
  for (unsigned int test = 0; test < 12; ++test) {
    for (unsigned int i = 0; i < N; ++i) {
      a.coeffs[i] = (int32_t)(test_random() % Q);
      b.coeffs[i] = (int32_t)(test_random() % Q);
      expected[i] = 0;
    }
    if (test == 0) { /* x^255 * x = -1 in the negacyclic ring */
      memset(&a, 0, sizeof a); memset(&b, 0, sizeof b);
      a.coeffs[255] = 1; b.coeffs[1] = 1;
    }
    for (unsigned int i = 0; i < N; ++i)
      for (unsigned int j = 0; j < N; ++j) {
        int64_t term = (int64_t)a.coeffs[i] * b.coeffs[j];
        if (i + j < N) expected[i + j] += term;
        else expected[i + j - N] -= term;
      }
    a_hat = a; b_hat = b;
    poly_ntt(&a_hat); poly_ntt(&b_hat);
    poly_pointwise_montgomery(&product, &a_hat, &b_hat);
    poly_invntt_tomont(&product);
    for (unsigned int i = 0; i < N; ++i)
      CHECK(canonical(product.coeffs[i]) == canonical(expected[i]));
  }
  puts("PASS: 12 NTT products match independent negacyclic schoolbook multiplication");
  return 0;
}

int main(void) {
  uint8_t seed[32], rnd[32];
  size_t len = 0, len2 = 0;
  const size_t lengths[] = {0, 1, 32, 59, 256, 1024, 4096};
  for (size_t i = 0; i < sizeof message; ++i) message[i] = (uint8_t)test_random();
  for (size_t i = 0; i < sizeof context; ++i) context[i] = (uint8_t)i;
  for (unsigned int test = 0; test < sizeof lengths / sizeof lengths[0]; ++test) {
    for (size_t i = 0; i < sizeof seed; ++i) {
      seed[i] = (uint8_t)test_random(); rnd[i] = (uint8_t)test_random();
    }
    size_t mlen = lengths[test];
    size_t ctxlen = test == 0 ? 0 : (test == 6 ? 255 : 13);
    const uint8_t *m = mlen == 0 ? NULL : message;
    const uint8_t *ctx = ctxlen == 0 ? NULL : context;
    CHECK(mldsa44_keypair_from_seed(pk, sk, seed) == 0);
    CHECK(mldsa44_keypair_from_seed(pk2, sk2, seed) == 0);
    CHECK(memcmp(pk, pk2, sizeof pk) == 0 && memcmp(sk, sk2, sizeof sk) == 0);
    CHECK(mldsa44_sign_deterministic(sig, &len, m, mlen, ctx, ctxlen, sk) == 0);
    CHECK(mldsa44_sign_deterministic(sig2, &len2, m, mlen, ctx, ctxlen, sk) == 0);
    CHECK(len == sizeof sig && len2 == len && memcmp(sig, sig2, len) == 0);
    CHECK(mldsa44_verify(sig, len, m, mlen, ctx, ctxlen, pk) == 0);
    CHECK(mldsa44_sign(sig2, &len2, m, mlen, ctx, ctxlen, rnd, sk) == 0);
    CHECK(memcmp(sig, sig2, len) != 0);
    CHECK(mldsa44_verify(sig2, len2, m, mlen, ctx, ctxlen, pk) == 0);

    if (mlen != 0) {
      message[mlen / 2] ^= 1;
      CHECK(mldsa44_verify(sig, len, m, mlen, ctx, ctxlen, pk) != 0);
      message[mlen / 2] ^= 1;
    } else CHECK(mldsa44_verify(sig, len, message, 1, ctx, ctxlen, pk) != 0);
    if (ctxlen != 0) {
      context[0] ^= 1;
      CHECK(mldsa44_verify(sig, len, m, mlen, ctx, ctxlen, pk) != 0);
      context[0] ^= 1;
    } else CHECK(mldsa44_verify(sig, len, m, mlen, context, 1, pk) != 0);

    const size_t positions[] = {0, 32, 1200, sizeof sig - 1};
    for (size_t i = 0; i < sizeof positions / sizeof positions[0]; ++i) {
      sig[positions[i]] ^= 1;
      CHECK(mldsa44_verify(sig, len, m, mlen, ctx, ctxlen, pk) != 0);
      sig[positions[i]] ^= 1;
    }
    pk[0] ^= 1;
    CHECK(mldsa44_verify(sig, len, m, mlen, ctx, ctxlen, pk) != 0);
    pk[0] ^= 1;
    CHECK(mldsa44_verify(sig, len - 1, m, mlen, ctx, ctxlen, pk) != 0);
    CHECK(mldsa44_verify(sig, len + 1, m, mlen, ctx, ctxlen, pk) != 0);
    memcpy(sig2, sig, sizeof sig);
    sig2[sizeof sig2 - 1] = 81; /* hint weight limit is 80 */
    CHECK(mldsa44_verify(sig2, sizeof sig2, m, mlen, ctx, ctxlen, pk) != 0);
  }
  puts("PASS: seeded keygen, deterministic/hedged signing, empty and long messages, context binding, tampering, malformed signatures");

  len = 99;
  CHECK(mldsa44_sign(sig, &len, message, 1, context, 256, rnd, sk) == -1 && len == 0);
  CHECK(mldsa44_sign(sig, &len, NULL, 1, NULL, 0, rnd, sk) == -1);
  CHECK(mldsa44_sign(sig, &len, message, 1, NULL, 1, rnd, sk) == -1);
  CHECK(mldsa44_sign(sig, &len, message, 1, NULL, 0, NULL, sk) == -1);
  CHECK(mldsa44_sign(sig, NULL, message, 1, NULL, 0, rnd, sk) == -1);
  CHECK(mldsa44_keypair_from_seed(NULL, sk, seed) == -1);
  CHECK(mldsa44_verify(NULL, sizeof sig, message, 1, NULL, 0, pk) == -1);
  CHECK(mldsa44_verify(sig, sizeof sig, NULL, 1, NULL, 0, pk) == -1);
  CHECK(mldsa44_verify(sig, sizeof sig, message, 1, context, 256, pk) == -1);
  memset(rnd, 0xa5, sizeof rnd);
  mldsa44_clear(rnd, sizeof rnd);
  for (size_t i = 0; i < sizeof rnd; ++i) CHECK(rnd[i] == 0);
  CHECK(check_ntt_multiplication() == 0);
  mldsa44_clear(sk, sizeof sk); mldsa44_clear(sk2, sizeof sk2);
  puts("ALL NATIVE TESTS PASSED");
  return 0;
}
