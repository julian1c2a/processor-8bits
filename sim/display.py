# MIT License — Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
"""
sim/display.py — Funciones de visualización para el simulador ISA v0.7.

Usa colores ANSI si la salida es un TTY. En caso contrario, texto plano.
"""

from __future__ import annotations
import sys
from .cpu import CPU, StepResult, F_C, F_H, F_V, F_Z, F_G, F_E, F_R, F_L

# ---------------------------------------------------------------------------
# ANSI
# ---------------------------------------------------------------------------

USE_COLOR: bool = sys.stdout.isatty()

class _C:
    """Códigos ANSI. Se vacían si USE_COLOR es False."""
    RESET   = '\033[0m'
    BOLD    = '\033[1m'
    DIM     = '\033[2m'
    CYAN    = '\033[96m'
    YELLOW  = '\033[93m'
    GREEN   = '\033[92m'
    RED     = '\033[91m'
    MAGENTA = '\033[95m'
    BLUE    = '\033[94m'
    WHITE   = '\033[97m'

def _c(code: str) -> str:
    return code if USE_COLOR else ''

def _reset() -> str:
    return _c(_C.RESET)

def _bold(s: str) -> str:
    return f'{_c(_C.BOLD)}{s}{_reset()}'

def _cyan(s: str) -> str:
    return f'{_c(_C.CYAN)}{s}{_reset()}'

def _yellow(s: str) -> str:
    return f'{_c(_C.YELLOW)}{s}{_reset()}'

def _green(s: str) -> str:
    return f'{_c(_C.GREEN)}{s}{_reset()}'

def _red(s: str) -> str:
    return f'{_c(_C.RED)}{s}{_reset()}'

def _dim(s: str) -> str:
    return f'{_c(_C.DIM)}{s}{_reset()}'

def _magenta(s: str) -> str:
    return f'{_c(_C.MAGENTA)}{s}{_reset()}'


# ---------------------------------------------------------------------------
# Registro F en texto
# ---------------------------------------------------------------------------

FLAG_NAMES = ['C', 'H', 'V', 'Z', 'G', 'E', 'R', 'L']
FLAG_MASKS = [F_C, F_H, F_V, F_Z, F_G, F_E, F_R, F_L]

def flags_str(f: int) -> str:
    parts = []
    for name, mask in zip(FLAG_NAMES, FLAG_MASKS):
        bit = 1 if (f & mask) else 0
        s = f'{name}:{bit}'
        if bit:
            s = _bold(s)
        parts.append(s)
    return '  '.join(parts)


# ---------------------------------------------------------------------------
# show_regs
# ---------------------------------------------------------------------------

def show_regs(cpu: CPU, *, file=None):
    """Imprime una línea con todos los registros."""
    f = file or sys.stdout
    I_str = _bold('I:1') if cpu.I else _dim('I:0')
    line = (f'  A={_cyan(f"{cpu.A:#04x}")}  B={_cyan(f"{cpu.B:#04x}")} '
            f' PC={_cyan(f"{cpu.PC:#06x}")}  SP={_cyan(f"{cpu.SP:#06x}")} '
            f' LR={_cyan(f"{cpu.LR:#06x}")}  {I_str}\n'
            f'  F={_cyan(f"{cpu.F:#04x}")}  [ {flags_str(cpu.F)} ]')
    print(line, file=f)


# ---------------------------------------------------------------------------
# show_diff
# ---------------------------------------------------------------------------

def show_diff(result: StepResult, *, file=None, indent: str = '  '):
    """Muestra el resultado de un step: instrucción + cambios."""
    f = file or sys.stdout

    # Línea de instrucción
    hex_bytes = ' '.join(f'{b:02x}' for b in result.raw_bytes)
    mnem_w = 28
    instr_part = _bold(result.mnemonic[:mnem_w].ljust(mnem_w))
    byte_part  = _dim(f'[{hex_bytes}]') if hex_bytes else _dim('[]')
    cyc_part   = _dim(f'{result.cycles}c')
    print(f'{indent}{instr_part}  {byte_part}  {cyc_part}', file=f)

    # Cambios en registros
    for name, (old, new) in result.reg_diff.items():
        if name == 'F':
            old_s = f'{old:#04x} [{_flags_inline(old)}]'
            new_s = f'{new:#04x} [{_flags_inline(new)}]'
        elif name == 'I':
            old_s = '1' if old else '0'
            new_s = '1' if new else '0'
        elif name in ('PC', 'SP', 'LR'):
            old_s = f'{old:#06x}'
            new_s = f'{new:#06x}'
        else:
            old_s = f'{old:#04x}'
            new_s = f'{new:#04x}'
        arrow = _dim('→')
        print(f'{indent}  {_yellow(name):<4} : {_dim(old_s)} {arrow} {_cyan(new_s)}', file=f)

    # Cambios en memoria
    for addr, old, new in result.mem_diff:
        old_s = f'{old:#04x}'
        new_s = f'{new:#04x}'
        arrow = _dim('→')
        tag   = _dim(f'mem[{addr:#06x}]')
        print(f'{indent}  {tag} : {_dim(old_s)} {arrow} {_yellow(new_s)}', file=f)

    # Cambios en E/S
    for port, old, new in result.io_diff:
        old_s = f'{old:#04x}'
        new_s = f'{new:#04x}'
        arrow = _dim('→')
        tag   = _dim(f'io[{port:#04x}]')
        print(f'{indent}  {tag}  : {_dim(old_s)} {arrow} {_yellow(new_s)}', file=f)

    # Estado HALT
    if result.halted:
        print(f'{indent}  {_red("⏸  HALT — CPU detenida. Esperando NMI / IRQ.")}', file=f)


