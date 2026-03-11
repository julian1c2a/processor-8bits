# MIT License
#
# Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
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
    # Espeja exactamente la ALU VHDL: resize(signed,9) - resize(signed,9)
    # C = not acc_ext(8)  donde acc_ext es la resta en signed 9-bit
    sa = sign8(a)  # signed 8-bit de A
    sb = sign8(b)  # signed 8-bit de B
    full9 = sa - sb          # resta en aritmética signed
    acc = u8(full9)
    # acc_ext(8) es el bit de signo del resultado de 9 bits signed
    # En Python: si full9 es negativo en 9 bits signed → bit8=1
    bit8 = 1 if (full9 < -128 or full9 > 127) and full9 < 0 else (1 if full9 < 0 else 0)
    # Más directamente: acc_ext(8) = MSB del resultado signed 9-bit
    # signed 9-bit rango: -256..255; bit8 = sign bit
    bit8 = 1 if full9 < 0 else 0
    C = 0 if bit8 else 1             # C = not acc_ext(8)
    H = 1 if (a & 0xF) >= (b & 0xF) else 0
    V = 1 if bit(a,7)!=bit(b,7) and bit(acc,7)==bit(b,7) else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_SBB(a, b, cin):
    # Espeja: resize(signed,9) - resize(signed,9) - signed(cin)
    sa = sign8(a)
    sb = sign8(b)
    full9 = sa - sb - cin
    acc = u8(full9)
    bit8 = 1 if full9 < 0 else 0
    C = 0 if bit8 else 1             # C = not acc_ext(8)
    H = 1 if (a & 0xF) >= (b & 0xF) + cin else 0
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
    # ALU VHDL: acc_ext = resize(signed(RegInA), 9) + 1
    # fC = acc_ext(8)  <- bit de signo del resultado signed 9-bit
    full9 = sign8(a) + 1   # aritmética signed 9-bit
    acc = u8(full9)
    # acc_ext(8) equivale al bit de signo del resultado en 9 bits signed
    C = 1 if full9 < 0 else 0
    V = 1 if a == 0x7F else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_DEC(a, b, cin):
    nh = (a & 0xF) - 1
    H = 1 if nh >= 0 else 0
    # ALU: acc_ext = resize(signed(RegInA),9) - 1  → fC = not acc_ext(8)
    full9 = sign8(a) - 1
    acc = u8(full9)
    bit8 = 1 if full9 < 0 else 0
    C = 0 if bit8 else 1             # C = not acc_ext(8)
    V = 1 if a == 0x80 else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_AND(a, b, cin):
    acc = a & b
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E)

def ref_IOR(a, b, cin):
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

def ref_PSA(a, b, cin):
    G, E = common_GE(a, b)
    Z = common_Z(a)
    return a, pack_status(Z=Z, G=G, E=E)

def ref_PSB(a, b, cin):
    G, E = common_GE(a, b)
    Z = common_Z(b)
    return b, pack_status(Z=Z, G=G, E=E)

def ref_CLR(a, b, cin):
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
    # Misma aritmética que SUB: resize(signed,9) - resize(signed,9)
    H = 1 if (a & 0xF) >= (b & 0xF) else 0
    sa, sb = sign8(a), sign8(b)
    full9 = sa - sb
    sub = u8(full9)
    bit8 = 1 if full9 < 0 else 0
    C = 0 if bit8 else 1
    V = 1 if bit(a,7)!=bit(b,7) and bit(sub,7)==bit(b,7) else 0
    Z = 1 if sub == 0 else 0
    G, E = common_GE(a, b)
    return 0, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_ASR(a, b, cin):
    R = bit(a, 0)
    acc = u8((a & 0x80) | (a >> 1))  # preserva signo
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E, R=R)

def ref_SWP(a, b, cin):
    acc = u8(((a & 0x0F) << 4) | ((a & 0xF0) >> 4))
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(Z=Z, G=G, E=E)

def ref_NEG(a, b, cin):
    # NEG: 0 - A  (complemento a dos)
    # Espeja VHDL: acc_ext = signed("000000000") - resize(signed(RegInA), 9)
    # Half-borrow del nibble: 0 - nibbleA (unsigned 5-bit)
    nibble_a = a & 0xF
    nibble_res_4 = 1 if nibble_a > 0 else 0   # borrow bit del nibble
    H = 0 if nibble_res_4 else 1               # fH = not nibble_res(4)
    # Resta principal 9 bits (signed extension)
    full9 = -sign8(a)                          # 0 - sign8(a)
    acc = u8(full9)
    bit8 = 1 if full9 < 0 else 0
    C = 0 if bit8 else 1                       # fC = not acc_ext(8); C=1 solo si A=0x00
    V = 1 if a == 0x80 else 0                  # overflow: -(-128) = +128 no cabe en signed 8-bit
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_INB(a, b, cin):
    # INB: ACC ← B+1  (misma aritmética que INC pero sobre B)
    nh = (b & 0xF) + 1
    H = 1 if nh > 0xF else 0
    full9 = sign8(b) + 1
    acc = u8(full9)
    C = 1 if full9 < 0 else 0                 # espeja VHDL: fC = acc_ext(8)
    V = 1 if b == 0x7F else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

def ref_DEB(a, b, cin):
    # DEB: ACC ← B-1  (misma aritmética que DEC pero sobre B)
    nh = (b & 0xF) - 1
    H = 1 if nh >= 0 else 0
    full9 = sign8(b) - 1
    acc = u8(full9)
    bit8 = 1 if full9 < 0 else 0
    C = 0 if bit8 else 1                      # fC = not acc_ext(8)
    V = 1 if b == 0x80 else 0
    G, E = common_GE(a, b)
    Z = common_Z(acc)
    return acc, pack_status(C=C, H=H, V=V, Z=Z, G=G, E=E)

# ---------------------------------------------------------------------------
# Registro de operaciones: nombre → (opcode_5bit, función_ref, usa_cin)
# ---------------------------------------------------------------------------

OPERATIONS = {
    "NOP":  (0b00000, ref_NOP,  False),
    "ADD":  (0b00001, ref_ADD,  False),
    "ADC":  (0b00010, ref_ADC,  True),
    "SUB":  (0b00011, ref_SUB,  False),
    "SBB":  (0b00100, ref_SBB,  True),
    "LSL":  (0b00101, ref_LSL,  False),
    "LSR":  (0b00110, ref_LSR,  False),
    "ROL":  (0b00111, ref_ROL,  False),
    "ROR":  (0b01000, ref_ROR,  False),
    "INC":  (0b01001, ref_INC,  False),
    "DEC":  (0b01010, ref_DEC,  False),
    "AND":  (0b01011, ref_AND,  False),
    "IOR":  (0b01100, ref_IOR,  False),
    "XOR":  (0b01101, ref_XOR,  False),
    "NOT":  (0b01110, ref_NOT,  False),
    "ASL":  (0b01111, ref_ASL,  False),
    "PSA":  (0b10001, ref_PSA,  False),
    "PSB":  (0b10010, ref_PSB,  False),
    "CLR":  (0b10011, ref_CLR,  False),
    "SET":  (0b10100, ref_SET,  False),
    "MUL":  (0b10101, ref_MUL,  False),
    "MUH":  (0b10110, ref_MUH,  False),
    "CMP":  (0b10111, ref_CMP,  False),
    "ASR":  (0b11000, ref_ASR,  False),
    "SWP":  (0b11001, ref_SWP,  False),
    "NEG":  (0b10000, ref_NEG,  False),
    "INB":  (0b11010, ref_INB,  False),
    "DEB":  (0b11011, ref_DEB,  False),
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
