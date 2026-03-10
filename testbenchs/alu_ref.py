"""
alu_ref.py — Oráculo de referencia para la ALU de 8 bits.

Genera vectores de test exhaustivos en formato CSV para cada operación.
Los archivos se escriben en testbenchs/vectors/<OP>.csv con el formato:
    A,B,CIN,ACC,STATUS
donde STATUS = CHVZGELR (bit7..bit0 de RegStatus).

Uso:
    python alu_ref.py            -> genera todos los CSVs
    python alu_ref.py ADD SUB    -> genera solo los indicados
"""

import csv
import os
import sys

VECTORS_DIR = os.path.join(os.path.dirname(__file__), "vectors")

# ---------------------------------------------------------------------------
# Helpers de aritmética sin ambigüedad
# ---------------------------------------------------------------------------

def u8(x: int) -> int:
    """Trunca a 8 bits sin signo."""
    return x & 0xFF

def sign8(x: int) -> int:
    """Interpreta un entero como signed 8-bit (complemento a 2)."""
    x = u8(x)
    return x - 256 if x >= 128 else x

def bit(x: int, n: int) -> int:
    """Devuelve el bit n de x."""
    return (x >> n) & 1

def pack_status(C=0, H=0, V=0, Z=0, G=0, E=0, R=0, L=0) -> int:
    """Empaqueta los flags en un byte: bit7=C, bit6=H, ..., bit0=L."""
    return (C<<7)|(H<<6)|(V<<5)|(Z<<4)|(G<<3)|(E<<2)|(R<<1)|(L<<0)

def common_GE(a: int, b: int) -> tuple[int, int]:
    """Flags G y E basados en comparación signed."""
    sa, sb = sign8(a), sign8(b)
    G = 1 if sa > sb else 0
    E = 1 if a == b   else 0
    return G, E

def common_Z(acc: int) -> int:
    return 1 if u8(acc) == 0 else 0

# ---------------------------------------------------------------------------
# Modelos de referencia por operación
# (cada función devuelve (acc: int, status: int), con acc en [0,255])
# ---------------------------------------------------------------------------

def ref_NOP(a, b, cin):
    G, E = common_GE(a, b)
    Z = common_Z(0)
    return 0, pack_status(Z=Z, G=G, E=E)

def ref_ADD(a, b, cin):
    # Nibble half-carry
    nh = (a & 0xF) + (b & 0xF)
    H = 1 if nh > 0xF else 0
    # Full 9-bit add (unsigned)
    full = a + b
    C = 1 if full > 0xFF else 0
    acc = u8(full)
    # Overflow: signos iguales en entrada, diferente en resultado
    V = 1 if bit(a,7)==bit(b,7) and bit(acc,7)!=bit(a,7) else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_ADC(a, b, cin):
    nh = (a & 0xF) + (b & 0xF) + cin
    H = 1 if nh > 0xF else 0
    full = a + b + cin
    C = 1 if full > 0xFF else 0
    acc = u8(full)
    V = 1 if bit(a,7)==bit(b,7) and bit(acc,7)!=bit(a,7) else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_SUB(a, b, cin):
    nh = (a & 0xF) - (b & 0xF)
    H = 0 if nh < 0 else 1          # H=0 significa borrow en nibble
    full_s = sign8(a) - sign8(b)
    acc = u8(a - b)
    borrow = 1 if a < b else 0
    C = 0 if borrow else 1           # C=0 → hubo borrow (convención ALU)
    H = 1 if (a & 0xF) >= (b & 0xF) else 0
    # Overflow: signos distintos y resultado igual al signo de B
    V = 1 if bit(a,7)!=bit(b,7) and bit(acc,7)==bit(b,7) else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_SBB(a, b, cin):
    # a - b - cin (borrow)
    raw = a - b - cin
    acc = u8(raw)
    borrow = 1 if raw < 0 else 0
    C = 0 if borrow else 1
    nh = (a & 0xF) - (b & 0xF) - cin
    H = 1 if nh >= 0 else 0
    V = 1 if bit(a,7)!=bit(b,7) and bit(acc,7)==bit(b,7) else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_LSL(a, b, cin):
    L = bit(a, 7)
    acc = u8(a << 1)
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E, L=L)

def ref_LSR(a, b, cin):
    R = bit(a, 0)
    acc = u8(a >> 1)
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E, R=R)

def ref_ROL(a, b, cin):
    acc = u8((a << 1) | bit(a, 7))
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E)

def ref_ROR(a, b, cin):
    acc = u8((bit(a, 0) << 7) | (a >> 1))
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E)

def ref_INC(a, b, cin):
    nh = (a & 0xF) + 1
    H = 1 if nh > 0xF else 0
    full = a + 1
    C = 1 if full > 0xFF else 0
    acc = u8(full)
    V = 1 if a == 0x7F else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_DEC(a, b, cin):
    nh = (a & 0xF) - 1
    H = 1 if nh >= 0 else 0
    raw = a - 1
    borrow = 1 if raw < 0 else 0
    C = 0 if borrow else 1
    acc = u8(raw)
    V = 1 if a == 0x80 else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_AND(a, b, cin):
    acc = a & b
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E)

def ref_OR(a, b, cin):
    acc = a | b
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E)

def ref_XOR(a, b, cin):
    acc = a ^ b
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E)