def _flags_inline(f: int) -> str:
    return ''.join(n if (f & m) else '.' for n, m in zip(FLAG_NAMES, FLAG_MASKS))


# ---------------------------------------------------------------------------
# show_mem  — volcado xxd-style
# ---------------------------------------------------------------------------

def show_mem(cpu: CPU, addr: int, count: int = 128, *, file=None):
    f = file or sys.stdout
    addr &= 0xFFFF
    count = max(1, min(count, 65536))
    rows = (count + 15) // 16
    for row in range(rows):
        base = (addr + row * 16) & 0xFFFF
        raw  = [cpu.mem[(base + i) & 0xFFFF] for i in range(16)]
        used = min(16, count - row * 16)
        hex_part = ' '.join(f'{raw[i]:02x}' if i < used else '  '
                            for i in range(16))
        asc_part = ''.join(chr(raw[i]) if 0x20 <= raw[i] < 0x7F else '.'
                           for i in range(used))
        line = (f'  {_dim(f"{base:#06x}")}  {hex_part}  {_dim("|")}'
                f'{asc_part}{_dim("|")}')
        print(line, file=f)


# ---------------------------------------------------------------------------
# show_io  — tabla de puertos de E/S
# ---------------------------------------------------------------------------

def show_io(cpu: CPU, start: int = 0, count: int = 16, *, file=None):
    f = file or sys.stdout
    start &= 0xFF
    count  = max(1, min(count, 256))
    for row in range((count + 15) // 16):
        base = start + row * 16
        if base > 0xFF:
            break
        vals = [cpu.io[(base + i) & 0xFF] for i in range(min(16, count - row*16))]
        hex_p = ' '.join(f'{v:02x}' for v in vals)
        tag   = _dim(f'IO[{base:#04x}]')
        print(f'  {tag}  {hex_p}', file=f)


# ---------------------------------------------------------------------------
# show_listing  — tabla de programa
# ---------------------------------------------------------------------------

def show_listing(lines: list, *, file=None, highlight_pc: int | None = None):
    """Imprime el listing de un programa (lista de AsmLine)."""
    f = file or sys.stdout
    header = (f'  {"Nº":>3}  {"Addr":>6}  {"Bytes":<14}  Mnemónico')
    sep    = '  ' + '─' * (len(header) - 2)
    print(_dim(sep), file=f)
    print(_dim(header), file=f)
    print(_dim(sep), file=f)
    for i, al in enumerate(lines, 1):
        if al.size == 0 and not al.label and not al.error:
            continue
        hex_b = ' '.join(f'{b:02x}' for b in al.encoded[:6])
        if len(al.encoded) > 6:
            hex_b += '…'
        addr_s = f'{al.addr:#06x}'
        lbl    = f'{al.label}: ' if al.label else ''
        mnem   = lbl + al.mnemonic
        arrow  = ' ← PC' if al.addr == highlight_pc else ''
        err    = f'  {_red("ERR: " + al.error)}' if al.error else ''
        num_s  = f'{i:>3}'
        if al.addr == highlight_pc:
            print(f'  {_bold(_cyan(num_s))}  {_cyan(addr_s)}  {hex_b:<14}  '
                  f'{_bold(mnem)}{_cyan(arrow)}{err}', file=f)
        else:
            print(f'  {_dim(num_s)}  {_dim(addr_s)}  {hex_b:<14}  {mnem}{err}', file=f)
    print(_dim(sep), file=f)


# ---------------------------------------------------------------------------
# show_step_trace  — traza compacta para modo run
# ---------------------------------------------------------------------------

def show_step_trace(result: StepResult, *, file=None):
    """Muestra una línea de traza de ejecución."""
    f = file or sys.stdout
    pc_s    = _dim(f'[{result.pc_before:#06x}]')
    mnem_s  = _bold(result.mnemonic[:28].ljust(28))
    cyc_s   = _dim(f'({result.cycles}c)')

    changes = []
    for name, (old, new) in result.reg_diff.items():
        if name == 'F':
            changes.append(f'F:{_flags_inline(old)}→{_flags_inline(new)}')
        elif name in ('PC', 'SP', 'LR'):
            changes.append(f'{name}:{old:#06x}→{_cyan(f"{new:#06x}")}')
        elif name == 'I':
            changes.append(f'I:{old}→{_cyan(str(new))}')
        else:
            changes.append(f'{name}:{old:#04x}→{_cyan(f"{new:#04x}")}')

    for addr, old, new in result.mem_diff:
        changes.append(f'M[{addr:#06x}]:{old:#04x}→{_yellow(f"{new:#04x}")}')
    for port, old, new in result.io_diff:
        changes.append(f'IO[{port:#04x}]:{old:#04x}→{_yellow(f"{new:#04x}")}')

    change_s = '   ' + '  '.join(changes) if changes else ''
    halt_s   = f'  {_red("⏸ HALT")}' if result.halted else ''
    print(f'{pc_s} {mnem_s}  {cyc_s}{change_s}{halt_s}', file=f)
