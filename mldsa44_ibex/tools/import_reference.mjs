// Import the pinned public-domain reference without OS RNG or x86 benchmarks.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const upstream = process.argv[2];
if (!upstream) throw new Error('Usage: node tools/import_reference.mjs UPSTREAM_CHECKOUT');
const revision = 'd35ba3fe5449bee3e6d43e1f296c3ca818bd36be';
const actualRevision = execFileSync('git', ['-c', 'safe.directory=' + path.resolve(upstream).replaceAll('\\', '/'),
  '-C', upstream, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
if (actualRevision !== revision) throw new Error('Expected upstream commit ' + revision);
const files = ['config.h', 'params.h', 'fips202.c', 'fips202.h', 'ntt.c', 'ntt.h',
  'packing.c', 'packing.h', 'poly.c', 'poly.h', 'polyvec.c', 'polyvec.h',
  'reduce.c', 'reduce.h', 'rounding.c', 'rounding.h', 'symmetric.h', 'symmetric-shake.c'];
const vendor = path.join(root, 'vendor', 'dilithium');
fs.mkdirSync(vendor, { recursive: true });
fs.mkdirSync(path.join(root, 'src'), { recursive: true });
const hashes = {};
for (const name of files) {
  const content = fs.readFileSync(path.join(upstream, 'ref', name), 'utf8').replace(/\r\n/g, '\n');
  fs.writeFileSync(path.join(vendor, name), content);
  hashes[name] = crypto.createHash('sha256').update(content).digest('hex');
}
for (const name of ['LICENSE', 'AUTHORS.md']) {
  fs.writeFileSync(path.join(vendor, name), fs.readFileSync(path.join(upstream, name), 'utf8').replace(/\r\n/g, '\n'));
}
const sign = fs.readFileSync(path.join(upstream, 'ref', 'sign.c'), 'utf8').replace(/\r\n/g, '\n');
function extract(name) {
  const match = sign.match(new RegExp('^int ' + name + '\\([\\s\\S]*?^}', 'm'));
  if (!match) throw new Error('Missing upstream function ' + name);
  return match[0];
}
let keygen = extract('crypto_sign_keypair')
  .replace('int crypto_sign_keypair(uint8_t *pk, uint8_t *sk)',
    'int mldsa44_core_keypair_from_seed(uint8_t *pk, uint8_t *sk, const uint8_t seed[32])')
  .replace('randombytes(seedbuf, SEEDBYTES);',
    'for (unsigned int i = 0; i < SEEDBYTES; ++i)\n    seedbuf[i] = seed[i];');
let signing = extract('crypto_sign_signature_internal')
  .replace('crypto_sign_signature_internal', 'mldsa44_core_sign')
  .replace('rej:\n', 'rej:\n  /* Prevent reuse when L*nonce would wrap its 16-bit sampling nonce. */\n  if (nonce >= 16384) {\n    volatile uint8_t *out = sig;\n    for (size_t i = 0; i < CRYPTO_BYTES; ++i) out[i] = 0;\n    *siglen = 0;\n    return -2;\n  }\n');
const verifying = extract('crypto_sign_verify_internal')
  .replace('crypto_sign_verify_internal', 'mldsa44_core_verify');
if (keygen.includes('randombytes') || !signing.includes('nonce >= 16384')) throw new Error('Import adaptation failed');
const header = `/* Derived from pq-crystals/dilithium ref/sign.c, commit ${revision}.
 * Upstream license: CC0/public domain (see vendor/dilithium/LICENSE).
 * Adaptations: explicit key seed; only internal detached-signature routines;
 * reject before mask nonce reuse. Arithmetic and encodings are unchanged.
 */
#include <stdint.h>
#include "sign_core.h"
#include "packing.h"
#include "polyvec.h"
#include "poly.h"
#include "symmetric.h"
#include "fips202.h"

`;
fs.writeFileSync(path.join(root, 'src', 'sign_core.c'), header + keygen + '\n\n' + signing + '\n\n' + verifying + '\n');
fs.writeFileSync(path.join(vendor, 'UPSTREAM.json'), JSON.stringify({
  repository: 'https://github.com/pq-crystals/dilithium', commit: revision,
  licenseChoice: 'CC0 / public domain', normalizedTextSHA256: hashes,
  adaptedSignSourceSHA256: crypto.createHash('sha256').update(sign).digest('hex')
}, null, 2) + '\n');
console.log('Imported reference C and generated src/sign_core.c');
