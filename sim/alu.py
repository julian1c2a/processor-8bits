# MIT License — Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
"""
sim/alu.py — Modelo de referencia de la ALU de 8 bits.

Portado de testbenchs/alu_ref.py (sin generación de CSV).
Todas las funciones tienen la firma:  fn(a, b, cin) -> (acc: int, status: int)
    acc    in [0, 255]
    status = byte con bits  C H V Z G E R L  (bit7..bit0)
"""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def u8(x: int) -> int:
    """Trunca a 8 bits sin signo."""
    return x & 0xFF


def sign8(x: int) -> int:
    """Interpreta un entero como signed 8-bit (complemento a dos)."""
    x = u8(x)
    return x - 256 if x >= 128 else x


def bit(x: int, n: int) -> int:
    """Devuelve el bit n de x."""
    return (x >> n) & 1


def pack_status(C=0, H=0, V=0, Z=0, G=0, E=0, R=0, L=0) -> int:
    """Empaqueta flags en un byte: bit7=C … bit0=L."""
    return (C << 7) | (H << 6) | (V << 5) | (Z << 4) | (G << 3) | (E << 2) | (R << 1) | L


def common_GE(a: int, b: int) -> tuple:
    sa, sb = sign8(a), sign8(b)
    G = 1 if sa > sb else 0
    E = 1 if a == b else 0
    return G, E


def common_Z(acc: int) -> int:
    return 1 if u8(acc) == 0 else 0


# ---------------------------------------------------------------------------
# Operaciones de la ALU (misma semántica que ALU.vhdl)
# ---------------------------------------------------------------------------

def ref_NOP(a, b, cin):
    G, E = common_GE(a, b)
    return 0, pack_status(Z=common_Z(0), G=G, E=E)


def ref_ADD(a, b, cin):
    nh = (a & 0xF) + (b & 0xF)
    H = 1 if nh > 0xF else 0
    full = a + b
    C = 1 if full > 0xFF else 0
    acc = u8(full)
    V = 1 if bit(a, 7) == bit(b, 7) and bit(acc, 7) != bit(a, 7) else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, H=H, V=V, Z=common_Z(acc), G=G, E=E)


def ref_ADC(a, b, cin):
    nh = (a & 0xF) + (b & 0xF) + cin
    H = 1 if nh > 0xF else 0
    full = a + b + cin
    C = 1 if full > 0xFF else 0
    acc = u8(full)
    V = 1 if bit(a, 7) == bit(b, 7) and bit(acc, 7) != bit(a, 7) else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, H=H, V=V, Z=common_Z(acc), G=G, E=E)


def ref_SUB(a, b, cin):
    full9 = sign8(a) - sign8(b)
    acc = u8(full9)
    C = 0 if full9 < 0 else 1
    H = 1 if (a & 0xF) >= (b & 0xF) else 0
    V = 1 if bit(a, 7) != bit(b, 7) and bit(acc, 7) == bit(b, 7) else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, H=H, V=V, Z=common_Z(acc), G=G, E=E)


def ref_SBB(a, b, cin):
    full9 = sign8(a) - sign8(b) - cin
    acc = u8(full9)
    C = 0 if full9 < 0 else 1
    H = 1 if (a & 0xF) >= (b & 0xF) + cin else 0
    V = 1 if bit(a, 7) != bit(b, 7) and bit(acc, 7) == bit(b, 7) else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, H=H, V=V, Z=common_Z(acc), G=G, E=E)


def ref_LSL(a, b, cin):
    L = bit(a, 7)
    acc = u8(a << 1)
    G, E = common_GE(a, b)
    return acc, pack_status(Z=common_Z(acc), G=G, E=E, L=L)


def ref_LSR(a, b, cin):
    R = bit(a, 0)
    acc = u8(a >> 1)
    G, E = common_GE(a, b)
    return acc, pack_status(Z=common_Z(acc), G=G, E=E, R=R)


def ref_ROL(a, b, cin):
    C = bit(a, 7)               # outgoing bit → C flag
    acc = u8((a << 1) | cin)    # rotate left through carry
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, Z=common_Z(acc), G=G, E=E)


def ref_ROR(a, b, cin):
    C = bit(a, 0)                    # outgoing bit → C flag
    acc = u8((cin << 7) | (a >> 1)) # rotate right through carry
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, Z=common_Z(acc), G=G, E=E)


def ref_INC(a, b, cin):
    nh = (a & 0xF) + 1
    H = 1 if nh > 0xF else 0
    full9 = sign8(a) + 1
    acc = u8(full9)
    C = 1 if full9 < 0 else 0
    V = 1 if a == 0x7F else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, H=H, V=V, Z=common_Z(acc), G=G, E=E)


