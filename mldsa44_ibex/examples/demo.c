/* SPDX-License-Identifier: MIT */
#include "mldsa44.h"
#include "platform.h"

/* Large buffers are static so they do not add to the signing call's stack. */
static uint8_t pk[MLDSA44_PUBLICKEY_BYTES];
static uint8_t sk[MLDSA44_SECRETKEY_BYTES];
static uint8_t signature[MLDSA44_SIGNATURE_BYTES];
static uint8_t seed[MLDSA44_SEED_BYTES];
static uint8_t rnd[MLDSA44_RANDOM_BYTES];
static uint8_t message[] = "Ibex ML-DSA-44 software baseline: firmware image v1";
static const uint8_t context[] = "minor-project";

static void report_cycles(const char *operation, uint64_t begin, uint64_t end) {
#if defined(MLDSA44_IBEX)
  demo_puts(operation);
  demo_puts(" cycles = ");
  demo_hex64(end - begin);
  demo_puts("\n");
#else
  (void)operation; (void)begin; (void)end;
#endif
}

static int fail(const char *message_text) {
  demo_puts("FAIL: "); demo_puts(message_text); demo_puts("\n");
  mldsa44_clear(sk, sizeof sk);
  return 1;
}

int main(void) {
  size_t signature_len = 0;
  uint64_t begin, end;
  int result;
  demo_puts("ML-DSA-44 software demo\n");
  demo_puts("DEMO ONLY: fixed test seed/randomness; never use these for real keys.\n");
  demo_puts("pk=1312 bytes, sk=2560 bytes, signature=2420 bytes\n");
  for (size_t i = 0; i < sizeof seed; ++i) seed[i] = (uint8_t)i;
  for (size_t i = 0; i < sizeof rnd; ++i) rnd[i] = (uint8_t)(0xa0u + i);

  begin = demo_cycles();
  result = mldsa44_keypair_from_seed(pk, sk, seed);
  end = demo_cycles();
  if (result != MLDSA44_OK) return fail("key generation");
  demo_puts("PASS: key generation\n");
  report_cycles("keygen", begin, end);

  begin = demo_cycles();
  result = mldsa44_sign(signature, &signature_len, message, sizeof message - 1,
                       context, sizeof context - 1, rnd, sk);
  end = demo_cycles();
  if (result != MLDSA44_OK || signature_len != sizeof signature) return fail("signing");
  demo_puts("PASS: signing\n");
  report_cycles("sign", begin, end);

  begin = demo_cycles();
  result = mldsa44_verify(signature, signature_len, message, sizeof message - 1,
                         context, sizeof context - 1, pk);
  end = demo_cycles();
  if (result != MLDSA44_OK) return fail("valid signature rejected");
  demo_puts("PASS: valid signature accepted\n");
  report_cycles("verify", begin, end);

  message[0] ^= 1u;
  result = mldsa44_verify(signature, signature_len, message, sizeof message - 1,
                         context, sizeof context - 1, pk);
  message[0] ^= 1u;
  if (result == MLDSA44_OK) return fail("modified message accepted");
  demo_puts("PASS: modified message rejected\n");

  signature[0] ^= 1u;
  result = mldsa44_verify(signature, signature_len, message, sizeof message - 1,
                         context, sizeof context - 1, pk);
  if (result == MLDSA44_OK) return fail("modified signature accepted");
  demo_puts("PASS: modified signature rejected\n");
  mldsa44_clear(sk, sizeof sk);
  mldsa44_clear(seed, sizeof seed);
  demo_puts("ALL TESTS PASSED\n");
  return 0;
}
