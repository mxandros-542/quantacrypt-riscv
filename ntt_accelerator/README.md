# ML-DSA NTT accelerator

SystemVerilog forward and inverse NTT for ML-DSA-44 polynomial arithmetic:
256 coefficients, modulus **8380417**, primitive 512th root **1753**. The
transform parameters are also used by ML-DSA-65 and ML-DSA-87. This component
processes one polynomial at a time; it does not implement an entire signer.

The RTL regression **passed with Icarus Verilog 12.0**. See
[verification results](docs/VERIFICATION.md) and the machine-readable
[run report](build/verification_report.json). FPGA synthesis, timing closure,
and physical side-channel measurements have not been performed.

## Included files

| File | Purpose |
| --- | --- |
| `rtl/ntt_accelerator.sv` | Streaming forward/inverse core, two separate arithmetic-share lanes |
| `rtl/ntt_modmul.sv` | Four-stage pipelined modular multiplier |
| `rtl/ntt_pkg.sv` | Canonical add/subtract and fixed-cost modular reduction |
| `rtl/ntt_twiddle_rom.sv` | Generated standard-domain FIPS twiddle constants |
| `rtl/ntt_mmio.sv` | Generic synchronous 32-bit register interface |
| `rtl/files.f` | Ordered synthesis source list |
| `tb/tb_modmul.sv` | Arithmetic, pipeline latency, bubbles, and clear tests |
| `tb/tb_ntt_accelerator.sv` | Complete transforms, individual shares, protocol, timing, scrub tests |
| `tb/tb_mmio.sv` | Register access, transform, and error-recovery tests |
| `tools/reference_model.py` | Butterfly models, independent evaluation/interpolation, schoolbook product |
| `tools/generate_vectors.py` | Reproducible vectors and ROM generator |
| `tools/run_tests.py` | Reference checks, real HDL compilation/simulation, logs and JSON report |
| `tests/reference_dilithium/` | Pinned upstream C arithmetic reference, license and provenance |
| `sw/ntt_accelerator.h` | MMIO constants and a bounded polling integration example |

## Run verification

On this Windows workspace, Icarus has already been extracted under
`build/tools/iverilog` and is used through WSL. In PowerShell:

```powershell
& 'C:\Users\Dell\Desktop\minor project\ntt_accelerator\verify.ps1'
```

On a fresh Debian/Ubuntu/WSL installation, the following downloads the official
distribution package locally without installing system packages or requiring
sudo. Package indexes and the package's runtime dependencies must be available.

```sh
cd ntt_accelerator
sh tools/setup_iverilog.sh
python3 tools/run_tests.py
```

Equivalently on Windows, use `verify.ps1 -Setup`. If Icarus and `vvp` are already
on PATH, setup is unnecessary. Python 3.9+ is required; Python dependencies are
standard-library only. GCC/Clang enables the compiled reference comparison and
C header check. Optional Verilator lint runs when Verilator is on PATH; lint
errors fail the regression. Executable overrides are `--iverilog`, `--vvp`,
and `--ivl-root`.

Logs, vectors, executables, and the report are written to `build/`. Any failed
check returns a nonzero exit code. `--reference-only` explicitly runs no HDL
simulation and writes a separate report. `--vcd` enables a potentially large
core waveform containing both shares; treat it as sensitive if using secrets.

## Numerical interface

Every input/output share is an unsigned 23-bit canonical value in
`0 .. 8380416`. For a shared coefficient, `a = (share0 + share1) mod q`.
Both lanes independently transform their input shares. For public functional
use, one may load `share0=a, share1=0`; this gives no masking benefit.

Forward NTT takes coefficients in natural order and returns values in the
FIPS bit-reversed odd-root order. Position `i` equals evaluation at
`1753^(2*BitRev8(i)+1) mod q`. The twiddle sequence is
`1753^BitRev8(k) mod q`, `k=1..255`, with butterfly lengths 128 down to 1.
The inverse uses the reverse negative-twiddle sequence, lengths 1 up to 128,
and multiplies by `256^-1 mod q = 8347681`.

**The interface uses standard residues, with no implicit Montgomery factor.**
Thus `INTT(NTT(a)) = a`, and `INTT(NTT(a) * NTT(b))` computes the negacyclic
product modulo `X^256+1` with ordinary modular pointwise multiplication.
The latter multiplication is exercised by the testbench but is not an
additional operation exposed by the accelerator.

