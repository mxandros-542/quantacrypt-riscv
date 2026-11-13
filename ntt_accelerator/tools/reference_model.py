"""ML-DSA field arithmetic and independent NTT oracles (Python standard library).

FIPS 204, sections 2.5 and 7.5, Algorithms 41/42. The public API uses
canonical residues, not the extra Montgomery factor of invntt_tomont.
This is a verification model; its execution time is not secret independent.
"""

Q = 8380417
N = 256
ROOT = 1753
INV_N = 8347681
MONT_R = 4193792
MONT_R_INV = 8265825


def bitrev8(value):
    """Reverse all eight bits of a byte."""
    if not 0 <= value < N:
        raise ValueError("bitrev8 requires a byte")
    return int(f"{value:08b}"[::-1], 2)


ZETAS = tuple(pow(ROOT, bitrev8(k), Q) for k in range(N))
POINTS = tuple(pow(ROOT, 2 * bitrev8(k) + 1, Q) for k in range(N))


def canonical(values):
    """Validate length and canonicalize signed or unsigned coefficients."""
    a = [int(value) % Q for value in values]
    if len(a) != N:
        raise ValueError(f"expected {N} coefficients, got {len(a)}")
    return a


def ntt(values):
    """FIPS forward transform: natural coefficients to bit-reversed roots."""
    a = canonical(values)
    k = 0
    length = N // 2
    while length:
        for start in range(0, N, 2 * length):
            k += 1
            zeta = ZETAS[k]
            for j in range(start, start + length):
                u = a[j]
                t = zeta * a[j + length] % Q
                a[j] = (u + t) % Q
                a[j + length] = (u - t) % Q
        length //= 2
    return a


def intt(values):
    """FIPS inverse transform, including 256^-1 and no Montgomery factor."""
    a = canonical(values)
    k = N
    length = 1
    while length < N:
        for start in range(0, N, 2 * length):
            k -= 1
            zeta = -ZETAS[k]
            for j in range(start, start + length):
                u, v = a[j], a[j + length]
                a[j] = (u + v) % Q
                a[j + length] = zeta * (u - v) % Q
        length *= 2
    return [value * INV_N % Q for value in a]


def ntt_direct(values):
    """Independent O(N^2) Horner evaluation at the 256 odd roots."""
    a = canonical(values)
    result = []
    for point in POINTS:
        value = 0
        for coefficient in reversed(a):
            value = (value * point + coefficient) % Q
        result.append(value)
    return result


def intt_direct(values):
    """Independent inverse interpolation by root orthogonality.

    a[j] = N^-1 sum_k A[k] * point[k]^-j. No butterfly schedule or
    forward-transform routine is shared with this oracle.
    """
    transformed = canonical(values)
    result = [0] * N
    for value, point in zip(transformed, POINTS):
        inverse = pow(point, Q - 2, Q)
        power = 1
        for j in range(N):
            result[j] = (result[j] + value * power) % Q
            power = power * inverse % Q
    return [value * INV_N % Q for value in result]


def negacyclic_schoolbook(left, right):
    """Independent multiplication in Z_q[X]/(X^256+1)."""
    a, b = canonical(left), canonical(right)
    result = [0] * N
    for i, ai in enumerate(a):
        for j, bj in enumerate(b):
            degree = i + j
            if degree >= N:
                result[degree - N] -= ai * bj
            else:
                result[degree] += ai * bj
    return [value % Q for value in result]


def negacyclic_ntt(left, right):
    """Transform-domain product, for comparison with schoolbook."""
    return intt([a * b % Q for a, b in zip(ntt(left), ntt(right))])


def reduce_product_folds(value):
    """Integer model of the fixed three-fold hardware reduction."""
    if not 0 <= value < (1 << 46):
        raise ValueError("reducer input must be an unsigned 46-bit integer")
    for _ in range(3):
        value = (value & ((1 << 23) - 1)) + 8191 * (value >> 23)
    return value - Q if value >= Q else value
