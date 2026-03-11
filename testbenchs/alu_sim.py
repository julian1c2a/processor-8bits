#!/usr/bin/env python3
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
alu_sim.py — Simulador interactivo de la ALU de 8 bits.

Actúa como si fuera la consola de una FPGA: le metes una operación, los
valores de los registros A y B (y opcionalmente Carry_in) y te devuelve
el valor del acumulador y del registro de estado con todos los flags.

La simulación es REAL: invoca al ejecutable GHDL compilado de ALU_run_tb,
que instancia el VHDL de la ALU y propaga las señales.

Uso:
    python testbenchs/alu_sim.py          # modo interactivo
    python testbenchs/alu_sim.py ADD 5 3  # modo no-interactivo (un solo cálculo)

Valores: decimal (255), hexadecimal (0xFF / 0XFF), binario (0b11111111)

Prerequisito:  make sim-compile  (o make sim, que compila y lanza)
"""

import os
import re
import subprocess
import sys

# En Windows, Python usa charmap (cp1252) por defecto y falla con
# caracteres Unicode de caja. Forzamos UTF-8 en stdout y stderr.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# ---------------------------------------------------------------------------
# Tabla de operaciones: nombre → (opcode_decimal, usa_carry_in)
# Opcodes según ALU_pkg.vhdl
# ---------------------------------------------------------------------------
OPERATIONS: dict[str, tuple[int, bool]] = {
    "NOP":  (0b00000,  False),  #  0
    "ADD":  (0b00001,  False),  #  1
    "ADC":  (0b00010,  True),   #  2  — usa Carry_in
    "SUB":  (0b00011,  False),  #  3
    "SBB":  (0b00100,  True),   #  4  — usa Carry_in
    "LSL":  (0b00101,  False),  #  5
    "LSR":  (0b00110,  False),  #  6
    "ROL":  (0b00111,  True),   #  7  — rota a través de Carry_in
    "ROR":  (0b01000,  True),   #  8  — rota a través de Carry_in
    "INC":  (0b01001,  False),  #  9
    "DEC":  (0b01010,  False),  # 10
    "AND":  (0b01011,  False),  # 11
    "IOR":  (0b01100,  False),  # 12
    "XOR":  (0b01101,  False),  # 13
    "NOT":  (0b01110,  False),  # 14
    "ASL":  (0b01111,  False),  # 15
    "PSA":  (0b10001,  False),  # 17
    "PSB":  (0b10010,  False),  # 18
    "CLR":  (0b10011,  False),  # 19
    "SET":  (0b10100,  False),  # 20
    "MUL":  (0b10101,  False),  # 21
    "MUH":  (0b10110,  False),  # 22
    "CMP":  (0b10111,  False),  # 23
    "ASR":  (0b11000,  False),  # 24
    "SWP":  (0b11001,  False),  # 25
}

# Operaciones que solo usan A (ignoran B)
UNARY_OPS = {"INC", "DEC", "NOT", "ASL", "ASR", "LSL", "LSR", "PSA", "CLR", "SET", "NOP"}
# Operaciones que solo usan B (ignoran A)
PASS_B_OPS = {"PSB"}

# ---------------------------------------------------------------------------
# Rutas
# ---------------------------------------------------------------------------
SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR    = os.path.dirname(SCRIPT_DIR)
BUILD_DIR   = os.path.join(ROOT_DIR, "build")
BUILD_TESTS = os.path.join(BUILD_DIR, "build_tests")
VECTORS_DIR = os.path.join(SCRIPT_DIR, "vectors")
TEMP_CSV    = os.path.join(VECTORS_DIR, "_sim_run.csv")

# El Makefile usa /ucrt64/bin/ghdl; buscamos el ejecutable compilado.
_ext    = ".exe" if (sys.platform == "win32" or os.name == "nt"
                     or "MSYSTEM" in os.environ) else ""
EXEC    = os.path.join(BUILD_TESTS, f"ALU_run_tb{_ext}")


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

def parse_int(s: str) -> int:
    """Acepta decimal, 0xHH, 0bBBBBBBBB."""
    s = s.strip()
    if s.startswith(("0x", "0X")):
        return int(s, 16)
    if s.startswith(("0b", "0B")):
        return int(s, 2)
    return int(s, 10)


def check_exec() -> None:
    if not os.path.isfile(EXEC):
        print(f"\n  ERROR: No se encuentra el ejecutable:")
        print(f"         {EXEC}")
        print(f"\n  Compila primero con:\n    make sim-compile\n  (o simplemente: make sim)\n")
        sys.exit(1)


def write_csv(a: int, b: int, cin: int, opcode: int) -> None:
    os.makedirs(VECTORS_DIR, exist_ok=True)
    with open(TEMP_CSV, "w") as f:
        f.write("A,B,CIN,OPCODE\n")
        f.write(f"{a},{b},{cin},{opcode}\n")


def run_ghdl() -> str:
    """Lanza el ejecutable GHDL y devuelve la salida combinada."""
    # GHDL escribe los report notes a stderr
    result = subprocess.run(
        [EXEC, f"-gVECTOR_FILE={TEMP_CSV}"],
        capture_output=True,
        text=True,
    )
    return result.stderr + result.stdout


def parse_result(output: str) -> dict | None:
    """Extrae los campos del report 'RESULT:...' generado por ALU_run_tb."""
    m = re.search(r"RESULT:\s*(.+)", output)
    if not m:
        return None
    line = m.group(1)

    def g(pattern: str) -> str:
        mm = re.search(pattern, line)
        return mm.group(1) if mm else "?"

    acc_hex = g(r"ACC=0x([0-9A-Fa-f]+)")
    acc_d   = g(r"ACC=0x[0-9A-Fa-f]+ \((\d+)d\)")
    acc_bin = g(r"ACC=0x[0-9A-Fa-f]+ \(\d+d\) bin=([01]+)")
    st_hex  = g(r"STATUS=0x([0-9A-Fa-f]+)")
    st_bin  = g(r"STATUS=0x[0-9A-Fa-f]+ bin=([01]+)")
    flags   = {
        "C": g(r"C=([01])"),
        "H": g(r"H=([01])"),
        "V": g(r"V=([01])"),
        "Z": g(r"Z=([01])"),
        "G": g(r"G=([01])"),
        "E": g(r"E=([01])"),
        "R": g(r"R=([01])"),
        "L": g(r"L=([01])"),
    }
    return {
        "acc_hex": acc_hex,
        "acc_d":   acc_d,
        "acc_bin": acc_bin,
        "st_hex":  st_hex,
        "st_bin":  st_bin,
        "flags":   flags,
    }


def display(op: str, a: int, b: int, cin: int, res: dict) -> None:
    """Imprime el resultado de forma legible."""
    opcode, uses_cin = OPERATIONS[op]
    sep = "  " + "─" * 46

    print()
    print(f"  ┌─ Operación: {op}  (opcode = {opcode:02d} = 0b{opcode:05b})")
    print(f"  │  A   = {a:3d}  (0x{a:02X}  {a:08b}b)")

    if op not in UNARY_OPS:
        print(f"  │  B   = {b:3d}  (0x{b:02X}  {b:08b}b)")

    if uses_cin:
        print(f"  │  Cin = {cin}")

    print(sep)

    acc_d = int(res["acc_d"]) if res["acc_d"].isdigit() else 0
    # Interpretación signed
    acc_s = acc_d if acc_d < 128 else acc_d - 256

    print(f"  │  ACC = {acc_d:3d}  (0x{res['acc_hex']}  {res['acc_bin']}b)  signed={acc_s:+d}")
    print(f"  │  STATUS = 0x{res['st_hex']}  {res['st_bin']}b")
    print(f"  │")
    f = res["flags"]
    print(f"  │  C={f['C']} (Carry/Borrow)        H={f['H']} (Half-carry)")
    print(f"  │  V={f['V']} (Overflow signed)      Z={f['Z']} (Zero)")
    print(f"  │  G={f['G']} (A > B  signed)        E={f['E']} (A == B)")
    print(f"  │  R={f['R']} (bit desplazado →)      L={f['L']} (bit desplazado ←)")
    print(f"  └" + "─" * 46)
    print()


def simulate(op: str, a: int, b: int, cin: int) -> None:
    opcode, _ = OPERATIONS[op]
    write_csv(a, b, cin, opcode)
    output = run_ghdl()
    res = parse_result(output)
    if res is None:
        print("\n  [ERROR] El simulador no produjo salida. Salida bruta:")
        print(output)
        return
    display(op, a, b, cin, res)


def print_help() -> None:
    ops = list(OPERATIONS.keys())
    cols = 8
    print()
    print("  Operaciones disponibles:")
    for i in range(0, len(ops), cols):
        print("    " + "  ".join(f"{o:<5}" for o in ops[i:i + cols]))
    print()
    print("  Sintaxis: <OP> <A> [B] [CIN]")
    print("  Valores : decimal (255) · hex (0xFF) · binario (0b11111111)")
    print("  Ejemplos:")
    print("    ADD 10 20          → suma A+B")
    print("    ADC 0xFF 0x01 1    → suma con carry (Cin=1)")
    print("    NOT 0b10110011     → complemento de A")
    print("    ROL 0x7F 0 1       → rota A a través de Cin=1")
    print("  Comandos: help · ops · q / exit")
    print()


# ---------------------------------------------------------------------------
# Punto de entrada
# ---------------------------------------------------------------------------

def main() -> None:
    check_exec()

    # Modo no-interactivo: argumentos en línea de comando
    if len(sys.argv) > 1:
        args = sys.argv[1:]
        op = args[0].upper()
        if op not in OPERATIONS:
            print(f"Operación desconocida: {op}")
            sys.exit(1)
        try:
            a   = parse_int(args[1]) if len(args) > 1 else 0
            b   = parse_int(args[2]) if len(args) > 2 else 0
            cin = parse_int(args[3]) if len(args) > 3 else 0
        except ValueError as e:
            print(f"Error de valor: {e}")
            sys.exit(1)
        simulate(op, a & 0xFF, b & 0xFF, cin & 1)
        return

    # Modo interactivo
    # En MSYS2/mintty con Python nativo de Windows, input() falla porque
    # mintty expone un pty POSIX y Python Win32 no lo reconoce como TTY.
    # La solución es ejecutar directamente desde el prompt con winpty:
    #   winpty python testbenchs/alu_sim.py
    print("=" * 50)
    print("  ALU 8-bit — Simulador VHDL interactivo")
    print("=" * 50)
    print_help()

    while True:
        try:
            line = input("ALU> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nSaliendo.")
            break

        if not line:
            continue

        cmd = line.split()[0].lower()
        if cmd in ("q", "quit", "exit", "salir"):
            break
        if cmd in ("help", "?", "ayuda"):
            print_help()
            continue
        if cmd == "ops":
            print("  " + "  ".join(OPERATIONS.keys()))
            continue

        parts = line.split()
        op = parts[0].upper()

        if op not in OPERATIONS:
            print(f"  Operación desconocida: '{op}'.  Escribe 'help' para ver la lista.")
            continue

        try:
            a   = parse_int(parts[1]) if len(parts) > 1 else 0
            b   = parse_int(parts[2]) if len(parts) > 2 else 0
            cin = parse_int(parts[3]) if len(parts) > 3 else 0
        except (ValueError, IndexError) as e:
            print(f"  Error de valor: {e}")
            continue

        if not (0 <= a <= 255) or not (0 <= b <= 255):
            print("  A y B deben ser valores de 8 bits: [0, 255]")
            continue

        simulate(op, a, b, cin & 1)


if __name__ == "__main__":
    main()
