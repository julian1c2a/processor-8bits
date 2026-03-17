# MIT License — Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
"""
sim/tests/test_cpu_alu.py — Tests unitarios de la ALU a través de CPU.step().

Verifica que cada operación ALU produce el resultado correcto en registros
y flags, integrando cpu.py con alu.py.

Ejecutar:  python -m pytest sim/tests/test_cpu_alu.py  (desde raíz del repo)
           python -m unittest sim.tests.test_cpu_alu
"""

import sys
import os
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from sim.cpu import CPU, F_C, F_Z, F_V, F_H, F_G, F_E, F_L

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_cpu(*opcodes: int) -> CPU:
    """Crea CPU con los bytes dados cargados desde la dirección 0."""
    c = CPU()
    for i, b in enumerate(opcodes):
        c.mem[i] = b & 0xFF
    return c


def step_n(cpu: CPU, n: int):
    """Ejecuta exactamente n pasos."""
    for _ in range(n):
        cpu.step()


# ---------------------------------------------------------------------------
# Sistema
# ---------------------------------------------------------------------------

class TestSystem(unittest.TestCase):

    def test_nop_advances_pc(self):
        c = make_cpu(0x00)
        r = c.step()
        self.assertEqual(r.mnemonic, 'NOP')
        self.assertEqual(r.cycles, 2)
        self.assertEqual(c.PC, 1)

    def test_halt_sets_flag(self):
        c = make_cpu(0x01)
        r = c.step()
        self.assertTrue(c.halted)
        self.assertTrue(r.halted)

    def test_sec_sets_carry(self):
        c = make_cpu(0x02)
        c.step()
        self.assertTrue(c.F & F_C)

    def test_clc_clears_carry(self):
        c = make_cpu(0x02, 0x03)   # SEC; CLC
        c.step(); c.step()
        self.assertFalse(c.F & F_C)

    def test_sei_sets_i(self):
        c = make_cpu(0x04)
        c.step()
        self.assertTrue(c.I)

    def test_cli_clears_i(self):
        c = make_cpu(0x04, 0x05)   # SEI; CLI
        c.step(); c.step()
        self.assertFalse(c.I)


# ---------------------------------------------------------------------------
# Cargas de registros
# ---------------------------------------------------------------------------

class TestLoads(unittest.TestCase):

    def test_ld_a_imm(self):
        c = make_cpu(0x11, 0x42)   # LD A, #0x42
        c.step()
        self.assertEqual(c.A, 0x42)
        self.assertFalse(c.F & F_Z)

    def test_ld_a_imm_zero_sets_z(self):
        c = make_cpu(0x11, 0x00)
        c.step()
        self.assertEqual(c.A, 0x00)
        self.assertTrue(c.F & F_Z)

    def test_ld_b_imm(self):
        c = make_cpu(0x21, 0x07)
        c.step()
        self.assertEqual(c.B, 0x07)

    def test_ld_a_b(self):
        c = make_cpu(0x21, 0xAB, 0x10)  # LD B,#0xAB; LD A,B
        c.step(); c.step()
        self.assertEqual(c.A, 0xAB)

    def test_ld_b_a(self):
        c = make_cpu(0x11, 0xCD, 0x20)  # LD A,#0xCD; LD B,A
        c.step(); c.step()
        self.assertEqual(c.B, 0xCD)


# ---------------------------------------------------------------------------
# ALU registro  A op B
# ---------------------------------------------------------------------------

