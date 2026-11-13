# Verification record

The completed regression in `build/verification_report.json` reports **PASS**.
It was executed in the user's WSL terminal using Icarus Verilog 12.0 and GCC;
the saved machine-readable report and logs were inspected after completion.
The report records exact commands, source hashes, and timestamps.

| Check | Observed result |
| --- | --- |
| Python mathematical/reference suite | 12 tests passed, no skips in the WSL run |
| Pinned upstream C implementation | Compiled and compared on 32 input polynomials, both forward and inverse; Montgomery inverse scale accounted for |
| Independent vector oracles | 24 cases from direct Horner evaluation/inverse interpolation |
| Pipelined multiplier | 17,123 checked results, including bubbles and clear cancellation |
| Modular arithmetic | 20,142 combined add/subtract/full-46-bit reduction checks in SV |
| Python reducer model | 100,000 seeded random 46-bit inputs plus boundaries; conservative fold-width bounds checked |
| Complete core | 33 transforms passed with both individual shares and reconstructed outputs checked |
| Constant schedule | Identical controller/index traces across all compared cases of each mode; forward 6,144 clocks, inverse 7,680 clocks |
| Core protocol | Load gaps, output backpressure, early/repeated START, ignored busy traffic, latched mode, done pulse, output count/last flag |
| Erasure/recovery | Partial-load abort, compute abort/reset, stalled-output zeroize, invalid values in both shares, memory and transient/pipeline register clearing |
| Polynomial composition | Real RTL forward→pointwise multiplication→inverse checks `X^255*X=-1`; nontrivial RTL forward/inverse round trip |
| MMIO | 14,514 checked responses, forward/inverse results, back-to-back requests, alignment/strobe/range/access-order errors, reset/zeroize |
| C polling header | GCC C11 syntax check passed with `-Wall -Wextra -Werror` |

The vector families include zero, one, q-1, impulses at 0/1/255, ramp,
alternating extremes, eta=2 signed coefficients mapped modulo q, and three
seeded uniform polynomials. Both transform directions are tested for each.
The core tests also check fresh re-sharing and zero-second-share functional use.

The reference suite compares the butterfly model with independent O(N^2)
evaluation/interpolation, and compares polynomial multiplication with O(N^2)
negacyclic schoolbook multiplication. A round trip alone could hide matching
ordering/scaling errors, so it is not the only oracle.

## Log locations

- `build/logs/reference.log`
- `build/logs/compile_tb_modmul.log` and `simulate_tb_modmul.log`
- `build/logs/compile_tb_ntt_accelerator.log` and `simulate_tb_ntt_accelerator.log`
- `build/logs/compile_tb_mmio.log` and `simulate_tb_mmio.log`
- `build/logs/driver_compile.log`

The MMIO compilation log contains Icarus's `constant selects in always_* ...
all bits will be included` notices. These indicate a conservative expansion
of simulation sensitivity; compilation and simulation passed. The arithmetic
and core compilation logs are empty. Do not interpret this as a clean run of
a separate static-lint or synthesis tool.

## Not established by this run

Verilator lint is explicitly **NOT_RUN** because it is not installed.
No synthesis, place-and-route, timing closure, resource report, post-layout
simulation, FPGA measurement, TVLA, power/EM attack testing, fault-injection
testing, formal proof, complete Ibex SoC integration, or full ML-DSA
keygen/sign/verify validation was performed. No throughput in MHz or security
certification is claimed. See SECURITY.md for the physical masking boundary.

Re-run `python3 tools/run_tests.py` after RTL changes. A missing simulator or a
failed test produces a failing exit code; reference-only runs produce a
separate report clearly excluding RTL verification.