def ref_NOT(a, b, cin):
    acc = u8(~a)
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E)

def ref_ASL(a, b, cin):
    L = bit(a, 7)
    acc = u8(a << 1)
    # Overflow si el bit de signo cambia
    V = 1 if bit(a, 7) != bit(acc, 7) else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(V=V, Z=Z, G=G, E=E, L=L)

def ref_PA(a, b, cin):
    G, E = common_GE(a, b)
    Z = common_Z(a)
    return a, pack_status(Z=Z, G=G, E=E)

def ref_PB(a, b, cin):
    G, E = common_GE(a, b)
    Z = common_Z(b)
    return b, pack_status(Z=Z, G=G, E=E)

def ref_CL(a, b, cin):
    G, E = common_GE(a, b)
    Z = 1  # siempre cero
    return 0, pack_status(Z=Z, G=G, E=E)

def ref_SET(a, b, cin):
    acc = 0xFF
    G, E = common_GE(a, b)
    Z = 0  # nunca cero
    return acc, pack_status(Z=Z, G=G, E=E)

def ref_MUL(a, b, cin):
    full = a * b
    acc = u8(full & 0xFF)
    C = 1 if (full >> 8) != 0 else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, Z=Z, G=G, E=E)

def ref_MUH(a, b, cin):
    full = a * b
    acc = u8((full >> 8) & 0xFF)
    C = 1 if acc != 0 else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, Z=Z, G=G, E=E)

def ref_CMP(a, b, cin):
    # ACC no se modifica (queda 0x00), pero flags reflejan a-b
    nh = (a & 0xF) - (b & 0xF)
    H = 1 if nh >= 0 else 0
    raw = sign8(a) - sign8(b)
    raw9 = a - b   # unsigned 9-bit
    borrow = 1 if raw9 < 0 else 0
    C = 0 if borrow else 1
    sub = u8(a - b)
    V = 1 if bit(a,7)!=bit(b,7) and bit(sub,7)==bit(b,7) else 0
    Z = 1 if sub == 0 else 0
    G, E = common_GE(a, b)
    # CMP no actualiza fG/fE con la lógica común — la ALU SÍ los calcula
    return 0, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_ASR(a, b, cin):
    R = bit(a, 0)
    acc = u8((a & 0x80) | (a >> 1))  # preserva signo
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E, R=R)

def ref_SWAP(a, b, cin):
    acc = u8(((a & 0x0F) << 4) | ((a & 0xF0) >> 4))
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E)

# ---------------------------------------------------------------------------
# Registro de operaciones: nombre → (opcode_5bit, función_ref, usa_cin)
# ---------------------------------------------------------------------------

OPERATIONS = {
    "NOP":  ("00000", ref_NOP,  False),
    "ADD":  ("00001", ref_ADD,  False),
    "ADC":  ("00010", ref_ADC,  True),
    "SUB":  ("00011", ref_SUB,  False),
    "SBB":  ("00100", ref_SBB,  True),
    "LSL":  ("00101", ref_LSL,  False),
    "LSR":  ("00110", ref_LSR,  False),
    "ROL":  ("00111", ref_ROL,  False),
    "ROR":  ("01000", ref_ROR,  False),
    "INC":  ("01001", ref_INC,  False),
    "DEC":  ("01010", ref_DEC,  False),
    "AND":  ("01011", ref_AND,  False),
    "OR":   ("01100", ref_OR,   False),
    "XOR":  ("01101", ref_XOR,  False),
    "NOT":  ("01110", ref_NOT,  False),
    "ASL":  ("01111", ref_ASL,  False),
    "PA":   ("10001", ref_PA,   False),
    "PB":   ("10010", ref_PB,   False),
    "CL":   ("10011", ref_CL,   False),
    "SET":  ("10100", ref_SET,  False),
    "MUL":  ("10101", ref_MUL,  False),
    "MUH":  ("10110", ref_MUH,  False),
    "CMP":  ("10111", ref_CMP,  False),
    "ASR":  ("11000", ref_ASR,  False),
    "SWAP": ("11001", ref_SWAP, False),
}

# ---------------------------------------------------------------------------
# Generador de CSV
# ---------------------------------------------------------------------------

def generate(op_name: str):
    opcode, ref_fn, uses_cin = OPERATIONS[op_name]
    os.makedirs(VECTORS_DIR, exist_ok=True)
    path = os.path.join(VECTORS_DIR, f"{op_name}.csv")
    count = 0
    cin_range = [0, 1] if uses_cin else [0]

    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["A", "B", "CIN", "OPCODE", "ACC", "STATUS"])
        for a in range(256):
            for b in range(256):
                for cin in cin_range:
                    acc, status = ref_fn(a, b, cin)
                    writer.writerow([a, b, cin, opcode, acc, status])
                    count += 1

    print(f"  [{op_name:>4}] {count:>7} vectores -> {path}")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    requested = sys.argv[1:] if len(sys.argv) > 1 else list(OPERATIONS.keys())
    unknown = [op for op in requested if op not in OPERATIONS]
    if unknown:
        print(f"ERROR: operaciones desconocidas: {unknown}")
        print(f"Disponibles: {list(OPERATIONS.keys())}")
        sys.exit(1)

    print(f"Generando vectores de test en: {VECTORS_DIR}")
    for op in requested:
        generate(op)
    print("Listo.")