class TestALURegister(unittest.TestCase):

    def _setup(self, a: int, b: int, *ops: int) -> CPU:
        """Carga A=a, B=b y luego ejecuta los opcodes dados."""
        # LD A,#a (2 bytes); LD B,#b (2 bytes); ops...
        c = make_cpu(0x11, a, 0x21, b, *ops)
        c.step(); c.step()   # cargar A y B
        for _ in ops:
            c.step()
        return c

    def test_add_basic(self):
        c = self._setup(0x07, 0x08, 0x90)
        self.assertEqual(c.A, 0x0F)
        self.assertFalse(c.F & F_C)
        self.assertFalse(c.F & F_Z)

    def test_add_carry_out(self):
        c = self._setup(0xFF, 0x01, 0x90)
        self.assertEqual(c.A, 0x00)
        self.assertTrue(c.F & F_C)
        self.assertTrue(c.F & F_Z)

    def test_adc_with_carry(self):
        # LD A,#7; LD B,#8; SEC; ADC
        c = make_cpu(0x11, 0x07, 0x21, 0x08, 0x02, 0x91)
        step_n(c, 4)
        self.assertEqual(c.A, 0x10)   # 7+8+1=16

    def test_sub_no_borrow(self):
        c = self._setup(0x08, 0x07, 0x92)
        self.assertEqual(c.A, 0x01)
        self.assertTrue(c.F & F_C)    # C=1 → no borrow

    def test_sub_borrow(self):
        c = self._setup(0x07, 0x08, 0x92)
        self.assertEqual(c.A, 0xFF)
        self.assertFalse(c.F & F_C)   # C=0 → borrow

    def test_sbb_with_carry(self):
        # LD A,#7; LD B,#8; SEC; SBB  →  7-8-1 = -2 = 0xFE
        c = make_cpu(0x11, 0x07, 0x21, 0x08, 0x02, 0x93)
        step_n(c, 4)
        self.assertEqual(c.A, 0xFE)

    def test_and(self):
        c = self._setup(0x0F, 0x35, 0x94)
        self.assertEqual(c.A, 0x05)

    def test_or(self):
        c = self._setup(0x0F, 0x35, 0x95)
        self.assertEqual(c.A, 0x3F)

    def test_xor(self):
        c = self._setup(0x0F, 0x35, 0x96)
        self.assertEqual(c.A, 0x3A)

    def test_xor_self_zero(self):
        c = self._setup(0xAB, 0xAB, 0x96)
        self.assertEqual(c.A, 0x00)
        self.assertTrue(c.F & F_Z)

    def test_cmp_leaves_a(self):
        c = self._setup(0x07, 0x05, 0x97)
        self.assertEqual(c.A, 0x07)   # A no cambia

    def test_cmp_equal_sets_e(self):
        c = self._setup(0x05, 0x05, 0x97)
        self.assertTrue(c.F & F_E)    # E=1 cuando A==B

    def test_cmp_gt_sets_g(self):
        c = self._setup(0x08, 0x03, 0x97)
        self.assertTrue(c.F & F_G)    # G=1 cuando A>B signed

    def test_mul_low(self):
        c = self._setup(0x07, 0x08, 0x98)
        self.assertEqual(c.A, 0x38)   # 7*8=56=0x38

    def test_mul_high_zero(self):
        c = self._setup(0x07, 0x08, 0x99)
        self.assertEqual(c.A, 0x00)   # byte alto de 56

    def test_muh_large(self):
        c = self._setup(0xFF, 0xFF, 0x99)
        self.assertEqual(c.A, 0xFE)   # 255*255=65025=0xFE01 → alto=0xFE


# ---------------------------------------------------------------------------
# ALU inmediato  A op #n
# ---------------------------------------------------------------------------

