# MIT License — Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
"""
sim/cli.py — Interfaz de línea de comandos del simulador ISA v0.7.

Modos:
  REPL    prompt "(asm) > "    — ensambla+ejecuta una instrucción a la vez.
  Program prompt "(prog NNNN) >> " — acumula instrucciones y las ejecuta.

Comandos comunes:
  <instrucción>               Ensambla y ejecuta (REPL) / acumula (prog)
  regs                        Muestra registros
  mem <addr> [n]              Volcado de memoria
  io [start] [n]              Tabla de puertos E/S
  set <reg> <valor>           Fuerza valor en registro
  write <addr> <b0> [b1..]    Escribe bytes en memoria
  reset                       Soft reset (conserva memoria)
  clrmem                      Hard reset (borra memoria)
  load <archivo.bin>          Carga binario en memoria desde start_addr
  save <archivo.bin>          Guarda rango de memoria a archivo
  irq                         Solicita señal IRQ
  nmi                         Solicita señal NMI
  program [addr]              Entra en modo programa (org=addr o PC actual)
  help                        Ayuda
  quit / exit / q             Salir

Comandos exclusivos de modo programa:
  <instrucción>               Añade instrucción al buffer
  <etiqueta>:                 Añade etiqueta
  .org <addr>                 Cambia la dirección de ensamblado
  .byte v1[,v2...]            Emite bytes literales
  .word v1[,v2...]            Emite words literales
  list                        Lista el buffer ensamblado
  run                         Enlaza y ejecuta todo el programa
  step                        Ejecuta una sola instrucción (requiere run previo)
  back                        Vuelve al modo REPL
  delete [n]                  Elimina la última (o n-ésima) línea del buffer
  rewind                      Vuelve al inicio del programa (PC = org)
"""

from __future__ import annotations
import sys
import os

try:
    import readline
    _HAS_READLINE = True
except ImportError:
    _HAS_READLINE = False

from .cpu        import CPU
from .assembler  import Assembler
from .display    import (show_regs, show_diff, show_mem, show_io,
                          show_listing, show_step_trace, _bold, _red,
                          _cyan, _dim, _green, _yellow)

# ---------------------------------------------------------------------------
# Ayuda
# ---------------------------------------------------------------------------

_HELP_REPL = """\
Modo REPL — instrucciones ejecutadas al instante
  <instrucción>         Ej: LD A, #0x42 ; ADD ; BEQ -4
  regs                  Muestra registros
  mem <addr> [n]        Volcado de memoria (n bytes, def=64)
  io  [start] [n]       Tabla de puertos E/S (def start=0, n=16)
  set <reg> <val>       Fuerza un registro  (A B PC SP F LR I)
  write <addr> <b...>   Escribe bytes en memoria
  reset                 Soft reset (registros; conserva mem)
  clrmem                Hard reset (registros + memoria)
  load <file> [addr]    Carga binario en memoria (def addr=PC)
  save <file> <a> <n>   Guarda n bytes desde addr a fichero
  irq / nmi             Señal de interrupción
  program [addr]        Entra en modo programa (org=addr)
  help   h   ?          Esta ayuda
  quit   q   exit       Salir
"""

_HELP_PROG = """\
Modo Programa — construye y ejecuta un programa completo
  <instrucción>         Añade instrucción al buffer
  <etiqueta>:           Añade etiqueta
  .org <addr>           Cambia base de ensamblado
  .byte v1[,v2...]      Emite bytes literales
  .word v1[,v2...]      Emite words literales
  list   ls             Lista el buffer (con dir. y bytes)
  run                   Enlaza y ejecuta — traza todas las instrucciones
  step                  Ejecuta una instrucción (después de cargar/run)
  rewind                Reinicia PC al .org del programa
  delete [n]            Elimina última línea (o la n-ésima)
  back   b              Vuelve al modo REPL
  regs  mem  io  set  write  reset  clrmem  load  save  irq  nmi
  help  quit
"""

# ---------------------------------------------------------------------------
# CLI principal
# ---------------------------------------------------------------------------

