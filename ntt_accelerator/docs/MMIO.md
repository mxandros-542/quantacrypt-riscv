# Generic MMIO interface

`rtl/ntt_mmio.sv` wraps the streaming accelerator with a synchronous 32-bit
register interface. It is a bus-neutral peripheral, not an Ibex, OBI, AXI, or
APB implementation. Add a SoC-specific bus adapter and address decoder before
connecting it to a processor. No physical base address is assumed.

Drive `req_i`, `write_i`, `addr_i`, `wdata_i`, and `wstrb_i` before a rising
clock edge. Every edge with `req_i=1` samples one request; `rsp_valid_o`,
`rdata_o`, and `error_o` provide its registered response immediately after that
edge. One request can be sampled each cycle. Holding `req_i` high repeats the
request each cycle. There is no response backpressure; the bus adapter must
always accept responses. Requests are not queued while the core is unavailable.

`addr_i` is a 12-bit byte offset. All accesses must be word aligned. Writes
require `wstrb_i=4'b1111`; read strobes are ignored. Invalid addresses, access
directions, partial writes, noncanonical input shares, and unavailable commands
return `error_o=1` and read data zero without advancing the core or losing a
staged coefficient. `error_o` is a response flag, distinct from the core fault.

| Offset | Name | Access | Meaning |
| --- | --- | --- | --- |
| `0x00` | CONTROL | W | Bit 0 START; bit 1 selects inverse for this START; bit 2 ZEROIZE. Bits 31:3 must be zero. At least START or ZEROIZE must be set. ZEROIZE dominates START. |
| `0x04` | STATUS | R | Status bits below. Reads have no clearing side effects. |
| `0x08` | INPUT_SHARE0 | W | Stage share 0 of the next coefficient. Requires input ready and no pending share. |
| `0x0c` | INPUT_SHARE1 | W | Commit the staged share 0 together with share 1. Requires input ready and a pending share. |
| `0x10` | OUTPUT_SHARE0 | R | Read current output share 0 and enable its share 1 read. Repeated reads return the same value. |
| `0x14` | OUTPUT_SHARE1 | R | Read current output share 1 and pop the pair. Requires a preceding successful share 0 read for this coefficient. |

Both input shares must be unsigned canonical field elements in
`0 .. 8380416`. Bits 31:23 are therefore zero. The wrapper rejects invalid
values before passing them to the core. A rejected share 1 write preserves the
staged share 0 for retry. A duplicate share 0 write is rejected and preserves
the original. Reading share 1 before share 0 is rejected without consuming any
output. Output shares are individually canonical and are not reconstructed by
this wrapper.

| STATUS bit | Meaning |
| --- | --- |
| 0 | Core busy |
| 1 | Core ready to accept START after exactly 256 coefficient pairs |
| 2 | Core ready to accept an input pair; also inspect bit 6 for wrapper staging |
| 3 | An output pair is valid |
| 4 | Sticky completion; cleared by accepted START, ZEROIZE, or reset |
| 5 | Core fault; recover with ZEROIZE or reset |
| 6 | Input share 0 is staged |
| 7 | Current valid output is the last coefficient |
| 8 | Sticky rejected-MMIO-request flag; cleared by ZEROIZE or reset |
| 31:9 | Zero |

## Transaction sequence

1. Wait for input ready after reset or ZEROIZE completes its 256-cycle scrub.
2. Write share 0 then share 1 for each of the 256 input coefficients in order.
3. Wait for START ready and write CONTROL `1` for forward or `3` for inverse.
4. Wait for output valid. Read share 0 then share 1 for all 256 coefficients.
5. The last share 1 read triggers automatic scrubbing. Wait for input ready
   before submitting the next polynomial.

ZEROIZE (`CONTROL=4`) is accepted during load, compute, output, scrubbing, and
fault states. It discards any staged input/output access state and clears sticky
wrapper status. A response already delivered before ZEROIZE cannot be recalled.
An invalid START returns an error; it does not interrupt the current transform.

`sw/ntt_accelerator.h` provides constants and a polling reference driver. Map
MMIO as uncached device memory with the ordering/barriers required by the SoC.
The register file has a single-owner protocol; serialize access across tasks,
interrupt handlers, cores, and DMA. Bus faults are handled by the SoC adapter
and CPU exception mechanism, not by the C header.

## Security boundary

This convenience interface serializes both shares through one ordinary bus,
one CPU, and one register response path. It is outside the protected boundary
of the separate-share streaming core. Separate register addresses do not protect
against transition leakage on shared wires/registers. The polling driver also
loads both shares in ordinary software and makes no constant-time or masking
claim. A protected signer requires an appropriate masked source/sink and
separate share paths, plus implementation-level leakage evaluation. See
[SECURITY.md](SECURITY.md).