class TestALUImmediate(unittest.TestCase):

    def _ld_then(self, a: int, *ops: int) -> CPU:
        c = make_cpu(0x11, a, *ops)
        c.step()   # LD A,#a
        for _ in range(len(ops) // 2 if ops[0] in (0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7) else 1):
            c.step()
        return c

    def test_add_imm(self):
        c = make_cpu(0x11, 0x07, 0xA0, 0x08)
        c.step(); c.step()
        self.assertEqual(c.A, 0x0F)

    def test_adc_imm_with_carry(self):
        # LD A,#7; SEC; ADC# 8  →  7+8+1=16
        c = make_cpu(0x11, 0x07, 0x02, 0xA1, 0x08)
        step_n(c, 3)
        self.assertEqual(c.A, 0x10)

    def test_sub_imm(self):
        c = make_cpu(0x11, 0x07, 0xA2, 0x08)
        c.step(); c.step()
        self.assertEqual(c.A, 0xFF)
        self.assertFalse(c.F & F_C)   # borrow

    def test_sbb_imm_with_carry(self):
        c = make_cpu(0x11, 0x07, 0x02, 0xA3, 0x08)
        step_n(c, 3)
        self.assertEqual(c.A, 0xFE)

    def test_and_imm(self):
        c = make_cpu(0x11, 0x0F, 0xA4, 0x35)
        c.step(); c.step()
        self.assertEqual(c.A, 0x05)

    def test_or_imm(self):
        c = make_cpu(0x11, 0x0F, 0xA5, 0x35)
        c.step(); c.step()
        self.assertEqual(c.A, 0x3F)

    def test_xor_imm(self):
        c = make_cpu(0x11, 0x0F, 0xA6, 0x35)
        c.step(); c.step()
        self.assertEqual(c.A, 0x3A)

    def test_cmp_imm_no_change(self):
        c = make_cpu(0x11, 0x07, 0xA7, 0x05)
        c.step(); c.step()
        self.assertEqual(c.A, 0x07)


# ---------------------------------------------------------------------------
# ALU memoria  A op [n]
# ---------------------------------------------------------------------------

class TestALUMemory(unittest.TestCase):

    def test_add_zp(self):
        c = CPU()
        c.mem[0x80] = 0x08
        c.mem[0] = 0x11; c.mem[1] = 0x07   # LD A,#7
        c.mem[2] = 0xB0; c.mem[3] = 0x80   # ADD [0x80]
        c.step(); c.step()
        self.assertEqual(c.A, 0x0F)

    def test_sub_zp(self):
        c = CPU()
        c.mem[0x10] = 0x03
        c.mem[0] = 0x11; c.mem[1] = 0x05   # LD A,#5
        c.mem[2] = 0xB2; c.mem[3] = 0x10   # SUB [0x10]
        c.step(); c.step()
        self.assertEqual(c.A, 0x02)

    def test_and_zp(self):
        c = CPU()
        c.mem[0x20] = 0xF0
        c.mem[0] = 0x11; c.mem[1] = 0xFF
        c.mem[2] = 0xB4; c.mem[3] = 0x20   # AND [0x20]
        c.step(); c.step()
        self.assertEqual(c.A, 0xF0)


# ---------------------------------------------------------------------------
# Unarias / Desplazamientos
# ---------------------------------------------------------------------------

class TestUnary(unittest.TestCase):

    def _ld_op(self, val: int, opcode: int) -> CPU:
        c = make_cpu(0x11, val, opcode)
        c.step(); c.step()
        return c

    def test_not(self):
        c = self._ld_op(0xFE, 0xC0)
        self.assertEqual(c.A, 0x01)

    def test_neg_positive(self):
        c = self._ld_op(0x01, 0xC1)
        self.assertEqual(c.A, 0xFF)

    def test_neg_zero(self):
        c = self._ld_op(0x00, 0xC1)
        self.assertEqual(c.A, 0x00)
        self.assertTrue(c.F & F_Z)

    def test_inc(self):
        c = self._ld_op(0xFE, 0xC2)
        self.assertEqual(c.A, 0xFF)

    def test_inc_wrap(self):
        c = self._ld_op(0xFF, 0xC2)
        self.assertEqual(c.A, 0x00)
        self.assertTrue(c.F & F_Z)

    def test_dec(self):
        c = self._ld_op(0xFF, 0xC3)
        self.assertEqual(c.A, 0xFE)

    def test_dec_wrap(self):
        c = self._ld_op(0x00, 0xC3)
        self.assertEqual(c.A, 0xFF)

    def test_inc_b(self):
        c = make_cpu(0x21, 0x05, 0xC4)   # LD B,#5; INC B
        c.step(); c.step()
        self.assertEqual(c.B, 0x06)

    def test_dec_b(self):
        c = make_cpu(0x21, 0x06, 0xC5)   # LD B,#6; DEC B
        c.step(); c.step()
        self.assertEqual(c.B, 0x05)

    def test_clr(self):
        c = self._ld_op(0xAB, 0xC6)
        self.assertEqual(c.A, 0x00)
        self.assertTrue(c.F & F_Z)

    def test_set(self):
        c = self._ld_op(0x00, 0xC7)
        self.assertEqual(c.A, 0xFF)

    def test_swap(self):
        c = self._ld_op(0x0F, 0xCE)
        self.assertEqual(c.A, 0xF0)   # nibbles intercambiados

    def test_swap_symmetric(self):
        c = self._ld_op(0xF0, 0xCE)
        self.assertEqual(c.A, 0x0F)


class TestShifts(unittest.TestCase):

    def _ld_clc_op(self, val: int, opcode: int) -> CPU:
        c = make_cpu(0x11, val, 0x03, opcode)   # LD A,#val; CLC; op
        c.step(); c.step(); c.step()
        return c

    def _ld_sec_op(self, val: int, opcode: int) -> CPU:
        c = make_cpu(0x11, val, 0x02, opcode)   # LD A,#val; SEC; op
        c.step(); c.step(); c.step()
        return c

    def test_lsl(self):
        c = self._ld_clc_op(0xAA, 0xC8)   # 1010_1010 << 1
        self.assertEqual(c.A, 0x54)        # 0101_0100
        self.assertTrue(c.F & F_L)         # LSL: bit 7 saliente → L flag (no C)

    def test_lsr(self):
        c = make_cpu(0x11, 0xAA, 0xC9)
        c.step(); c.step()
        self.assertEqual(c.A, 0x55)        # 0101_0101

    def test_asl(self):
        c = self._ld_clc_op(0xAA, 0xCA)
        self.assertEqual(c.A, 0x54)        # igual que LSL para 0xAA

    def test_asr(self):
        c = make_cpu(0x11, 0xAA, 0xCB)
        c.step(); c.step()
        self.assertEqual(c.A, 0xD5)        # 1101_0101 (extiende bit7)

    def test_rol_c0(self):
        c = self._ld_clc_op(0xAA, 0xCC)
        self.assertEqual(c.A, 0x54)
        self.assertTrue(c.F & F_C)

    def test_rol_c1(self):
        c = self._ld_sec_op(0x01, 0xCC)    # 0x01 rota izq con C=1 → 0x03
        self.assertEqual(c.A, 0x03)

    def test_ror_c0(self):
        c = self._ld_clc_op(0xAA, 0xCD)
        self.assertEqual(c.A, 0x55)
        self.assertFalse(c.F & F_C)

    def test_ror_c1(self):
        c = self._ld_sec_op(0x80, 0xCD)   # 0x80 rota der con C=1 → 0xC0
        self.assertEqual(c.A, 0xC0)


# ---------------------------------------------------------------------------
# Pila y Stack Pointer
# ---------------------------------------------------------------------------

class TestStack(unittest.TestCase):

    def test_push_pop_a(self):
        c = make_cpu(
            0x11, 0xAB,  # LD A,#0xAB
            0x60,         # PUSH A
            0x11, 0x00,  # LD A,#0  (destruye A)
            0x64,         # POP A
        )
        step_n(c, 4)
        self.assertEqual(c.A, 0xAB)

    def test_push_pop_b(self):
        c = make_cpu(
            0x21, 0xCD,  # LD B,#0xCD
            0x61,         # PUSH B
            0x21, 0x00,  # LD B,#0
            0x65,         # POP B
        )
        step_n(c, 4)
        self.assertEqual(c.B, 0xCD)

    def test_push_pop_ab(self):
        c = make_cpu(
            0x11, 0xAB,  # LD A,#0xAB
            0x21, 0xCD,  # LD B,#0xCD
            0x63,         # PUSH A:B
            0x11, 0x00,  # LD A,#0
            0x21, 0x00,  # LD B,#0
            0x67,         # POP A:B
        )
        step_n(c, 6)
        self.assertEqual(c.A, 0xAB)
        self.assertEqual(c.B, 0xCD)

    def test_sp_restored_after_push_pop(self):
        c = CPU()
        sp_before = c.SP
        c.mem[0] = 0x11; c.mem[1] = 0x42   # LD A,#0x42
        c.mem[2] = 0x60                      # PUSH A
        c.mem[3] = 0x64                      # POP A
        step_n(c, 3)
        self.assertEqual(c.SP, sp_before)

    def test_ld_sp_imm(self):
        c = make_cpu(0x50, 0xFE, 0x01)   # LD SP,#0x01FE
        c.step()
        self.assertEqual(c.SP, 0x01FE)

    def test_ld_sp_ab(self):
        c = make_cpu(
            0x11, 0x01,   # LD A,#0x01
            0x21, 0xFE,   # LD B,#0xFE
            0x51,          # LD SP,A:B  → SP = 0x01FE (bit0 forzado a 0)
        )
        step_n(c, 3)
        self.assertEqual(c.SP, 0x01FE)

    def test_rd_sp_l(self):
        c = make_cpu(0x50, 0x34, 0x12, 0x52)   # LD SP,#0x1234; ST SP_L,A
        c.step(); c.step()
        self.assertEqual(c.A, 0x34)

    def test_rd_sp_h(self):
        c = make_cpu(0x50, 0x34, 0x12, 0x53)   # LD SP,#0x1234; ST SP_H,A
        c.step(); c.step()
        self.assertEqual(c.A, 0x12)


# ---------------------------------------------------------------------------
# Saltos incondicionales
# ---------------------------------------------------------------------------

class TestJumps(unittest.TestCase):

    def test_jp_abs(self):
        c = make_cpu(0x70, 0x10, 0x00)   # JP 0x0010
        c.step()
        self.assertEqual(c.PC, 0x0010)

    def test_jr_forward(self):
        c = make_cpu(0x71, 0x05)   # JR +5 desde PC=0x02 → 0x07
        c.step()
        self.assertEqual(c.PC, 0x07)

    def test_jr_backward(self):
        c = CPU()
        c.PC = 0x0010
        c.mem[0x0010] = 0x71
        c.mem[0x0011] = 0xFE & 0xFF   # -2 → PC+2-2=0x0010 (bucle)
        c.step()
        self.assertEqual(c.PC, 0x0010)

    def test_jpn(self):
        c = CPU()
        c.PC = 0x0100
        c.mem[0x0100] = 0x72
        c.mem[0x0101] = 0x30   # JPN 0x30 → PC=0x0130
        c.step()
        self.assertEqual(c.PC, 0x0130)

    def test_jp_ab(self):
        c = make_cpu(
            0x11, 0x01,   # LD A,#0x01
            0x21, 0x20,   # LD B,#0x20
            0x74,          # JP A:B → PC=0x0120
        )
        step_n(c, 3)
        self.assertEqual(c.PC, 0x0120)

    def test_call_ret(self):
        c = CPU()
        # main: CALL 0x0010; NOP
        c.mem[0x0000] = 0x75; c.mem[0x0001] = 0x10; c.mem[0x0002] = 0x00
        c.mem[0x0003] = 0x00   # NOP (destino tras RET)
        # sub @ 0x0010: INC A; RET
        c.mem[0x0010] = 0xC2
        c.mem[0x0011] = 0x77
        c.step()               # CALL
        self.assertEqual(c.PC, 0x0010)
        self.assertEqual(c.LR, 0x0003)
        c.step()               # INC A
        self.assertEqual(c.A, 0x01)
        c.step()               # RET
        self.assertEqual(c.PC, 0x0003)


# ---------------------------------------------------------------------------
# Saltos condicionales
# ---------------------------------------------------------------------------

class TestBranches(unittest.TestCase):

    def _cmp_then_branch(self, a: int, b: int, branch_op: int, offset: int) -> CPU:
        """LD A,#a; LD B,#b; CMP; BCC/BCS/... offset"""
        c = make_cpu(0x11, a, 0x21, b, 0x97, branch_op, offset & 0xFF)
        step_n(c, 4)
        return c

    def test_beq_taken(self):
        c = self._cmp_then_branch(5, 5, 0x80, 0x05)  # Z=1 → taken
        self.assertEqual(c.PC, 0x07 + 5)   # PC tras fetch BEQ=0x07, +5=0x0C

    def test_beq_not_taken(self):
        c = self._cmp_then_branch(5, 3, 0x80, 0x05)  # Z=0 → not taken
        self.assertEqual(c.PC, 0x07)

    def test_bne_taken(self):
        c = self._cmp_then_branch(5, 3, 0x81, 0x03)
        self.assertEqual(c.PC, 0x07 + 3)

    def test_bcs_taken(self):
        # CMP 5,3: 5>=3 → no borrow → C=1
        c = self._cmp_then_branch(5, 3, 0x82, 0x03)
        self.assertEqual(c.PC, 0x07 + 3)

    def test_bcc_taken(self):
        # CMP 3,5: 3<5 → borrow → C=0
        c = self._cmp_then_branch(3, 5, 0x83, 0x03)
        self.assertEqual(c.PC, 0x07 + 3)

    def test_bgt_taken(self):
        # CMP 8,3: 8>3 signed → G=1
        c = self._cmp_then_branch(8, 3, 0x86, 0x03)
        self.assertEqual(c.PC, 0x07 + 3)

    def test_ble_taken(self):
        # CMP 3,8: 3<8 → G=0
        c = self._cmp_then_branch(3, 8, 0x87, 0x03)
        self.assertEqual(c.PC, 0x07 + 3)


# ---------------------------------------------------------------------------
# ADD16 / SUB16
# ---------------------------------------------------------------------------

class TestALU16(unittest.TestCase):

    def _ab(self, cpu: CPU) -> int:
        return (cpu.A << 8) | cpu.B

    def test_add16_imm8(self):
        c = make_cpu(0x11, 0x00, 0x21, 0xFF, 0xE0, 0x01)   # A:B=0x00FF; ADD16 #1
        step_n(c, 3)
        self.assertEqual(self._ab(c), 0x0100)

    def test_add16_imm16(self):
        c = make_cpu(0x11, 0x01, 0x21, 0x00, 0xE1, 0x01, 0x00)  # A:B=0x0100; ADD16 #0x0001
        step_n(c, 3)
        self.assertEqual(self._ab(c), 0x0101)

    def test_sub16_imm8(self):
        c = make_cpu(0x11, 0x01, 0x21, 0x01, 0xE2, 0x01)   # A:B=0x0101; SUB16 #1
        step_n(c, 3)
        self.assertEqual(self._ab(c), 0x0100)

    def test_sub16_imm16(self):
        c = make_cpu(0x11, 0x01, 0x21, 0x00, 0xE3, 0x01, 0x00)  # A:B=0x0100; SUB16 #0x0001
        step_n(c, 3)
        self.assertEqual(self._ab(c), 0x00FF)

    def test_add16_overflow_carry(self):
        c = make_cpu(0x11, 0xFF, 0x21, 0xFF, 0xE0, 0x01)   # A:B=0xFFFF; ADD16 #1
        step_n(c, 3)
        self.assertEqual(self._ab(c), 0x0000)
        self.assertTrue(c.F & F_C)
        self.assertTrue(c.F & F_Z)


# ---------------------------------------------------------------------------
# Interrupciones
# ---------------------------------------------------------------------------

class TestInterrupts(unittest.TestCase):

    def test_irq_jumps_to_vector(self):
        c = CPU()
        # Vector IRQ @ 0xFFFE = 0x0050
        c.mem[0xFFFE] = 0x50; c.mem[0xFFFF] = 0x00
        c.mem[0] = 0x04   # SEI
        c.mem[1] = 0x01   # HALT
        c.step()           # SEI
        c.step()           # HALT → cpu.halted=True
        c.request_irq()
        c.step()           # procesa IRQ desde HALT
        self.assertFalse(c.halted)
        self.assertEqual(c.PC, 0x0050)

    def test_irq_ignored_when_i_false(self):
        c = CPU()
        c.mem[0xFFFE] = 0x50; c.mem[0xFFFF] = 0x00
        c.mem[0] = 0x01   # HALT (sin SEI, I=False)
        c.step()           # HALT
        c.request_irq()
        c.step()           # intenta procesar → no puede (I=False)
        self.assertTrue(c.halted)  # sigue halted

    def test_nmi_jumps_to_vector(self):
        c = CPU()
        c.mem[0xFFFA] = 0x60; c.mem[0xFFFB] = 0x00
        c.mem[0] = 0x01   # HALT
        c.step()           # HALT
        c.request_nmi()
        c.step()           # NMI no necesita I
        self.assertEqual(c.PC, 0x0060)

    def test_rti_restores_pc_and_f(self):
        c = CPU()
        # Poner un F conocido
        c.F = 0x10          # Z=1
        c.mem[0xFFFE] = 0x10; c.mem[0xFFFF] = 0x00  # IRQ vector → 0x0010
        c.mem[0x0000] = 0x04   # SEI
        c.mem[0x0001] = 0x01   # HALT @ 0x0001; retorno = 0x0002
        c.mem[0x0002] = 0x00   # NOP (destino tras RTI)
        c.mem[0x0010] = 0x06   # RTI
        c.step()               # SEI
        c.step()               # HALT
        c.request_irq()
        c.step()               # procesa IRQ → PC=0x0010
        c.step()               # RTI → regresa a 0x0002
        self.assertEqual(c.PC, 0x0002)
        self.assertEqual(c.F & 0xFF, 0x10)  # F restaurado


if __name__ == '__main__':
    unittest.main()