class CLI:
    def __init__(self):
        self.cpu     = CPU()
        self.asm     = Assembler()
        self._in_prog_mode = False
        self._prog_org     = 0x0000
        self._loaded       = False     # True después de run/load

    # ------------------------------------------------------------------
    # Entry point
    # ------------------------------------------------------------------

    def run(self):
        print(_bold('\nSimulador ISA v0.7  —  procesador de 8 bits'))
        print(_dim("Escribe 'help' para ver los comandos disponibles.\n"))
        while True:
            try:
                prompt = self._prompt()
                line   = input(prompt).strip()
            except (EOFError, KeyboardInterrupt):
                print('\nSaliendo.')
                break

            if not line:
                continue
            try:
                if not self._dispatch(line):
                    break
            except Exception as exc:
                print(_red(f'Error interno: {exc}'))

    # ------------------------------------------------------------------
    # Prompt
    # ------------------------------------------------------------------

    def _prompt(self) -> str:
        if self._in_prog_mode:
            pc_s = f'{self.asm.pc:#06x}'
            return f'(prog {pc_s}) >> '
        return '(asm) > '

    # ------------------------------------------------------------------
    # Dispatch
    # ------------------------------------------------------------------

    def _dispatch(self, line: str) -> bool:
        """Devuelve False para salir del bucle principal."""
        cmd, *rest = line.split(None, 1)
        arg  = rest[0] if rest else ''
        cmdU = cmd.upper()

        # --- Comandos que funcionan en ambos modos ---
        if cmdU in ('QUIT', 'EXIT', 'Q'):
            print('Saliendo.')
            return False

        if cmdU in ('HELP', 'H', '?'):
            print(_HELP_PROG if self._in_prog_mode else _HELP_REPL)
            return True

        if cmdU == 'REGS':
            show_regs(self.cpu); return True

        if cmdU == 'MEM':
            self._cmd_mem(arg); return True

        if cmdU == 'IO':
            self._cmd_io(arg); return True

        if cmdU == 'SET':
            self._cmd_set(arg); return True

        if cmdU == 'WRITE':
            self._cmd_write(arg); return True

        if cmdU == 'RESET':
            self.cpu.soft_reset()
            print(_green('Soft reset — registros reiniciados (memoria conservada)'))
            return True

        if cmdU == 'CLRMEM':
            self.cpu.hard_reset()
            print(_green('Hard reset — registros y memoria borrados'))
            return True

        if cmdU == 'LOAD':
            self._cmd_load(arg); return True

        if cmdU == 'SAVE':
            self._cmd_save(arg); return True

        if cmdU == 'IRQ':
            self.cpu.request_irq()
            print(_yellow('IRQ solicitado'))
            return True

        if cmdU == 'NMI':
            self.cpu.request_nmi()
            print(_yellow('NMI solicitado'))
            return True

        # --- Comandos de modo programa ---
        if cmdU == 'PROGRAM':
            self._enter_prog_mode(arg); return True

        if cmdU in ('BACK', 'B') and self._in_prog_mode:
            self._in_prog_mode = False
            print(_dim('← Modo REPL'))
            return True

        if cmdU in ('LIST', 'LS') and self._in_prog_mode:
            show_listing(self.asm.lines,
                         highlight_pc=self.cpu.PC if self._loaded else None)
            return True

        if cmdU == 'RUN' and self._in_prog_mode:
            self._cmd_run(); return True

        if cmdU == 'STEP':
            self._cmd_step(); return True

        if cmdU == 'REWIND' and self._in_prog_mode:
            self.cpu.PC = self._prog_org
            print(_dim(f'PC ← {self._prog_org:#06x}'))
            return True

        if cmdU == 'DELETE' and self._in_prog_mode:
            self._cmd_delete(arg); return True

        # --- Ensamblado ---
        if self._in_prog_mode:
            self._prog_feed(line)
        else:
            self._repl_exec(line)

        return True

    # ------------------------------------------------------------------
    # Modo REPL: ensambla + ejecuta
    # ------------------------------------------------------------------

    def _repl_exec(self, line: str):
        result = self.asm.assemble_line(line, self.cpu.PC)
        if result.error:
            print(_red(f'Error: {result.error}')); return
        if not result.bytes:
            return    # línea vacía o directiva .org sin código

        # Escribir bytes en memoria desde PC actual
        for i, b in enumerate(result.bytes):
            self.cpu.mem[(self.cpu.PC + i) & 0xFFFF] = b

        sr = self.cpu.step()
        show_diff(sr)
        if sr.error:
            print(_red(f'Error de ejecución: {sr.error}'))

    # ------------------------------------------------------------------
    # Modo Programa
    # ------------------------------------------------------------------

    def _enter_prog_mode(self, arg: str):
        if arg.strip():
            v = self._parse_int_arg(arg.strip())
            if v is None:
                print(_red(f'Dirección inválida: {arg}')); return
            org = v & 0xFFFF
        else:
            org = self.cpu.PC
        self._prog_org = org
        self._in_prog_mode = True
        self.asm.reset(org=org)
        self._loaded = False
        print(_cyan(f'Modo programa — .org = {org:#06x}'))

    def _prog_feed(self, line: str):
        al = self.asm.feed(line)
        if al is None:
            return
        if al.error:
            print(_red(f'Error: {al.error}')); return
        if al.size == 0:
            if al.label:
                print(_dim(f'  etiqueta {al.label} → {al.addr:#06x}'))
            return
        hex_b = ' '.join(f'{b:02x}' for b in al.encoded)
        print(_dim(f'  {al.addr:#06x}  [{hex_b}]  {al.mnemonic}'))

    def _cmd_run(self):
        """Enlaza, carga en memoria y ejecuta trazando todos los pasos."""
        binary, lines = self.asm.link()
        errors = [l for l in lines if l.error]
        if errors:
            print(_red('Errores de ensamblado:'))
            for l in errors:
                print(_red(f'  [{l.addr:#06x}] {l.text}  →  {l.error}'))
            return

        # Cargar en memoria
        for i, b in enumerate(binary):
            self.cpu.mem[(self._prog_org + i) & 0xFFFF] = b

        self.cpu.PC   = self._prog_org
        self._loaded  = True
        cycles_before = self.cpu.total_cycles

        print(_dim(f'Programa cargado en {self._prog_org:#06x} '
                   f'({len(binary)} bytes). Ejecutando...\n'))

        max_steps = 100_000
        steps     = 0
        end_addrs = {(self._prog_org + len(binary)) & 0xFFFF}

        while steps < max_steps:
            if self.cpu.PC in end_addrs and not self.cpu.halted:
                print(_dim(f'\nFin del programa (PC={self.cpu.PC:#06x})'))
                break
            sr = self.cpu.step()
            show_step_trace(sr)
            steps += 1

            if sr.halted and not (self.cpu._pending_nmi or
                                  (self.cpu._pending_irq and self.cpu.I)):
                print(_dim('\nCPU en HALT. Usa "irq" o "nmi" para reanudar, '
                            '"step" para un paso.'))
                break
            if sr.mnemonic.startswith('<NMI>') or sr.mnemonic.startswith('<IRQ>'):
                continue
        else:
            print(_yellow(f'\nLímite de {max_steps} pasos alcanzado.'))

        print()
        show_regs(self.cpu)
        prog_cycles = self.cpu.total_cycles - cycles_before
        print(_dim(f'  Programa: {prog_cycles} ciclos'
                   f'  ≈ {prog_cycles / 10:.1f} ns  @ 100 MHz'))

    def _cmd_step(self):
        """Ejecuta una sola instrucción."""
        if not self._loaded and not self._in_prog_mode:
            print(_dim('(sin programa cargado — ejecutando desde PC actual)'))
        sr = self.cpu.step()
        show_step_trace(sr)
        if sr.halted:
            print(_dim('CPU en HALT.'))

    def _cmd_delete(self, arg: str):
        lines = self.asm.lines
        if not lines:
            print(_dim('Buffer vacío')); return
        if arg.strip():
            n = self._parse_int_arg(arg.strip())
            idx = (n - 1) if n else -1
        else:
            idx = -1
        try:
            removed = lines[idx]
            # Reconstruir buffer sin esa línea
            kept = [l for i, l in enumerate(lines) if i != (idx % len(lines))]
            self.asm.reset(org=self._prog_org)
            for l in kept:
                self.asm.feed(l.text)
            print(_dim(f'Eliminada: {removed.mnemonic or removed.text}'))
        except IndexError:
            print(_red('Índice fuera de rango'))

    # ------------------------------------------------------------------
    # Comandos de memoria y registros
    # ------------------------------------------------------------------

    def _cmd_mem(self, arg: str):
        parts = arg.split()
        if not parts:
            show_mem(self.cpu, self.cpu.PC, 64); return
        addr = self._parse_int_arg(parts[0])
        if addr is None:
            print(_red(f'Dirección inválida: {parts[0]}')); return
        n = self._parse_int_arg(parts[1]) if len(parts) > 1 else 64
        n = max(1, min(n or 64, 1024))
        show_mem(self.cpu, addr, n)

    def _cmd_io(self, arg: str):
        parts = arg.split()
        start = self._parse_int_arg(parts[0]) if parts else 0
        n     = self._parse_int_arg(parts[1]) if len(parts) > 1 else 16
        show_io(self.cpu, start or 0, n or 16)

    def _cmd_set(self, arg: str):
        parts = arg.split(None, 1)
        if len(parts) < 2:
            print(_red('Uso: set <reg> <valor>  (regs: A B PC SP F LR I)')); return
        reg  = parts[0].upper()
        val  = self._parse_int_arg(parts[1].strip())
        if val is None:
            print(_red(f'Valor inválido: {parts[1]}')); return
        if reg == 'A':   self.cpu.A  = val & 0xFF
        elif reg == 'B': self.cpu.B  = val & 0xFF
        elif reg == 'PC':self.cpu.PC = val & 0xFFFF
        elif reg == 'SP':self.cpu.SP = val & 0xFFFE
        elif reg == 'F': self.cpu.F  = val & 0xFF
        elif reg == 'LR':self.cpu.LR = val & 0xFFFF
        elif reg == 'I': self.cpu.I  = bool(val)
        else:
            print(_red(f'Registro desconocido: {reg}')); return
        print(_dim(f'{reg} ← {val:#06x}'))

    def _cmd_write(self, arg: str):
        parts = arg.split()
        if len(parts) < 2:
            print(_red('Uso: write <addr> <byte> [byte...]')); return
        addr = self._parse_int_arg(parts[0])
        if addr is None:
            print(_red(f'Dirección inválida: {parts[0]}')); return
        for i, tok in enumerate(parts[1:]):
            v = self._parse_int_arg(tok)
            if v is None:
                print(_red(f'Byte inválido: {tok}')); return
            self.cpu.mem[(addr + i) & 0xFFFF] = v & 0xFF
        print(_dim(f'{len(parts)-1} byte(s) escritos en {addr:#06x}'))

    def _cmd_load(self, arg: str):
        parts = arg.split()
        if not parts:
            print(_red('Uso: load <archivo> [addr]')); return
        fname = parts[0]
        addr  = self._parse_int_arg(parts[1]) if len(parts) > 1 else self.cpu.PC
        addr  = (addr or self.cpu.PC) & 0xFFFF
        try:
            with open(fname, 'rb') as fh:
                data = fh.read()
            for i, b in enumerate(data):
                self.cpu.mem[(addr + i) & 0xFFFF] = b
            self._loaded = True
            print(_green(f'Cargados {len(data)} bytes en {addr:#06x} desde "{fname}"'))
        except OSError as e:
            print(_red(f'Error al cargar: {e}'))

    def _cmd_save(self, arg: str):
        parts = arg.split()
        if len(parts) < 3:
            print(_red('Uso: save <archivo> <addr> <n_bytes>')); return
        fname = parts[0]
        addr  = self._parse_int_arg(parts[1])
        n     = self._parse_int_arg(parts[2])
        if addr is None or n is None:
            print(_red('Dirección o tamaño inválidos')); return
        data = bytes(self.cpu.mem[(addr + i) & 0xFFFF] for i in range(n))
        try:
            with open(fname, 'wb') as fh:
                fh.write(data)
            print(_green(f'Guardados {n} bytes desde {addr:#06x} en "{fname}"'))
        except OSError as e:
            print(_red(f'Error al guardar: {e}'))

    # ------------------------------------------------------------------
    # Utilidades
    # ------------------------------------------------------------------

    @staticmethod
    def _parse_int_arg(s: str) -> int | None:
        if not s:
            return None
        s = s.strip()
        try:
            if s.startswith('0x') or s.startswith('0X'):
                return int(s, 16)
            if s.startswith('0b') or s.startswith('0B'):
                return int(s, 2)
            if s.startswith('0o') or s.startswith('0O'):
                return int(s, 8)
            return int(s, 10)
        except ValueError:
            return None
