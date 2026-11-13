"""Independent mathematical, pinned C reference, and vector integrity tests."""
import ctypes
import hashlib
import json
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys
import unittest

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'tools'))
from reference_model import (N, Q, ROOT, INV_N, MONT_R, MONT_R_INV, ZETAS,
    POINTS, ntt, intt, ntt_direct, intt_direct, negacyclic_schoolbook,
    negacyclic_ntt, reduce_product_folds)
from generate_vectors import input_cases, rom_source


class ReferenceTests(unittest.TestCase):
    def test_field_and_roots(self):
        self.assertEqual(pow(ROOT, 256, Q), Q-1)
        self.assertEqual(pow(ROOT, 512, Q), 1)
        self.assertEqual(len(set(POINTS)), 256)
        self.assertEqual(N*INV_N % Q, 1)
        self.assertEqual(MONT_R*MONT_R_INV % Q, 1)

    def test_forward_against_independent_evaluation(self):
        for name, values in input_cases():
            with self.subTest(name=name):
                self.assertEqual(ntt(values), ntt_direct(values))

    def test_inverse_against_independent_interpolation(self):
        for name, values in input_cases():
            with self.subTest(name=name):
                self.assertEqual(intt(values), intt_direct(values))

    def test_round_trips(self):
        rng = random.Random(44123)
        for _ in range(40):
            values = [rng.randrange(Q) for _ in range(N)]
            self.assertEqual(intt(ntt(values)), values)
            self.assertEqual(ntt(intt(values)), values)

    def test_negacyclic_multiplication(self):
        rng = random.Random(44098)
        for _ in range(10):
            a = [rng.randrange(Q) for _ in range(N)]
            b = [rng.randrange(Q) for _ in range(N)]
            self.assertEqual(negacyclic_ntt(a, b), negacyclic_schoolbook(a, b))
        a, b = [0]*N, [0]*N
        a[255], b[1] = 1, 1
        self.assertEqual(negacyclic_ntt(a, b), [Q-1]+[0]*255)

    def test_arithmetic_sharing_linearity(self):
        rng = random.Random(44011)
        for transform in (ntt, intt):
            for _ in range(10):
                plain = [rng.randrange(Q) for _ in range(N)]
                mask = [rng.randrange(Q) for _ in range(N)]
                other = [(x-r) % Q for x, r in zip(plain, mask)]
                joined = [(a+b) % Q for a,b in zip(transform(mask), transform(other))]
                self.assertEqual(joined, transform(plain))

    def test_three_fold_reducer(self):
        rng = random.Random(44888)
        values = [0, 1, Q-1, Q, Q+1, (Q-1)**2, (1<<46)-1]
        for exponent in range(1, 46):
            values.extend([(1<<exponent)-1, 1<<exponent, (1<<exponent)+1])
        values.extend(rng.randrange(1<<46) for _ in range(100000))
        for value in values:
            self.assertEqual(reduce_product_folds(value), value % Q)
        # Conservative fold bounds establish the final single subtract suffices.
        bound = (1<<46)-1
        for width in (36, 27, 24):
            bound = ((1<<23)-1) + 8191*(bound >> 23)
            self.assertLess(bound, 1<<width)
        self.assertLess(bound, 2*Q)

    def test_pinned_dilithium_twiddles(self):
        source = (PROJECT/'tests/reference_dilithium/ntt.c').read_text()
        table_text = re.search(r'zetas\[N\]\s*=\s*\{(.*?)\}', source, re.S).group(1)
        table = [int(x) for x in re.findall(r'-?\d+', table_text)]
        self.assertEqual(len(table), N)
        self.assertEqual([z*MONT_R_INV % Q for z in table[1:]], list(ZETAS[1:]))

    def test_checked_in_rom(self):
        self.assertEqual((PROJECT/'rtl/ntt_twiddle_rom.sv').read_text(), rom_source())

    def test_generated_vector_integrity(self):
        directory = PROJECT/'build/vectors'
        manifest = json.loads((directory/'manifest.json').read_text())
        self.assertEqual(manifest['num_cases'], 24)
        for filename, digest in manifest['sha256'].items():
            # Normalize platform line endings exactly as generator source strings.
            text = (directory/filename).read_text()
            self.assertEqual(hashlib.sha256(text.encode('ascii')).hexdigest(), digest)
        self.assertEqual(len((directory/'input.memh').read_text().splitlines()), 24*N)
        self.assertEqual(len((directory/'expected.memh').read_text().splitlines()), 24*N)

    def test_bad_length_rejected(self):
        for transform in (ntt, intt, ntt_direct, intt_direct):
            with self.assertRaises(ValueError):
                transform([0]*255)


class PinnedCReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which('gcc') or shutil.which('clang')
        if not compiler:
            raise unittest.SkipTest('Native C compiler unavailable; pinned table test still runs.')
        directory = PROJECT/'build/reference'
        directory.mkdir(parents=True, exist_ok=True)
        library = directory/('dilithium_ref.dll' if sys.platform == 'win32' else 'dilithium_ref.so')
        source = PROJECT/'tests/reference_dilithium'
        command = [compiler, '-shared', '-fPIC', '-O2', '-std=c99', '-DDILITHIUM_MODE=2',
                   str(source/'ntt.c'), str(source/'reduce.c'), '-o', str(library)]
        subprocess.run(command, check=True, capture_output=True, text=True)
        cls.library = ctypes.CDLL(str(library))
        cls.forward = cls.library.pqcrystals_dilithium2_ref_ntt
        cls.inverse = cls.library.pqcrystals_dilithium2_ref_invntt_tomont
        for function in (cls.forward, cls.inverse):
            function.argtypes = [ctypes.POINTER(ctypes.c_int32)]
            function.restype = None

    def test_compiled_pinned_c_forward_and_inverse(self):
        rng = random.Random(44567)
        cases = input_cases() + [('random_'+str(i), [rng.randrange(Q) for _ in range(N)]) for i in range(20)]
        for name, values in cases:
            with self.subTest(name=name):
                a = (ctypes.c_int32*N)(*values)
                self.forward(a)
                self.assertEqual([x % Q for x in a], ntt(values))
                b = (ctypes.c_int32*N)(*values)
                self.inverse(b)
                self.assertEqual([x*MONT_R_INV % Q for x in b], intt(values))


if __name__ == '__main__':
    unittest.main()
