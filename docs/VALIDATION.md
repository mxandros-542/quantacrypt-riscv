# Validation results

Performed on 2 November 2026 in WSL Ubuntu on the development computer.

## Executed checks

| Check | Result |
| --- | --- |
| Native keygen/sign/verify demonstration | Passed |
| Deterministic signature reproducibility | Passed |
| Supplied-randomness signing and verification | Passed |
| Empty through 4096-byte messages | Passed |
| Empty through 255-byte contexts; context binding | Passed |
| Modified messages, signatures, and public keys | Rejected as expected |
| Incorrect lengths, excessive hints, invalid API arguments | Rejected as expected |
| 12 NTT products versus independent negacyclic multiplication | Passed |
| AddressSanitizer + UndefinedBehaviorSanitizer | Passed |
| RISC-V cross-compile and link | Passed |
| ELF architecture, entry, symbols, RAM/stack separation | Passed |

Commands were `make test`, `make acvp`, `make sanitize`, and
`make ibex check-elf RV_CC=riscv64-unknown-elf-gcc`.

## Independent NIST known-answer tests

All 115 cases in the selected supported interfaces passed:

| NIST case type | Cases |
| --- | ---: |
| Key generation: complete public and private key byte comparison | 25 |
| External pure ML-DSA signing: deterministic and supplied randomness | 30 |
| Internal message-interface signing | 30 |
| External pure ML-DSA verification | 15 |
| Internal message-interface verification | 15 |

Signature outputs were compared byte-for-byte with NIST's expected outputs,
and verification outcomes were compared against NIST's expected booleans.
The generated signatures were also verified.

The downloaded ML-DSA-44 corpus includes 90 additional cases for prehash and
external-mu interfaces. The test runner explicitly skips those cases because
those interfaces are outside this package's API; they are not counted as passes.

Vectors come from NIST's public ACVP-Server repository at commit
`975de31eb83d87039ec88934fdc47d8c312b892d`. See `tests/vectors/SOURCES.json`.
Machine-readable results are in `build/validation_acvp.json`.

## RV32 artifact

The tested compiler was `riscv64-unknown-elf-gcc` 14.2.0 using
`-march=rv32imc_zicsr -mabi=ilp32 -Os`.

The resulting ELF is ELF32 RISC-V, has entry `0x00100080`, and has no unresolved
symbols. ELF code and data load segments are separate; both occupy the Simple
System's instruction/data RAM.

| Section accounting | Bytes |
| --- | ---: |
| Text/constant data reported by `size` | 16,089 |
| Initialized writable data | 52 |
| Zero-initialized data | 6,364 |
| Reserved stack, additional to the above | 131,072 |

Largest compiler-reported individual frames:

| Function | Bytes |
| --- | ---: |
| `mldsa44_core_sign` | 50,720 |
| `mldsa44_core_keypair_from_seed` | 37,120 |
| `mldsa44_core_verify` | 34,992 |

Individual frames are not complete call-chain high-water measurements.
Compiler flags and versions can change these sizes.

## What remains to validate on the target

The ELF has **not been executed in an Ibex RTL simulator or on an FPGA** in this
workspace. No Ibex cycle-count or hardware-performance result is claimed.
Load it into the user's existing Simple System simulator and confirm the
`ALL TESTS PASSED` log message before collecting cycle measurements.

Native sanitizer testing does not establish target-side side-channel resistance,
fault resistance, complete stack scrubbing, or a NIST validation certificate.
This is a tested reference port for study and a software performance baseline.