The upstream Dilithium `ntt()` matches the hardware modulo q, but its
`invntt_tomont()` returns `R*INTT(a)`, where `R=2^32 mod q=4193792`.
Its Montgomery pointwise multiplication contributes `R^-1`. When retaining
that software pointwise operation and replacing `invntt_tomont`, multiply each
hardware inverse result by R modulo q, independently on each share if shared.
Alternatively use ordinary modular pointwise multiplication throughout.
Replacing only the forward NTT needs canonicalization but no Montgomery-scale
conversion. The tests check the upstream inverse after removing R with
`R^-1=8265825`.

## Streaming protocol and architecture

All handshakes are sampled at rising edges of `clk_i`. `rst_ni` is an
asynchronous active-low reset; deassert it synchronously in the surrounding
system. No clock-domain crossing is built in.

1. Reset enters a 256-cycle memory scrub; wait for `in_ready_o`.
2. Submit exactly 256 pairs with `in_valid_i && in_ready_o`. The source holds
   an offered pair stable until accepted. Load gaps are allowed.
3. Assert `start_i` with `start_ready_o`, and select `inverse_i` (0 forward,
   1 inverse). The mode is captured; later pin changes have no effect.
4. `busy_o` stays high throughout computation. `done_o` pulses once when the
   results become available; `out_valid_o` then stays high until drained.
5. Accept pairs with `out_valid_o && out_ready_i`. Output and `out_last_o`
   remain stable under backpressure. `out_last_o` marks coefficient 255.
6. Consumed locations are cleared. After the last output, another complete
   256-cycle scrub precedes the next input transaction.

Early START or input traffic outside its ready state is ignored by the core.
The MMIO wrapper returns an error for corresponding illegal bus operations.
An accepted noncanonical core input triggers a full scrub and a sticky fault;
reset or `zeroize_i` is required to recover. Range-error timing is outside the
valid-input constant-schedule contract. No partial result is exposed.

`zeroize_i` has priority over all operations, suppresses all streaming ready
and valid outputs, clears transient registers, and restarts the scrub. Keep
clocks running for all 256 scrub cycles after releasing reset/zeroize. Holding
zeroize high keeps restarting the scrub. `busy_o` includes scrubbing but is
low while waiting for input, START, or output consumption; use the ready/valid
signals to decide which transactions are legal.

One butterfly per lane uses READ, ISSUE, and four pipeline/wait clocks: six
clocks per butterfly, 1,024 butterflies per transform. The two share lanes run
simultaneously, using separate multiplier state and coefficient arrays.

| Operation | Measured computation clocks, accepted START to DONE |
| --- | ---: |
| Forward NTT | 6,144 |
| Inverse NTT, including 256 coefficient normalizations | 7,680 |
| Memory scrub | 256 |

Load/drain time, scrubbing, and bus stalls are additional. The arithmetic
multiplier itself accepts one input every clock, but this area-conscious
controller does not interleave butterflies to fill it. The design replaces
general division with three fixed shift/add folds using `2^23 = 8191 mod q`,
followed by one conditional subtraction. There is no synthesizable `%` or
variable-iteration reducer.

The source is portable RTL without vendor primitives. Memory inference,
resource use, and maximum frequency depend on the target: the current arrays
have two butterfly writes and asynchronous streaming output reads, so do not
assume BRAM inference. Use the source order in `rtl/files.f`, select the core
or MMIO top, add board-specific constraints, and review the inferred netlist.
A particular FPGA part, clock target, or resource/performance claim is not
assumed here.

## Ibex and security integration

[MMIO.md](docs/MMIO.md) documents every register and transaction. The wrapper
is a generic peripheral and still needs the selected Ibex SoC's bus adapter,
address decoder, reset/clock integration, and device-memory ordering.

The core includes fixed control/address schedules, separate share datapaths,
backpressure-safe output gating, and deterministic zeroization. Supply fresh,
uniform cryptographic masks through a protected producer and keep outputs
shared through a protected consumer. The convenience CPU/MMIO interface
serializes both shares and is **outside the masking boundary**.

See [SECURITY.md](docs/SECURITY.md) for assumptions and physical evaluation
requirements. Logical separation and passing simulations do not prove power,
EM, glitch, fault, or higher-order resistance. This is not a complete masked
ML-DSA signing implementation.

References: [FIPS 204, Algorithms 41–43](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.204.pdf),
[pinned Dilithium arithmetic](https://github.com/pq-crystals/dilithium/tree/d35ba3fe5449bee3e6d43e1f296c3ca818bd36be/ref).
The small vendored reference retains its own LICENSE and UPSTREAM.json.
