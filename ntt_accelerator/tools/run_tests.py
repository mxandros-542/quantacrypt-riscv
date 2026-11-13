#!/usr/bin/env python3
"""Reproducible, fail-closed reference and real SystemVerilog regression."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
RTL = ['rtl/ntt_pkg.sv', 'rtl/ntt_modmul.sv', 'rtl/ntt_twiddle_rom.sv',
       'rtl/ntt_accelerator.sv', 'rtl/ntt_mmio.sv']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iverilog', default=os.environ.get('IVERILOG'))
    parser.add_argument('--vvp', default=os.environ.get('VVP'))
    parser.add_argument('--ivl-root', help='Icarus backend directory for a locally extracted package')
    parser.add_argument('--reference-only', action='store_true',
                        help='Run software tests only; report explicitly excludes RTL verification')
    parser.add_argument('--vcd', action='store_true', help='Dump core waveform (may be large)')
    args = parser.parse_args()
    os.chdir(ROOT)
    BUILD.mkdir(exist_ok=True)
    log_dir = BUILD / 'logs'
    log_dir.mkdir(exist_ok=True)
    report = {'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
              'scope': 'reference_only' if args.reference_only else 'rtl_regression',
              'status': 'RUNNING', 'checks': [], 'source_sha256': {}}
    for path in sorted(ROOT.rglob('*')):
        if path.is_file() and path.suffix in ('.sv', '.py', '.h', '.c') and 'build' not in path.parts and '__pycache__' not in path.parts:
            report['source_sha256'][path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()

    def run(name, command, timeout=180):
        print(f'Running {name}', flush=True)
        started = time.monotonic()
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=timeout)
        (log_dir / (name + '.log')).write_text(result.stdout, encoding='utf-8')
        report['checks'].append({'name': name, 'status': 'PASS' if result.returncode == 0 else 'FAIL',
                                 'seconds': round(time.monotonic()-started, 3), 'command': command,
                                 'log': 'build/logs/' + name + '.log'})
        print(result.stdout, end='' if result.stdout.endswith('\n') else '\n', flush=True)
        if result.returncode:
            raise RuntimeError(f'{name} exited with status {result.returncode}')
        return result.stdout

    try:
        run('generate_vectors', [sys.executable, 'tools/generate_vectors.py'])
        run('reference', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-v'])
        if args.reference_only:
            report['status'] = 'REFERENCE_ONLY_PASS'
            report['limitation'] = 'No HDL compiler or RTL simulator was run.'
            return 0
        local_base = BUILD / 'tools' / 'iverilog' / 'usr'
        iverilog = args.iverilog or shutil.which('iverilog')
        vvp = args.vvp or shutil.which('vvp')
        if not iverilog and (local_base / 'bin/iverilog').exists():
            iverilog = str(local_base / 'bin/iverilog')
            vvp = vvp or str(local_base / 'bin/vvp')
            if not args.ivl_root:
                backends = list((local_base / 'lib').rglob('ivl'))
                # Icarus internally invokes its backends through a shell and
                # does not quote -B correctly. Relative local paths avoid the
                # spaces in a project directory such as "minor project".
                args.ivl_root = next((p.parent.relative_to(ROOT).as_posix()
                                      for p in backends if p.is_file()), None)
        if not iverilog or not vvp:
            raise RuntimeError('Icarus Verilog and vvp are required. See README.md setup; software checks alone do not verify RTL.')
        backend_args = ['-B', args.ivl_root] if args.ivl_root else []
        run('iverilog_version', [iverilog] + backend_args + ['-V'])
        run('vvp_version', [vvp, '-V'])
        for top in ['tb_modmul', 'tb_ntt_accelerator', 'tb_mmio']:
            executable = 'build/' + top + '.vvp'
            command = [iverilog, '-g2012', '-Wall', '-Ibuild/vectors', '-s', top, '-o', executable]
            command += backend_args
            command += RTL + ['tb/' + top + '.sv']
            run('compile_' + top, command)
            output = run('simulate_' + top, [vvp, executable] +
                         (['+vcd'] if args.vcd and top == 'tb_ntt_accelerator' else []), timeout=300)
            if 'PASS ' + top not in output:
                raise RuntimeError(f'{top}: missing explicit success marker')
        verilator = shutil.which('verilator')
        if verilator:
            run('verilator_lint', [verilator, '--lint-only', '--top-module', 'ntt_mmio', '-Wall'] + RTL)
        else:
            report['checks'].append({'name': 'verilator_lint', 'status': 'NOT_RUN',
                                     'reason': 'Verilator is not installed.'})
        compiler = shutil.which('gcc') or shutil.which('clang')
        if compiler:
            smoke = BUILD / 'driver_compile.c'
            smoke.write_text('#include "ntt_accelerator.h"\nint main(void) { return 0; }\n', encoding='utf-8')
            run('driver_compile', [compiler, '-std=c11', '-Wall', '-Wextra', '-Werror', '-fsyntax-only',
                                   '-Isw', str(smoke)])
        else:
            report['checks'].append({'name': 'driver_compile', 'status': 'NOT_RUN',
                                     'reason': 'No native C compiler found.'})
        report['status'] = 'PASS'
        report['limitation'] = 'Functional RTL/control-trace verification, not synthesis, timing closure, physical leakage assessment, or full ML-DSA validation.'
        return 0
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        report['status'] = 'FAIL'
        report['error'] = str(exc)
        print('FAIL:', exc, file=sys.stderr)
        return 1
    finally:
        report['finished_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        name = 'reference_report.json' if args.reference_only else 'verification_report.json'
        (BUILD / name).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print('Report: build/' + name)


if __name__ == '__main__':
    raise SystemExit(main())
