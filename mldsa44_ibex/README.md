# ML-DSA-44 software implementation for Ibex

Complete portable C implementation of **pure ML-DSA-44**, with key generation,
detached signing, verification, context strings, and both deterministic and
hedged signing. All NTT, inverse NTT, polynomial arithmetic, SHAKE128, and
SHAKE256 calculations run in software.

This is a reference-based software baseline for the Ibex/NTT minor project.
The arithmetic comes from the official [pq-crystals/dilithium reference](https://github.com/pq-crystals/dilithium/tree/d35ba3fe5449bee3e6d43e1f296c3ca818bd36be/ref),
pinned to commit `d35ba3fe5449bee3e6d43e1f296c3ca818bd36be`.
It matches the included NIST ML-DSA-44 vectors, including final-standard key
expansion and context handling. Upstream's internal `dilithium2` symbol names
are retained; the public API is named `mldsa44_*`.

**Start reading:** `examples/demo.c`, `include/mldsa44.h`, then
`docs/CODE_WALKTHROUGH.md` and `src/sign_core.c`.

## What is included

| File or directory | Purpose |
| --- | --- |
| `include/mldsa44.h` | Public firmware API, buffer sizes, return codes |
| `src/mldsa44.c` | Input checks, ordinary ML-DSA context prefix, API wrappers |
| `src/sign_core.c` | Full key generation, signing loop, and verification |
| `vendor/dilithium/` | Pinned reference NTT, arithmetic, packing, SHAKE, licenses |
| `examples/demo.c` | Runnable keygen/sign/verify/tampering demonstration |
| `examples/platform.c` | Host output or Ibex MMIO output and cycle counters |
| `platform/ibex/` | Bare-metal startup, linker script, minimal runtime |
| `tests/` | Native tests, independent polynomial multiplication, NIST vectors |
| `build/ibex/mldsa44_demo.elf` | Prebuilt RV32IMC + Zicsr application |
| `build/ibex/mldsa44_demo.bin` | Raw load image; use the ELF with Simple System |
| `docs/VALIDATION.md` | Actual test coverage, build results, limitations |

The C library has no OS calls, dynamic allocation, OpenSSL dependency, or hidden
global random generator. The Ibex executable links without a hosted C library;
the cross-compiler's `libgcc` supplies any compiler arithmetic helpers.

## Run the host demo and tests

Use Linux or WSL Ubuntu. From this package directory:

```sh
make -j2 test
make acvp
make sanitize
```

Requirements: GCC or a compatible C11 compiler, GNU Make, and Python 3 for ACVP
tests. No Python packages are needed. `make sanitize` additionally needs GCC's
address/undefined-behavior sanitizer runtime.

On this computer, the package is available in WSL at:

```sh
cd "/mnt/c/Users/Dell/Desktop/minor project/mldsa44_ibex"
make test
```

Successful demonstration output includes:

```text
PASS: key generation
PASS: signing
PASS: valid signature accepted
PASS: modified message rejected
PASS: modified signature rejected
ALL TESTS PASSED
```

The demo deliberately uses a fixed seed and fixed signing randomness, labeled
**DEMO ONLY** in both the code and output. This makes results reproducible for
simulation. Supply cryptographically secure randomness for real keys.

## Build for Ibex

The default compiler name is `riscv32-unknown-elf-gcc`:

```sh
make -j2 ibex
```

Ubuntu's multilib `riscv64-unknown-elf-gcc` also builds the required **32-bit**
image because the Makefile explicitly selects `-march=rv32imc_zicsr -mabi=ilp32`:

```sh
make -j2 ibex check-elf RV_CC=riscv64-unknown-elf-gcc
```

On this computer the host and RISC-V compilers were installed in WSL Ubuntu and
the second command was tested. This does not install or build the Ibex RTL simulator.

Build outputs are `build/ibex/mldsa44_demo.elf`, `.bin`, `.map`, and compiler
stack-usage reports (`.su` files in the object directories).

## Run on your existing Ibex Simple System simulator

Use a Simple System configuration supporting **RV32IMC and machine CSRs**, such
as the project's `small` configuration. Set the package path as appropriate for
the machine holding your Ibex checkout.

From the root of your existing Ibex repository:

```sh
MLDSA_DIR="/mnt/c/Users/Dell/Desktop/minor project/mldsa44_ibex"

./build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system \
  "--meminit=ram,$MLDSA_DIR/build/ibex/mldsa44_demo.elf"
```

Read `ibex_simple_system.log` for the demo messages. Completion writes the
Simple System halt register. Confirm **ALL TESTS PASSED**; a simulator process
exit alone does not establish that the application passed its tests.

If your Ibex version produces a differently named simulator executable, use its
actual path with the same ELF loading option. For initial cryptographic runs,
omit waveform tracing because it can produce large traces.

The executable follows the [documented Ibex Simple System memory map](https://github.com/lowRISC/ibex/blob/master/examples/simple_system/README.md):

| Item | Address / setting |
| --- | --- |
| Instruction/data RAM base | `0x00100000` |
| Default RAM size | 1 MiB |
| Vector base | `0x00100000` |
| Reset entry | `0x00100080` |
| ASCII output register | `0x00020000` |
| Simulation halt register | `0x00020008` |
| Reserved stack | 128 KiB at the top of RAM |

This platform layer is specific to **Simple System**. For an Ibex Demo System
or a custom FPGA SoC, adapt the linker memory regions, reset/startup, output,
and completion behavior to that system's map. The cryptographic C API is reusable.

### Stack and memory

Do not use the original example's 32 KiB stack unchanged. This build's signing
function alone has a **50,720-byte stack frame**, before nested function calls.
The included linker reserves 128 KiB separately from the program and globals
and asserts that the two regions cannot overlap.

For a smaller Simple System RAM configuration, set the real size explicitly:

```sh
make ibex RV_CC=riscv64-unknown-elf-gcc \
  LDFLAGS='-Wl,--defsym=IBEX_RAM_BYTES=0x40000'
```

Changing only a Make variable does not force an existing ELF to relink. Run
`make clean` before rebuilding with different compiler, architecture, or memory
options. Keep the simulator RAM size consistent with the linker configuration.

The binary assumes the simulator loads the ELF directly into RAM. A system
booting from flash/ROM also needs its own initialized-data copy routine.

## Public API

Sizes are 1312 bytes for the public key, 2560 bytes for the expanded private key,
2420 bytes for a detached signature, and 32 bytes for a key seed or signing
randomness. Contexts may contain 0 through 255 bytes, including binary data.

```c
mldsa44_keypair_from_seed(pk, sk, seed);

mldsa44_sign(signature, &signature_len,
             message, message_len, context, context_len, rnd, sk);

mldsa44_sign_deterministic(signature, &signature_len,
                           message, message_len, context, context_len, sk);

mldsa44_verify(signature, signature_len,
               message, message_len, context, context_len, pk);
```

Use the complete, runnable example for declarations and error handling. Each
function returns zero on success. Verification returns `-1` for an invalid
signature. Signing returns `-1` for invalid arguments or `-2` if the attempt
limit is reached; output signature length is zero on error. The attempt cap
prevents repetition of the 16-bit mask sampling nonce.

Provide a fresh cryptographically random key seed for real key generation.
For hedged signing, provide 32 fresh random bytes. Deterministic signing uses
the FIPS 204 all-zero `rnd` convention, while deriving its masks from the
secret key and message. It still requires securely generated keys.

The API accepts message bytes and creates the ordinary ML-DSA domain/context
prefix itself. Do not add that prefix to the message yourself. **HashML-DSA,
arbitrary prehash inputs, and an external-mu API are not implemented.**

The caller allocates fixed-size key and output buffers; buffer sizes and
non-overlap are caller obligations described in the header. Private keys are
trusted inputs. `mldsa44_clear` clears caller buffers, not all internal stack
frames. This educational reference port has not received a production
side-channel/security audit or a formal NIST validation certificate.

## Cycle measurements and later accelerator work

On Ibex, the demo prints hexadecimal 64-bit `mcycle` differences for keygen,
sign, and successful verify. Output is outside the measured intervals. The
counter helper uses high/low/high reads so an RV32 counter rollover is handled.
The measurements include function-call and counter-read overhead; they do not
include entropy acquisition. A single demo run is a functional baseline, not
a statistical benchmark. Signing latency varies with rejection attempts.

For the later hardware comparison, keep the same message, public key, CPU
configuration, clock, and compiler options. Compare software NTT already in
this implementation with the accelerator, including the accelerator's data
transfer and control costs.

The most relevant replacement points are `poly_ntt`, `poly_invntt_tomont`, and
`poly_pointwise_montgomery` in `vendor/dilithium/poly.c`. Preserve coefficient
ordering, allowed ranges, and Montgomery factors. An ordinary mathematical
inverse is not a direct replacement for `invntt_tomont` without adjusting its
scaling contract.

## Provenance and licensing

The vendored arithmetic is unchanged apart from line-ending normalization.
`vendor/dilithium/UPSTREAM.json` records its commit and file hashes. The derived
`src/sign_core.c` replaces OS randomness in keygen with an explicit seed, keeps
the internal detached signing/verification routines, and guards nonce exhaustion.
The importer can reproduce this adaptation from the pinned checkout.

The wrapper, demonstration, and platform code use the MIT license. The upstream
reference offers CC0/public-domain terms, retained in `vendor/dilithium/LICENSE`
with its author information. NIST vector provenance and the exact selected
commit are recorded in `tests/vectors/SOURCES.json`.
