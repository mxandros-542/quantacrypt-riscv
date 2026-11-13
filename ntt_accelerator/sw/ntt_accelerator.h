#ifndef MLDSA_NTT_ACCELERATOR_H
#define MLDSA_NTT_ACCELERATOR_H

#include <stddef.h>
#include <stdint.h>

/* Generic MMIO polling example; not a masked or constant-time software driver.
 * The caller supplies canonical arithmetic shares and a device-memory mapping.
 * Add architecture-specific MMIO barriers to these accessors when required. */
#define NTT_ACCEL_N 256u
#define NTT_ACCEL_Q 8380417u
#define NTT_ACCEL_CONTROL 0x00u
#define NTT_ACCEL_STATUS 0x04u
#define NTT_ACCEL_INPUT_SHARE0 0x08u
#define NTT_ACCEL_INPUT_SHARE1 0x0cu
#define NTT_ACCEL_OUTPUT_SHARE0 0x10u
#define NTT_ACCEL_OUTPUT_SHARE1 0x14u
#define NTT_ACCEL_CMD_START 0x01u
#define NTT_ACCEL_CMD_INVERSE 0x02u
#define NTT_ACCEL_CMD_ZEROIZE 0x04u
#define NTT_ACCEL_ST_BUSY (1u << 0)
#define NTT_ACCEL_ST_START_READY (1u << 1)
#define NTT_ACCEL_ST_INPUT_READY (1u << 2)
#define NTT_ACCEL_ST_OUTPUT_VALID (1u << 3)
#define NTT_ACCEL_ST_DONE (1u << 4)
#define NTT_ACCEL_ST_CORE_ERROR (1u << 5)
#define NTT_ACCEL_ST_INPUT_PENDING (1u << 6)
#define NTT_ACCEL_ST_OUTPUT_LAST (1u << 7)
#define NTT_ACCEL_ST_PROTOCOL_ERROR (1u << 8)

enum ntt_accel_result {
  NTT_ACCEL_OK = 0,
  NTT_ACCEL_TIMEOUT = -1,
  NTT_ACCEL_FAULT = -2,
  NTT_ACCEL_BAD_INPUT = -3
};

static inline void ntt_accel_write(uintptr_t base, size_t offset, uint32_t value) {
  *(volatile uint32_t *)(base + offset) = value;
}

static inline uint32_t ntt_accel_read(uintptr_t base, size_t offset) {
  return *(volatile uint32_t *)(base + offset);
}

static inline void ntt_accel_zeroize(uintptr_t base) {
  ntt_accel_write(base, NTT_ACCEL_CONTROL, NTT_ACCEL_CMD_ZEROIZE);
}

/* poll_limit bounds each wait, not the overall CPU time of the transform. */
static inline int ntt_accel_wait(uintptr_t base, uint32_t required,
                                 uint32_t poll_limit) {
  while (poll_limit != 0u) {
    uint32_t status = ntt_accel_read(base, NTT_ACCEL_STATUS);
    --poll_limit;
    if ((status & (NTT_ACCEL_ST_CORE_ERROR | NTT_ACCEL_ST_PROTOCOL_ERROR)) != 0u)
      return NTT_ACCEL_FAULT;
    if ((status & required) == required)
      return NTT_ACCEL_OK;
  }
  return NTT_ACCEL_TIMEOUT;
}

/* Single-owner blocking transform. After validating inputs, this begins with
 * ZEROIZE, so it intentionally discards any earlier operation. Validation errors
 * leave the peripheral untouched; later failures request ZEROIZE before return.
 * The caller must erase software buffers as required by its threat model.
 * Arrays have NTT_ACCEL_N entries; do not alias outputs with unread input arrays.
 * inverse=0 performs NTT; any nonzero inverse selects normalized inverse NTT. */
static inline int ntt_accel_transform_shares(
    uintptr_t base, const uint32_t in_share0[NTT_ACCEL_N],
    const uint32_t in_share1[NTT_ACCEL_N],
    uint32_t out_share0[NTT_ACCEL_N], uint32_t out_share1[NTT_ACCEL_N],
    int inverse, uint32_t poll_limit) {
  int result;
  size_t i;
  if (in_share0 == NULL || in_share1 == NULL ||
      out_share0 == NULL || out_share1 == NULL)
    return NTT_ACCEL_BAD_INPUT;
  for (i = 0; i < NTT_ACCEL_N; ++i) {
    if (in_share0[i] >= NTT_ACCEL_Q || in_share1[i] >= NTT_ACCEL_Q)
      return NTT_ACCEL_BAD_INPUT;
  }
  ntt_accel_zeroize(base);
  for (i = 0; i < NTT_ACCEL_N; ++i) {
    result = ntt_accel_wait(base, NTT_ACCEL_ST_INPUT_READY, poll_limit);
    if (result != NTT_ACCEL_OK) goto fail;
    ntt_accel_write(base, NTT_ACCEL_INPUT_SHARE0, in_share0[i]);
    ntt_accel_write(base, NTT_ACCEL_INPUT_SHARE1, in_share1[i]);
  }
  result = ntt_accel_wait(base, NTT_ACCEL_ST_START_READY, poll_limit);
  if (result != NTT_ACCEL_OK) goto fail;
  ntt_accel_write(base, NTT_ACCEL_CONTROL, NTT_ACCEL_CMD_START |
                  (inverse != 0 ? NTT_ACCEL_CMD_INVERSE : 0u));
  for (i = 0; i < NTT_ACCEL_N; ++i) {
    result = ntt_accel_wait(base, NTT_ACCEL_ST_OUTPUT_VALID, poll_limit);
    if (result != NTT_ACCEL_OK) goto fail;
    out_share0[i] = ntt_accel_read(base, NTT_ACCEL_OUTPUT_SHARE0);
    out_share1[i] = ntt_accel_read(base, NTT_ACCEL_OUTPUT_SHARE1);
  }
  /* Wait for post-output scrubbing, then inspect any final protocol fault. */
  result = ntt_accel_wait(base, NTT_ACCEL_ST_INPUT_READY, poll_limit);
  if (result == NTT_ACCEL_OK) return result;
fail:
  ntt_accel_zeroize(base);
  return result;
}

#endif /* MLDSA_NTT_ACCELERATOR_H */