def ref_DEC(a, b, cin):
    nh = (a & 0xF) - 1
    H = 1 if nh >= 0 else 0
    full9 = sign8(a) - 1
    acc = u8(full9)
    C = 0 if full9 < 0 else 1
    V = 1 if a == 0x80 else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, H=H, V=V, Z=common_Z(acc), G=G, E=E)


def ref_AND(a, b, cin):
    acc = a & b
    G, E = common_GE(a, b)
    return acc, pack_status(Z=common_Z(acc), G=G, E=E)


def ref_IOR(a, b, cin):
    acc = a | b
    G, E = common_GE(a, b)
    return acc, pack_status(Z=common_Z(acc), G=G, E=E)


def ref_XOR(a, b, cin):
    acc = a ^ b
    G, E = common_GE(a, b)
    return acc, pack_status(Z=common_Z(acc), G=G, E=E)


def ref_NOT(a, b, cin):
    acc = u8(~a)
    G, E = common_GE(a, b)
    return acc, pack_status(Z=common_Z(acc), G=G, E=E)


def ref_ASL(a, b, cin):
    L = bit(a, 7)
    acc = u8(a << 1)
    V = 1 if bit(a, 7) != bit(acc, 7) else 0
    G, E = common_GE(a, b)
    return acc, pack_status(V=V, Z=common_Z(acc), G=G, E=E, L=L)


def ref_PSA(a, b, cin):
    G, E = common_GE(a, b)
    return a, pack_status(Z=common_Z(a), G=G, E=E)


def ref_PSB(a, b, cin):
    G, E = common_GE(a, b)
    return b, pack_status(Z=common_Z(b), G=G, E=E)


def ref_CLR(a, b, cin):
    G, E = common_GE(a, b)
    return 0, pack_status(Z=1, G=G, E=E)


def ref_SET(a, b, cin):
    G, E = common_GE(a, b)
    return 0xFF, pack_status(Z=0, G=G, E=E)


def ref_MUL(a, b, cin):
    full = a * b
    acc = u8(full & 0xFF)
    C = 1 if (full >> 8) != 0 else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, Z=common_Z(acc), G=G, E=E)


def ref_MUH(a, b, cin):
    full = a * b
    acc = u8((full >> 8) & 0xFF)
    C = 1 if acc != 0 else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, Z=common_Z(acc), G=G, E=E)


def ref_CMP(a, b, cin):
    H = 1 if (a & 0xF) >= (b & 0xF) else 0
    full9 = sign8(a) - sign8(b)
    sub = u8(full9)
    C = 0 if full9 < 0 else 1
    V = 1 if bit(a, 7) != bit(b, 7) and bit(sub, 7) == bit(b, 7) else 0
    G, E = common_GE(a, b)
    return 0, pack_status(C=C, H=H, V=V, Z=common_Z(sub), G=G, E=E)


def ref_ASR(a, b, cin):
    R = bit(a, 0)
    acc = u8((a & 0x80) | (a >> 1))
    G, E = common_GE(a, b)
    return acc, pack_status(Z=common_Z(acc), G=G, E=E, R=R)


def ref_SWP(a, b, cin):
    acc = u8(((a & 0x0F) << 4) | ((a & 0xF0) >> 4))
    G, E = common_GE(a, b)
    return acc, pack_status(Z=common_Z(acc), G=G, E=E)


def ref_NEG(a, b, cin):
    nibble_a = a & 0xF
    H = 0 if nibble_a > 0 else 1
    full9 = -sign8(a)
    acc = u8(full9)
    C = 0 if full9 < 0 else 1
    V = 1 if a == 0x80 else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, H=H, V=V, Z=common_Z(acc), G=G, E=E)


def ref_INB(a, b, cin):
    nh = (b & 0xF) + 1
    H = 1 if nh > 0xF else 0
    full9 = sign8(b) + 1
    acc = u8(full9)
    C = 1 if full9 < 0 else 0
    V = 1 if b == 0x7F else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, H=H, V=V, Z=common_Z(acc), G=G, E=E)


def ref_DEB(a, b, cin):
    nh = (b & 0xF) - 1
    H = 1 if nh >= 0 else 0
    full9 = sign8(b) - 1
    acc = u8(full9)
    C = 0 if full9 < 0 else 1
    V = 1 if b == 0x80 else 0
    G, E = common_GE(a, b)
    return acc, pack_status(C=C, H=H, V=V, Z=common_Z(acc), G=G, E=E)
