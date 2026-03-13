# MIT License — Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
"""
sim/cpu.py — Simulador RTL del procesador de 8 bits (ISA v0.7).

CPU.step() ejecuta una instrucción y devuelve un StepResult con el
diff de registros, memoria y puertos de E/S modificados.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from .alu import (
    ref_ADD, ref_ADC, ref_SUB, ref_SBB, ref_LSL, ref_LSR,
    ref_ROL, ref_ROR, ref_INC, ref_DEC, ref_AND, ref_IOR,
    ref_XOR, ref_NOT, ref_ASL, ref_ASR, ref_SWP, ref_NEG,
    ref_MUL, ref_MUH, ref_CMP, ref_PSA, ref_PSB, ref_CLR,
    ref_SET, ref_INB, ref_DEB,
)

# Máscaras de flag en el registro F
F_C = 0x80; F_H = 0x40; F_V = 0x20; F_Z = 0x10
F_G = 0x08; F_E = 0x04; F_R = 0x02; F_L = 0x01
FLAG_MASK = 0xFF


@dataclass
class StepResult:
    pc_before:  int
    mnemonic:   str
    raw_bytes:  list            # bytes de la instrucción
    cycles:     int
    halted:     bool            = False
    reg_diff:   dict            = field(default_factory=dict)   # {name: (old, new)}
    mem_diff:   list            = field(default_factory=list)   # [(addr, old, new)]
    io_diff:    list            = field(default_factory=list)   # [(port, old, new)]
    error:      str | None      = None


class CPU:
    def __init__(self):
        self.mem = bytearray(65536)
        self.io  = bytearray(256)
        self.soft_reset()

    # ------------------------------------------------------------------
    # Reset
    # ------------------------------------------------------------------

    def soft_reset(self):
        """Reinicia registros sin borrar memoria ni E/S."""
        self.A:       int  = 0
        self.B:       int  = 0
        self.PC:      int  = 0x0000
        self.SP:      int  = 0xFFFE
        self.F:       int  = 0
        self.LR:      int  = 0
        self.I:       bool = False
        self.halted:  bool = False
        self._pending_irq: bool = False
        self._pending_nmi: bool = False

    def hard_reset(self):
        """Reinicia todo, incluyendo memoria y E/S."""
        self.mem = bytearray(65536)
        self.io  = bytearray(256)
        self.soft_reset()

    # ------------------------------------------------------------------
    # Acceso a memoria
    # ------------------------------------------------------------------

    def mem_read(self, addr: int) -> int:
        return self.mem[addr & 0xFFFF]

    def mem_write(self, addr: int, val: int):
        self.mem[addr & 0xFFFF] = val & 0xFF

    def mem_read16(self, addr: int) -> int:
        lo = self.mem[addr & 0xFFFF]
        hi = self.mem[(addr + 1) & 0xFFFF]
        return lo | (hi << 8)

    def mem_write16(self, addr: int, val: int):
        self.mem[addr & 0xFFFF]       = val & 0xFF
        self.mem[(addr + 1) & 0xFFFF] = (val >> 8) & 0xFF

    # ------------------------------------------------------------------
    # Pila (word-aligned, little-endian)
    # ------------------------------------------------------------------

    def push16(self, val: int):
        self.SP = (self.SP - 2) & 0xFFFF
        self.mem[self.SP]         = val & 0xFF
        self.mem[(self.SP+1) & 0xFFFF] = (val >> 8) & 0xFF

    def pop16(self) -> int:
        lo = self.mem[self.SP]
        hi = self.mem[(self.SP + 1) & 0xFFFF]
        self.SP = (self.SP + 2) & 0xFFFF
        return lo | (hi << 8)

    # ------------------------------------------------------------------
    # Flags
    # ------------------------------------------------------------------

    def get_C(self): return (self.F >> 7) & 1
    def get_H(self): return (self.F >> 6) & 1
    def get_V(self): return (self.F >> 5) & 1
    def get_Z(self): return (self.F >> 4) & 1
    def get_G(self): return (self.F >> 3) & 1
    def get_E(self): return (self.F >> 2) & 1
    def get_R(self): return (self.F >> 1) & 1
    def get_L(self): return (self.F >> 0) & 1

    def flags_str(self) -> str:
        names = ['C', 'H', 'V', 'Z', 'G', 'E', 'R', 'L']
        bits  = [(self.F >> (7 - i)) & 1 for i in range(8)]
        return ' '.join(f"{n}:{b}" for n, b in zip(names, bits))

    # ------------------------------------------------------------------
    # Interrupciones
    # ------------------------------------------------------------------

    def request_irq(self):
        self._pending_irq = True

    def request_nmi(self):
        self._pending_nmi = True

    def _handle_interrupt(self, vector_addr: int, mem_diff: list):
        """Push PC y F. Carga PC desde vector. Retorna registros modificados."""
        sp_pre_pc = (self.SP - 2) & 0xFFFF
        mem_diff.append((sp_pre_pc,       self.mem[sp_pre_pc],            self.PC & 0xFF))
        mem_diff.append(((sp_pre_pc+1) & 0xFFFF, self.mem[(sp_pre_pc+1)&0xFFFF], (self.PC>>8) & 0xFF))
        self.push16(self.PC)
        sp_pre_f = (self.SP - 2) & 0xFFFF
        mem_diff.append((sp_pre_f,        self.mem[sp_pre_f],             self.F))
        mem_diff.append(((sp_pre_f+1) & 0xFFFF, self.mem[(sp_pre_f+1)&0xFFFF],  0x00))
        self.push16(self.F)
        self.PC = self.mem_read16(vector_addr)
        self.I  = False

    # ------------------------------------------------------------------
    # Paso de ejecución principal
    # ------------------------------------------------------------------

    def snapshot(self) -> dict:
        return dict(A=self.A, B=self.B, PC=self.PC, SP=self.SP,
                    F=self.F, LR=self.LR, I=int(self.I))

    def _make_reg_diff(self, before: dict) -> dict:
        diff = {}
        after = self.snapshot()
        for k in ('A', 'B', 'PC', 'SP', 'F', 'LR', 'I'):
            if before[k] != after[k]:
                diff[k] = (before[k], after[k])
        return diff

    def step(self) -> StepResult:
        """Ejecuta una instrucción; devuelve StepResult con diffs."""

        mem_diff: list = []
        io_diff:  list = []

        # --- Procesamiento de interrupciones desde estado HALT ---
        if self.halted:
            if self._pending_nmi:
                self._pending_nmi = False
                self.halted = False
                before = self.snapshot()
                self._handle_interrupt(0xFFFA, mem_diff)
                r = StepResult(pc_before=before['PC'], mnemonic='<NMI>',
                               raw_bytes=[], cycles=9, halted=False)
                r.reg_diff = self._make_reg_diff(before)
                r.mem_diff = mem_diff
                return r
            elif self._pending_irq and self.I:
                self._pending_irq = False
                self.halted = False
                before = self.snapshot()
                self._handle_interrupt(0xFFFE, mem_diff)
                r = StepResult(pc_before=before['PC'], mnemonic='<IRQ>',
                               raw_bytes=[], cycles=9, halted=False)
                r.reg_diff = self._make_reg_diff(before)
                r.mem_diff = mem_diff
                return r
            else:
                return StepResult(pc_before=self.PC,
                                  mnemonic='<HALT — esperando IRQ/NMI>',
                                  raw_bytes=[], cycles=0, halted=True)

        before  = self.snapshot()
        pc0     = self.PC
        raw_bytes: list = []

        def fetch8() -> int:
            v = self.mem[self.PC]
            raw_bytes.append(v)
            self.PC = (self.PC + 1) & 0xFFFF
            return v

        def fetch16() -> int:
            lo = fetch8()
            hi = fetch8()
            return lo | (hi << 8)

        def mem_wr(addr: int, val: int):
            addr &= 0xFFFF; val &= 0xFF
            mem_diff.append((addr, self.mem[addr], val))
            self.mem[addr] = val

        def io_wr(port: int, val: int):
            port &= 0xFF; val &= 0xFF
            io_diff.append((port, self.io[port], val))
            self.io[port] = val

        def alu_op(fn, a, b, cin=0, write_a=True) -> int:
            acc, flags = fn(a, b, cin)
            if write_a:
                self.A = acc
            self.F = flags
            return acc

        opcode = fetch8()
        mnemonic = f'??? ({opcode:#04x})'
        cycles   = 2

        # -------------------------------------------------------
        # 0x0x  Sistema
        # -------------------------------------------------------
        if opcode == 0x00:
            mnemonic = 'NOP'; cycles = 2

        elif opcode == 0x01:
            mnemonic = 'HALT'; self.halted = True; cycles = 2

        elif opcode == 0x02:
            mnemonic = 'SEC'; self.F |= F_C; cycles = 2

        elif opcode == 0x03:
            mnemonic = 'CLC'; self.F &= ~F_C & 0xFF; cycles = 2

        elif opcode == 0x04:
            mnemonic = 'SEI'; self.I = True; cycles = 2

        elif opcode == 0x05:
            mnemonic = 'CLI'; self.I = False; cycles = 2

        elif opcode == 0x06:
            mnemonic = 'RTI'
            f_val = self.pop16() & 0xFF
            self.F  = f_val
            self.PC = self.pop16()
            self.I  = True
            cycles  = 6

        # -------------------------------------------------------
        # 0x1x  LD A
        # -------------------------------------------------------
        elif opcode == 0x10:
            mnemonic = 'LD A, B'; alu_op(ref_PSA, self.B, self.B); cycles = 2

        elif opcode == 0x11:
            n = fetch8(); mnemonic = f'LD A, #{n:#04x}'
            self.A = n
            self.F = (self.F & ~F_Z & 0xFF) | (F_Z if n == 0 else 0)
            cycles = 2

        elif opcode == 0x12:
            n = fetch8(); mnemonic = f'LD A, [{n:#04x}]'
            val = self.mem[n]; self.A = val
            self.F = (self.F & ~F_Z & 0xFF) | (F_Z if val == 0 else 0); cycles = 2

        elif opcode == 0x13:
            nn = fetch16(); mnemonic = f'LD A, [{nn:#06x}]'
            val = self.mem_read(nn); self.A = val
            self.F = (self.F & ~F_Z & 0xFF) | (F_Z if val == 0 else 0); cycles = 4

        elif opcode == 0x14:
            mnemonic = 'LD A, [B]'
            val = self.mem[self.B]; self.A = val
            self.F = (self.F & ~F_Z & 0xFF) | (F_Z if val == 0 else 0); cycles = 2

        elif opcode == 0x15:
            nn = fetch16(); mnemonic = f'LD A, [{nn:#06x}+B]'
            addr = (nn + self.B) & 0xFFFF
            val = self.mem_read(addr); self.A = val
            self.F = (self.F & ~F_Z & 0xFF) | (F_Z if val == 0 else 0); cycles = 4

        elif opcode == 0x16:
            n = fetch8(); mnemonic = f'LD A, [{n:#04x}+B]'
            addr = (n + self.B) & 0xFF
            val = self.mem[addr]; self.A = val
            self.F = (self.F & ~F_Z & 0xFF) | (F_Z if val == 0 else 0); cycles = 2

        # -------------------------------------------------------
        # 0x2x  LD B
        # -------------------------------------------------------
        elif opcode == 0x20:
            mnemonic = 'LD B, A'; self.B = self.A; cycles = 2

        elif opcode == 0x21:
            n = fetch8(); mnemonic = f'LD B, #{n:#04x}'; self.B = n; cycles = 2

        elif opcode == 0x22:
            n = fetch8(); mnemonic = f'LD B, [{n:#04x}]'; self.B = self.mem[n]; cycles = 2

        elif opcode == 0x23:
            nn = fetch16(); mnemonic = f'LD B, [{nn:#06x}]'
            self.B = self.mem_read(nn); cycles = 4

        elif opcode == 0x24:
            mnemonic = 'LD B, [B]'; self.B = self.mem[self.B]; cycles = 2

        elif opcode == 0x25:
            nn = fetch16(); mnemonic = f'LD B, [{nn:#06x}+B]'
            self.B = self.mem_read((nn + self.B) & 0xFFFF); cycles = 4

        # -------------------------------------------------------
        # 0x3x  ST A
        # -------------------------------------------------------
        elif opcode == 0x30:
            n = fetch8(); mnemonic = f'ST A, [{n:#04x}]'; mem_wr(n, self.A); cycles = 2

        elif opcode == 0x31:
            nn = fetch16(); mnemonic = f'ST A, [{nn:#06x}]'; mem_wr(nn, self.A); cycles = 4

        elif opcode == 0x32:
            mnemonic = 'ST A, [B]'; mem_wr(self.B, self.A); cycles = 2

        elif opcode == 0x33:
            nn = fetch16(); mnemonic = f'ST A, [{nn:#06x}+B]'
            mem_wr((nn + self.B) & 0xFFFF, self.A); cycles = 4

        elif opcode == 0x34:
            n = fetch8(); mnemonic = f'ST A, [{n:#04x}+B]'
            mem_wr((n + self.B) & 0xFF, self.A); cycles = 2

        # -------------------------------------------------------
        # 0x4x  ST B
        # -------------------------------------------------------
        elif opcode == 0x40:
            n = fetch8(); mnemonic = f'ST B, [{n:#04x}]'; mem_wr(n, self.B); cycles = 2

        elif opcode == 0x41:
            nn = fetch16(); mnemonic = f'ST B, [{nn:#06x}]'; mem_wr(nn, self.B); cycles = 4

        elif opcode == 0x42:
            nn = fetch16(); mnemonic = f'ST B, [{nn:#06x}+B]'
            mem_wr((nn + self.B) & 0xFFFF, self.B); cycles = 4

        # -------------------------------------------------------
        # 0x5x  SP
        # -------------------------------------------------------
        elif opcode == 0x50:
            nn = fetch16(); mnemonic = f'LD SP, #{nn:#06x}'
            self.SP = nn & 0xFFFE; cycles = 4  # bit 0 forzado a 0

        elif opcode == 0x51:
            mnemonic = 'LD SP, A:B'
            self.SP = ((self.A << 8) | self.B) & 0xFFFE; cycles = 2

        elif opcode == 0x52:
            mnemonic = 'ST SP_L, A'           # A ← SP[7:0]
            self.A = self.SP & 0xFF; cycles = 2

        elif opcode == 0x53:
            mnemonic = 'ST SP_H, A'           # A ← SP[15:8]
            self.A = (self.SP >> 8) & 0xFF; cycles = 2

        # -------------------------------------------------------
        # 0x6x  PUSH / POP
        # -------------------------------------------------------
        elif opcode == 0x60:
            mnemonic = 'PUSH A'
            new_sp = (self.SP - 2) & 0xFFFF
            mem_wr(new_sp, self.A); mem_wr((new_sp+1)&0xFFFF, 0x00)
            self.SP = new_sp; cycles = 4

        elif opcode == 0x61:
            mnemonic = 'PUSH B'
            new_sp = (self.SP - 2) & 0xFFFF
            mem_wr(new_sp, self.B); mem_wr((new_sp+1)&0xFFFF, 0x00)
            self.SP = new_sp; cycles = 4

        elif opcode == 0x62:
            mnemonic = 'PUSH F'
            new_sp = (self.SP - 2) & 0xFFFF
            mem_wr(new_sp, self.F); mem_wr((new_sp+1)&0xFFFF, 0x00)
            self.SP = new_sp; cycles = 4

        elif opcode == 0x63:
            mnemonic = 'PUSH A:B'
            new_sp = (self.SP - 2) & 0xFFFF
            mem_wr(new_sp, self.B); mem_wr((new_sp+1)&0xFFFF, self.A)
            self.SP = new_sp; cycles = 4

        elif opcode == 0x64:
            mnemonic = 'POP A'
            val = self.mem[self.SP]; self.A = val
            self.SP = (self.SP + 2) & 0xFFFF
            self.F = (self.F & ~F_Z & 0xFF) | (F_Z if val == 0 else 0); cycles = 4

        elif opcode == 0x65:
            mnemonic = 'POP B'
            self.B = self.mem[self.SP]; self.SP = (self.SP + 2) & 0xFFFF; cycles = 4

        elif opcode == 0x66:
            mnemonic = 'POP F'
            self.F = self.mem[self.SP] & 0xFF; self.SP = (self.SP + 2) & 0xFFFF; cycles = 4

        elif opcode == 0x67:
            mnemonic = 'POP A:B'
            self.B = self.mem[self.SP]
            self.A = self.mem[(self.SP+1) & 0xFFFF]
            self.SP = (self.SP + 2) & 0xFFFF; cycles = 4

        # -------------------------------------------------------
        # 0x7x  Saltos y llamadas
        # -------------------------------------------------------
        elif opcode == 0x70:
            nn = fetch16(); mnemonic = f'JP {nn:#06x}'; self.PC = nn; cycles = 6

        elif opcode == 0x71:
            rel = fetch8()
            if rel >= 0x80: rel -= 0x100
            mnemonic = f'JR {rel:+d}'
            self.PC = (self.PC + rel) & 0xFFFF; cycles = 4

        elif opcode == 0x72:
            pg = fetch8(); mnemonic = f'JPN {pg:#04x}'
            self.PC = (self.PC & 0xFF00) | pg; cycles = 4

        elif opcode == 0x73:
            nn = fetch16(); mnemonic = f'JP ([{nn:#06x}])'
            self.PC = self.mem_read16(nn); cycles = 8

        elif opcode == 0x74:
            mnemonic = 'JP A:B'; self.PC = (self.A << 8) | self.B; cycles = 2

        elif opcode == 0x75:
            nn  = fetch16(); mnemonic = f'CALL {nn:#06x}'
            ret = self.PC              # ya apunta a la sig. instrucción
            mem_diff_pre = list(mem_diff)
            new_sp = (self.SP - 2) & 0xFFFF
            mem_wr(new_sp, ret & 0xFF); mem_wr((new_sp+1)&0xFFFF, (ret>>8)&0xFF)
            self.SP = new_sp; self.LR = ret; self.PC = nn; cycles = 4

        elif opcode == 0x76:
            nn  = fetch16(); mnemonic = f'CALL ([{nn:#06x}])'
            ret = self.PC
            new_sp = (self.SP - 2) & 0xFFFF
            mem_wr(new_sp, ret & 0xFF); mem_wr((new_sp+1)&0xFFFF, (ret>>8)&0xFF)
            self.SP = new_sp; self.LR = ret; self.PC = self.mem_read16(nn); cycles = 6

        elif opcode == 0x77:
            mnemonic = 'RET'; self.PC = self.pop16(); cycles = 2

        # -------------------------------------------------------
        # 0x8x  Ramas condicionales
        # -------------------------------------------------------
        elif 0x80 <= opcode <= 0x8B:
            rel = fetch8()
            if rel >= 0x80: rel -= 0x100
            branch_table = {
                0x80: ('BEQ',  self.get_Z() == 1),
                0x81: ('BNE',  self.get_Z() == 0),
                0x82: ('BCS',  self.get_C() == 1),
                0x83: ('BCC',  self.get_C() == 0),
                0x84: ('BVS',  self.get_V() == 1),
                0x85: ('BVC',  self.get_V() == 0),
                0x86: ('BGT',  self.get_G() == 1),
                0x87: ('BLE',  self.get_G() == 0),
                0x88: ('BGE',  self.get_G() == 1 or self.get_E() == 1),
                0x89: ('BLT',  self.get_G() == 0 and self.get_E() == 0),
                0x8A: ('BHC',  self.get_H() == 1),
                0x8B: ('BEQ2', self.get_E() == 1),
            }
            name, cond = branch_table[opcode]
            mnemonic = f'{name} {rel:+d}'
            if cond:
                self.PC = (self.PC + rel) & 0xFFFF
                cycles = 4
            else:
                cycles = 2

        # -------------------------------------------------------
        # 0x9x  ALU registro A op B
        # -------------------------------------------------------
        elif opcode == 0x90:
            mnemonic = 'ADD'; alu_op(ref_ADD, self.A, self.B); cycles = 2
        elif opcode == 0x91:
            mnemonic = 'ADC'; alu_op(ref_ADC, self.A, self.B, self.get_C()); cycles = 2
        elif opcode == 0x92:
            mnemonic = 'SUB'; alu_op(ref_SUB, self.A, self.B); cycles = 2
        elif opcode == 0x93:
            mnemonic = 'SBB'; alu_op(ref_SBB, self.A, self.B, self.get_C()); cycles = 2
        elif opcode == 0x94:
            mnemonic = 'AND'; alu_op(ref_AND, self.A, self.B); cycles = 2
        elif opcode == 0x95:
            mnemonic = 'OR'; alu_op(ref_IOR, self.A, self.B); cycles = 2
        elif opcode == 0x96:
            mnemonic = 'XOR'; alu_op(ref_XOR, self.A, self.B); cycles = 2
        elif opcode == 0x97:
            mnemonic = 'CMP'; alu_op(ref_CMP, self.A, self.B, write_a=False); cycles = 2
        elif opcode == 0x98:
            mnemonic = 'MUL'; alu_op(ref_MUL, self.A, self.B); cycles = 2
        elif opcode == 0x99:
            mnemonic = 'MUH'; alu_op(ref_MUH, self.A, self.B); cycles = 2

        # -------------------------------------------------------
        # 0xAx  ALU inmediato A op #n
        # -------------------------------------------------------
        elif opcode == 0xA0:
            n=fetch8(); mnemonic=f'ADD #{n:#04x}'; alu_op(ref_ADD,self.A,n); cycles=2
        elif opcode == 0xA1:
            n=fetch8(); mnemonic=f'ADC #{n:#04x}'; alu_op(ref_ADC,self.A,n,self.get_C()); cycles=2
        elif opcode == 0xA2:
            n=fetch8(); mnemonic=f'SUB #{n:#04x}'; alu_op(ref_SUB,self.A,n); cycles=2
        elif opcode == 0xA3:
            n=fetch8(); mnemonic=f'SBB #{n:#04x}'; alu_op(ref_SBB,self.A,n,self.get_C()); cycles=2
        elif opcode == 0xA4:
            n=fetch8(); mnemonic=f'AND #{n:#04x}'; alu_op(ref_AND,self.A,n); cycles=2
        elif opcode == 0xA5:
            n=fetch8(); mnemonic=f'OR #{n:#04x}'; alu_op(ref_IOR,self.A,n); cycles=2
        elif opcode == 0xA6:
            n=fetch8(); mnemonic=f'XOR #{n:#04x}'; alu_op(ref_XOR,self.A,n); cycles=2
        elif opcode == 0xA7:
            n=fetch8(); mnemonic=f'CMP #{n:#04x}'; alu_op(ref_CMP,self.A,n,write_a=False); cycles=2

        # -------------------------------------------------------
        # 0xBx  ALU memoria A op [...]
        # -------------------------------------------------------
        elif opcode == 0xB0:
            n=fetch8();  mnemonic=f'ADD [{n:#04x}]';   alu_op(ref_ADD,self.A,self.mem[n]); cycles=2
        elif opcode == 0xB1:
            nn=fetch16();mnemonic=f'ADD [{nn:#06x}]';  alu_op(ref_ADD,self.A,self.mem_read(nn)); cycles=4
        elif opcode == 0xB2:
            n=fetch8();  mnemonic=f'SUB [{n:#04x}]';   alu_op(ref_SUB,self.A,self.mem[n]); cycles=2
        elif opcode == 0xB3:
            nn=fetch16();mnemonic=f'SUB [{nn:#06x}]';  alu_op(ref_SUB,self.A,self.mem_read(nn)); cycles=4
        elif opcode == 0xB4:
            n=fetch8();  mnemonic=f'AND [{n:#04x}]';   alu_op(ref_AND,self.A,self.mem[n]); cycles=2
        elif opcode == 0xB5:
            n=fetch8();  mnemonic=f'OR [{n:#04x}]';    alu_op(ref_IOR,self.A,self.mem[n]); cycles=2
        elif opcode == 0xB6:
            n=fetch8();  mnemonic=f'XOR [{n:#04x}]';   alu_op(ref_XOR,self.A,self.mem[n]); cycles=2
        elif opcode == 0xB7:
            n=fetch8();  mnemonic=f'CMP [{n:#04x}]';   alu_op(ref_CMP,self.A,self.mem[n],write_a=False); cycles=2
        elif opcode == 0xB8:
            nn=fetch16(); addr=(nn+self.B)&0xFFFF; mnemonic=f'ADD [{nn:#06x}+B]'
            alu_op(ref_ADD,self.A,self.mem_read(addr)); cycles=4
        elif opcode == 0xB9:
            nn=fetch16(); addr=(nn+self.B)&0xFFFF; mnemonic=f'SUB [{nn:#06x}+B]'
            alu_op(ref_SUB,self.A,self.mem_read(addr)); cycles=4
        elif opcode == 0xBA:
            nn=fetch16(); addr=(nn+self.B)&0xFFFF; mnemonic=f'AND [{nn:#06x}+B]'
            alu_op(ref_AND,self.A,self.mem_read(addr)); cycles=4
        elif opcode == 0xBB:
            nn=fetch16(); addr=(nn+self.B)&0xFFFF; mnemonic=f'OR [{nn:#06x}+B]'
            alu_op(ref_IOR,self.A,self.mem_read(addr)); cycles=4
        elif opcode == 0xBC:
            nn=fetch16(); addr=(nn+self.B)&0xFFFF; mnemonic=f'XOR [{nn:#06x}+B]'
            alu_op(ref_XOR,self.A,self.mem_read(addr)); cycles=4
        elif opcode == 0xBD:
            nn=fetch16(); addr=(nn+self.B)&0xFFFF; mnemonic=f'CMP [{nn:#06x}+B]'
            alu_op(ref_CMP,self.A,self.mem_read(addr),write_a=False); cycles=4

        # -------------------------------------------------------
        # 0xCx  Unarias / Desplazamientos
        # -------------------------------------------------------
        elif opcode == 0xC0:
            mnemonic='NOT A'; alu_op(ref_NOT,self.A,0); cycles=2
        elif opcode == 0xC1:
            mnemonic='NEG A'; alu_op(ref_NEG,self.A,0); cycles=2
        elif opcode == 0xC2:
            mnemonic='INC A'; alu_op(ref_INC,self.A,0); cycles=2
        elif opcode == 0xC3:
            mnemonic='DEC A'; alu_op(ref_DEC,self.A,0); cycles=2
        elif opcode == 0xC4:
            # INC B: resultado → B, flags DESCARTADOS (ISA)
            mnemonic='INC B'
            acc, _ = ref_INB(self.A, self.B, 0)
            self.B = acc; cycles=2
        elif opcode == 0xC5:
            # DEC B: resultado → B, flags DESCARTADOS (ISA)
            mnemonic='DEC B'
            acc, _ = ref_DEB(self.A, self.B, 0)
            self.B = acc; cycles=2
        elif opcode == 0xC6:
            mnemonic='CLR A'; alu_op(ref_CLR,self.A,0); cycles=2
        elif opcode == 0xC7:
            mnemonic='SET A'; alu_op(ref_SET,self.A,0); cycles=2
        elif opcode == 0xC8:
            mnemonic='LSL A'; alu_op(ref_LSL,self.A,0); cycles=2
        elif opcode == 0xC9:
            mnemonic='LSR A'; alu_op(ref_LSR,self.A,0); cycles=2
        elif opcode == 0xCA:
            mnemonic='ASL A'; alu_op(ref_ASL,self.A,0); cycles=2
        elif opcode == 0xCB:
            mnemonic='ASR A'; alu_op(ref_ASR,self.A,0); cycles=2
        elif opcode == 0xCC:
            mnemonic='ROL A'; alu_op(ref_ROL,self.A,0); cycles=2
        elif opcode == 0xCD:
            mnemonic='ROR A'; alu_op(ref_ROR,self.A,0); cycles=2
        elif opcode == 0xCE:
            mnemonic='SWAP A'; alu_op(ref_SWP,self.A,0); cycles=2

        # -------------------------------------------------------
        # 0xDx  E/S
        # -------------------------------------------------------
        elif opcode == 0xD0:
            n=fetch8(); mnemonic=f'IN A, #{n:#04x}'
            val=self.io[n]; self.A=val
            self.F=(self.F&~F_Z&0xFF)|(F_Z if val==0 else 0); cycles=4

        elif opcode == 0xD1:
            mnemonic='IN A, [B]'
            val=self.io[self.B]; self.A=val
            self.F=(self.F&~F_Z&0xFF)|(F_Z if val==0 else 0); cycles=2

        elif opcode == 0xD2:
            n=fetch8(); mnemonic=f'OUT #{n:#04x}, A'
            io_wr(n, self.A); cycles=4

        elif opcode == 0xD3:
            mnemonic='OUT [B], A'
            io_wr(self.B, self.A); cycles=2

        # -------------------------------------------------------
        # 0xEx  ADD16 / SUB16  (A:B como par de 16 bits)
        # -------------------------------------------------------
        elif opcode == 0xE0:
            n=fetch8(); mnemonic=f'ADD16 #{n:#04x}'
            n16 = n - 256 if n >= 0x80 else n
            ab=(self.A<<8)|self.B; r,c,v,z=self._alu16(ab, n16)
            self.A=(r>>8)&0xFF; self.B=r&0xFF
            self.F=(self.F&~(F_C|F_V|F_Z)&0xFF)|(F_C if c else 0)|(F_V if v else 0)|(F_Z if z else 0)
            cycles=4

        elif opcode == 0xE1:
            nn=fetch16(); mnemonic=f'ADD16 #{nn:#06x}'
            ab=(self.A<<8)|self.B; r,c,v,z=self._alu16(ab, nn)
            self.A=(r>>8)&0xFF; self.B=r&0xFF
            self.F=(self.F&~(F_C|F_V|F_Z)&0xFF)|(F_C if c else 0)|(F_V if v else 0)|(F_Z if z else 0)
            cycles=6

        elif opcode == 0xE2:
            n=fetch8(); mnemonic=f'SUB16 #{n:#04x}'
            n16 = n - 256 if n >= 0x80 else n
            ab=(self.A<<8)|self.B; r,c,v,z=self._alu16_sub(ab, n16)
            self.A=(r>>8)&0xFF; self.B=r&0xFF
            self.F=(self.F&~(F_C|F_V|F_Z)&0xFF)|(F_C if c else 0)|(F_V if v else 0)|(F_Z if z else 0)
            cycles=4

        elif opcode == 0xE3:
            nn=fetch16(); mnemonic=f'SUB16 #{nn:#06x}'
            ab=(self.A<<8)|self.B; r,c,v,z=self._alu16_sub(ab, nn)
            self.A=(r>>8)&0xFF; self.B=r&0xFF
            self.F=(self.F&~(F_C|F_V|F_Z)&0xFF)|(F_C if c else 0)|(F_V if v else 0)|(F_Z if z else 0)
            cycles=6

        # -------------------------------------------------------
        # 0xFx  BSR / RET LR / CALL LR
        # -------------------------------------------------------
        elif opcode == 0xF0:
            rel=fetch8()
            if rel >= 0x80: rel -= 0x100
            mnemonic=f'BSR {rel:+d}'
            ret=self.PC                          # PC ya apunta a instr+2
            new_sp=(self.SP-2)&0xFFFF
            mem_wr(new_sp, ret&0xFF); mem_wr((new_sp+1)&0xFFFF, (ret>>8)&0xFF)
            self.SP=new_sp; self.LR=ret
            self.PC=(self.PC+rel)&0xFFFF; cycles=3

        elif opcode == 0xF1:
            mnemonic='RET LR'; self.PC=self.LR; cycles=1

        elif opcode == 0xF2:
            nn=fetch16(); mnemonic=f'CALL LR, {nn:#06x}'
            self.LR=self.PC; self.PC=nn; cycles=3

        # -------------------------------------------------------
        result = StepResult(
            pc_before = pc0,
            mnemonic  = mnemonic,
            raw_bytes  = list(raw_bytes),
            cycles    = cycles,
            halted    = self.halted,
        )
        result.reg_diff = self._make_reg_diff(before)
        result.mem_diff = mem_diff
        result.io_diff  = io_diff
        return result

    # ------------------------------------------------------------------
    # Aritmética de 16 bits (ADD16 / SUB16)
    # ------------------------------------------------------------------

    def _alu16(self, a16: int, b16: int):
        """ADD16 sin signo para C; con signo para V. b16 puede ser negativo."""
        b_u = b16 & 0xFFFF
        full = a16 + b_u
        result = full & 0xFFFF
        C = 1 if full > 0xFFFF else 0
        sa = a16 - 0x10000 if a16 >= 0x8000 else a16
        sb = b16 if isinstance(b16, int) and b16 < 0 else (b_u - 0x10000 if b_u >= 0x8000 else b_u)
        sr = result - 0x10000 if result >= 0x8000 else result
        V  = 1 if (sa >= 0) == (sb >= 0) and (sr >= 0) != (sa >= 0) else 0
        Z  = 1 if result == 0 else 0
        return result, C, V, Z

    def _alu16_sub(self, a16: int, b16: int):
        """SUB16: C=no-borrow (1 cuando no hay borrow)."""
        b_u  = b16 & 0xFFFF
        full = a16 - b_u
        result = full & 0xFFFF
        C = 0 if full < 0 else 1
        sa = a16 - 0x10000 if a16 >= 0x8000 else a16
        sb = b_u - 0x10000 if b_u >= 0x8000 else b_u
        sr = result - 0x10000 if result >= 0x8000 else result
        V  = 1 if (sa >= 0) != (sb >= 0) and (sr >= 0) == (sb >= 0) else 0
        Z  = 1 if result == 0 else 0
        return result, C, V, Z
