"""Check the actual ELF architecture, memory layout and measured stack frames."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
prefix = sys.argv[1] if len(sys.argv) > 1 else "riscv64-unknown-elf-"
elf = root / "build/ibex/mldsa44_demo.elf"

def run(tool, *args):
    return subprocess.check_output([prefix + tool, *map(str, args)], text=True)

header = run("readelf", "-h", elf)
assert "ELF32" in header and "RISC-V" in header
assert re.search(r"Entry point address:\s+0x100080", header)
assert not run("nm", "-u", elf).strip(), "unresolved symbols"
symbols = {}
for line in run("nm", "-n", elf).splitlines():
    parts = line.split()
    if len(parts) == 3:
        symbols[parts[2]] = int(parts[0], 16)
assert symbols["_vectors"] == 0x100000
assert symbols["_reset"] == 0x100080
assert symbols["__bss_end"] <= symbols["__stack_bottom"] < symbols["__stack_top"]
assert symbols["__stack_top"] % 16 == 0
assert symbols["__stack_top"] - symbols["__stack_bottom"] == 128 * 1024

frames = []
for source in (root / "build/ibex").rglob("*.su"):
    for line in source.read_text().splitlines():
        location, size, kind = line.split("\t")
        frames.append((int(size), location.rsplit(":", 1)[-1], kind))
print("PASS: ELF32 RISC-V, reset 0x00100080, no unresolved symbols, 128 KiB separate stack")
print(run("readelf", "-A", elf).strip())
print("Largest compiler-reported individual stack frames (not complete call chains):")
for size, name, kind in sorted(frames, reverse=True)[:8]:
    print(f"  {name}: {size} bytes ({kind})")
