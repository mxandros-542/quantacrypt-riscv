# Side-channel design and limits

The accelerator reduces identifiable RTL leakage risks. It is not a certified
side-channel-resistant implementation, and functional simulation cannot
establish power or electromagnetic leakage resistance.

## Protected computation boundary

The streaming core accepts two canonical arithmetic shares per coefficient:

`a[i] = (share0[i] + share1[i]) mod 8380417`.

NTT and normalized inverse NTT are linear over this field. Applying the same
transform independently to both shares therefore preserves this representation.
The core keeps the shares in separate memories and datapaths and returns them
separately. It does not reconstruct the polynomial internally. A caller can
select an unmasked functional mode by setting one share to zero, but that mode
has no masking protection.

For an ideal additive masking model, choose each share 0 coefficient uniformly
and independently from `0 .. q-1`, and compute share 1 as `a-share0 mod q`
within an appropriately protected source. Fresh masks are required across
independent operations. A cryptographic generator or suitable entropy source
must supply deployment masks. Rejection sampling of uniform 23-bit values
accepts values below `q`; reducing all 23-bit values modulo `q` introduces
bias. Generate masks before submitting an operation so mask-generation stalls
do not depend on secret data. The core neither supplies nor certifies randomness.
Reproducible testbench PRNGs and deterministic test masks are test stimuli only.

Separate logical lanes avoid deliberately time-multiplexing both shares through
the same arithmetic state. That structure is a mitigation, not a proof that
synthesis and placement preserve a valid physical leakage model. Public
twiddles, loop counters, addresses, and operation modes need not be masked.
Share recombination, raw-secret input masking, and unprotected consumers remain
outside this computation boundary.

## Timing and state lifecycle

The core schedules all butterflies and inverse normalization with public loop
counters. It does not skip zero coefficients or use coefficient-dependent
memory addresses. The arithmetic reduction has a bounded combinational path,
and the controller must never add data-dependent correction cycles. A public
forward/inverse selection may change the fixed operation latency.

Input and output transfers can stall according to the caller's ready/valid
handshake. The guarantee being checked is the fixed computation schedule after
an accepted START, not constant total time across different host traffic. No
claim is made that the ordinary C polling driver is constant time.

Reset, explicit ZEROIZE, error recovery, and completion cleanup clear internal
coefficient storage using a deterministic scrub. The core must suppress
coefficient outputs while they are unavailable, clear transient arithmetic
state, and finish scrubbing before accepting another polynomial. A scrub is a
digital erasure operation, not protection against invasive remanence or a way
to erase data already returned to the caller. External software buffers,
registers, caches, DMA storage, and debug traces require their own lifecycle.

## Generic MMIO is outside the masking boundary

The optional MMIO wrapper and C reference driver serialize both shares through
an ordinary shared CPU/bus/register path. Share values and transitions can leak
there even if the transform core has separate lanes. Different share addresses
alone do not fix this. Use separate protected share paths and an appropriate
masked producer/consumer for a side-channel-sensitive signing system.

The wrapper checks access order, canonical input ranges, bus alignment and
write strobes. Invalid requests report errors without silently overwriting or
consuming valid data. These checks improve interface correctness; they are not
fault-attack countermeasures.

## What verification can establish

Functional verification checks arithmetic correctness against independent
references, separate-share reconstruction, boundary coefficients, transform
ordering, inverse normalization, and polynomial multiplication behavior.
Protocol tests check output stability, invalid requests, reset/zeroization,
and recovery. Fixed schedule tests compare latency and public control behavior
for different coefficient values and sharings.

These tests do **not** establish statistical leakage bounds or demonstrate a
TVLA pass. Hamming-weight/toggle counts from RTL simulation, if measured, would
only be exploratory proxies and could miss analog glitches and coupling.

Before handling real signing secrets, evaluate the synthesized and placed
implementation: inspect whether tools merge share resources, inspect shared
clock/reset/control and routing coupling, disable secret debug access, and
measure power/EM traces on the target. Use an adequate fixed-versus-random
leakage assessment with justified sample sizes and targeted attacks, including
higher-order and transition leakage. A TVLA non-detection alone is not a
security proof. Mask quality, generator security, and repeated-operation mask
reuse must also be assessed in the complete system.

## Scope within ML-DSA

Multiplication by a public twiddle or public polynomial is linear and can be
performed independently on shares. Multiplication of two secret-shared
operands cannot be implemented by simply multiplying corresponding shares;
it requires a dedicated masked multiplication construction and randomness.

Protecting this NTT block does not protect all of ML-DSA signing. Sampling,
SHAKE, rejection sampling, decomposition, challenge handling, norm checks,
secret storage, control flow, and software integration need a consistent threat
model. No fault-injection resistance, full ML-DSA implementation certification,
or security-level certification is claimed for this component.
